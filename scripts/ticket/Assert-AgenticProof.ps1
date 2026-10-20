#Requires -Version 7
<#
.SYNOPSIS
    Check the Agentic-Proof trailer on a work commit (advisory PR check, standalone).

.DESCRIPTION
    Standalone on purpose: it dot-sources nothing from this repo, so the single file can be copied
    into a product repo's Azure Pipelines step. The diff args and hashing below are a copy of
    scripts/ticket/lib/ManifestFields.ps1 (CanonicalDiffArgs, Get-GitDiffText,
    Get-DiffFingerprintFromText, EmptyTreeSha); keep them in step with that file.

    Picks the work commit: the newest first-parent non-merge commit in <Base>..<Commit> (or
    walking back from <Commit> when no -Base), so a merge of the base branch on top is skipped.
    Reads its trailer, parses

      Agentic-Proof: v1 fp=<64 hex> verify=pass evidence=<12 hex|none> review=<ready|ready-with-fixes>

    and recomputes fp from that commit's diff against its first parent (empty tree for a root
    commit). The proof is self-asserted: it shows a commit was stamped, not that it was run.

    Output: [PASS] / [FAIL] / [INFO] agentic-proof lines (or one JSON object with -Json).
    Exit 0 for PASS; a missing trailer is INFO and exits 0 unless -Require (exit 1). A trailer that
    is present but invalid or mismatched always exits 1.

.PARAMETER RepoPath
    Git working tree to check.

.PARAMETER Commit
    Tip to start from. Defaults to HEAD.

.PARAMETER Base
    Optional base ref; only commits in Base..Commit are considered.

.PARAMETER Require
    Treat a missing trailer as a failure.

.PARAMETER Json
    Print one object {ok, sha, reason, present} instead of the text line.

.EXAMPLE
    pwsh -File Assert-AgenticProof.ps1 -RepoPath . -Base origin/dev -Require
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoPath,
    [string]$Commit = 'HEAD',
    [string]$Base,
    [switch]$Require,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Copy of ManifestFields.ps1 CanonicalDiffArgs / EmptyTreeSha (fpVersion 2).
$CanonicalDiffArgs = @('--no-color', '--no-ext-diff', '--no-textconv', '--full-index', '--src-prefix=a/', '--dst-prefix=b/')
$AsJson = $Json.IsPresent
$EmptyTreeSha = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'

# Copy of ManifestFields.ps1 Get-GitDiffText: $null on git failure, '' for empty output.
function Get-GitText {
    param([Parameter(Mandatory)][string[]]$GitArgs)
    # Process + explicit UTF-8, not native-command output (decoded with the console code page, which
    # is the OEM page under Node or Git Bash). ReadLine splits on \r\n, \n and a lone \r like pwsh.
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'git'
    $psi.ArgumentList.Add('-C')
    $psi.ArgumentList.Add($RepoPath)
    foreach ($a in $GitArgs) { $psi.ArgumentList.Add([string]$a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = (Get-Location).ProviderPath   # a relative RepoPath resolves like it did for & git
    $proc = [Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    try {
        try { [void]$proc.Start() } catch { return $null }   # git missing or not startable: same "git failed" result as before
        $errTask = $proc.StandardError.ReadToEndAsync()
        $lines = [System.Collections.Generic.List[string]]::new()
        while ($null -ne ($line = $proc.StandardOutput.ReadLine())) { $lines.Add($line) }
        $proc.WaitForExit()
        [void]$errTask.Wait()
        if ($proc.ExitCode -ne 0) { return $null }
        if ($lines.Count -eq 0) { return '' }
        return ($lines -join "`n")
    } finally {
        $proc.Dispose()
    }
}

# Copy of ManifestFields.ps1 Get-DiffFingerprintFromText.
function Get-DiffFingerprintFromText {
    param([AllowEmptyString()][string]$Diff)
    if ([string]::IsNullOrEmpty($Diff)) { return $null }
    $bytes = [Text.Encoding]::UTF8.GetBytes($Diff)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return (([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant())
    } finally {
        $sha.Dispose()
    }
}

function Complete-Check {
    param([bool]$Ok, [string]$Sha, [string]$Reason, [bool]$Present, [string]$Level)
    $short = if ($Sha) { $Sha.Substring(0, [Math]::Min(7, $Sha.Length)) } else { '-' }
    if ($AsJson) {
        [pscustomobject]@{ ok = $Ok; sha = $Sha; reason = $Reason; present = $Present } | ConvertTo-Json -Compress
    } else {
        $text = switch ($Level) {
            'PASS' { "[PASS] agentic-proof: $short $Reason" }
            'INFO' { "[INFO] agentic-proof: no Agentic-Proof trailer on $short" }
            default { "[FAIL] agentic-proof: $Reason" }
        }
        Write-Output $text
    }
    if ($Ok) { exit 0 } else { exit 1 }
}

if (-not (Test-Path -LiteralPath $RepoPath)) {
    Complete-Check -Ok $false -Sha '' -Reason "repo path not found: $RepoPath" -Present $false -Level 'FAIL'
}

# First-parent history, newest first: "<sha> <parent> [<parent>...]".
$range = if ($Base) { "$Base..$Commit" } else { $Commit }
$listing = Get-GitText -GitArgs @('rev-list', '--first-parent', '--parents', '--max-count=50', $range)
if ($null -eq $listing) {
    Complete-Check -Ok $false -Sha '' -Reason "cannot list commits for '$range' (unknown ref, or shallow clone missing the base)" -Present $false -Level 'FAIL'
}
$work = $null
foreach ($line in ($listing -split "`n")) {
    $parts = @($line.Trim() -split '\s+' | Where-Object { $_ })
    if ($parts.Count -eq 0) { continue }
    if ($parts.Count -gt 2) { continue }   # merge commit: not the work
    $work = [pscustomobject]@{ sha = $parts[0]; parent = $(if ($parts.Count -gt 1) { $parts[1] } else { $null }) }
    break
}
if (-not $work) {
    Complete-Check -Ok $false -Sha '' -Reason "no non-merge commit in '$range'" -Present $false -Level 'FAIL'
}
$sha = $work.sha.ToLowerInvariant()

# Trailer.
$trailerRaw = Get-GitText -GitArgs @('log', '-1', '--format=%(trailers:key=Agentic-Proof,valueonly,unfold)', $sha)
$values = @(if ($trailerRaw) { $trailerRaw -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } })
if ($values.Count -eq 0) {
    if ($Require) {
        Complete-Check -Ok $false -Sha $sha -Reason "no Agentic-Proof trailer on $($sha.Substring(0, 7)) (required)" -Present $false -Level 'FAIL'
    }
    Complete-Check -Ok $true -Sha $sha -Reason 'no trailer' -Present $false -Level 'INFO'
}
$value = $values[-1]

$m = [regex]::Match($value, '^v(?<v>\d+) fp=(?<fp>\S+) verify=(?<verify>\S+) evidence=(?<ev>\S+) review=(?<review>\S+)$')
if (-not $m.Success) {
    Complete-Check -Ok $false -Sha $sha -Reason "malformed trailer on $($sha.Substring(0, 7))" -Present $true -Level 'FAIL'
}
if ($m.Groups['v'].Value -ne '1') {
    Complete-Check -Ok $false -Sha $sha -Reason "unknown proof version v$($m.Groups['v'].Value) on $($sha.Substring(0, 7))" -Present $true -Level 'FAIL'
}
if ($m.Groups['fp'].Value -notmatch '^[0-9a-f]{64}$') {
    Complete-Check -Ok $false -Sha $sha -Reason "fp is not 64 lowercase hex on $($sha.Substring(0, 7))" -Present $true -Level 'FAIL'
}
if ($m.Groups['ev'].Value -notmatch '^([0-9a-f]{12}|none)$') {
    Complete-Check -Ok $false -Sha $sha -Reason "evidence is not 12 lowercase hex or none on $($sha.Substring(0, 7))" -Present $true -Level 'FAIL'
}
if ($m.Groups['verify'].Value -ne 'pass') {
    Complete-Check -Ok $false -Sha $sha -Reason "verify is '$($m.Groups['verify'].Value)', not pass, on $($sha.Substring(0, 7))" -Present $true -Level 'FAIL'
}
if ($m.Groups['review'].Value -cnotin @('ready', 'ready-with-fixes')) {
    Complete-Check -Ok $false -Sha $sha -Reason "review is '$($m.Groups['review'].Value)', not ready or ready-with-fixes, on $($sha.Substring(0, 7))" -Present $true -Level 'FAIL'
}

# Recompute fp from the commit's diff against its first parent.
$from = $EmptyTreeSha
if ($work.parent) {
    $parentOk = Get-GitText -GitArgs @('cat-file', '-e', "$($work.parent)^{commit}")
    if ($null -eq $parentOk) {
        Complete-Check -Ok $false -Sha $sha -Reason "parent of $($sha.Substring(0, 7)) is not available (shallow clone? fetch more history)" -Present $true -Level 'FAIL'
    }
    $from = $work.parent
} else {
    $shallow = Get-GitText -GitArgs @('rev-parse', '--is-shallow-repository')
    if ($shallow -and $shallow.Trim() -eq 'true') {
        $file = Get-GitText -GitArgs @('rev-parse', '--git-path', 'shallow')
        $path = if ($file) { Join-Path $RepoPath $file.Trim() } else { $null }
        if ($path -and (Test-Path -LiteralPath $path) -and (@(Get-Content -LiteralPath $path) -contains $sha)) {
            Complete-Check -Ok $false -Sha $sha -Reason "parent of $($sha.Substring(0, 7)) is not available (shallow clone boundary; fetch more history)" -Present $true -Level 'FAIL'
        }
    }
}
$diff = Get-GitText -GitArgs (@('diff') + $CanonicalDiffArgs + @($from, $sha))
if ($null -eq $diff) {
    Complete-Check -Ok $false -Sha $sha -Reason "cannot diff $($sha.Substring(0, 7)) against its parent" -Present $true -Level 'FAIL'
}
$actual = Get-DiffFingerprintFromText -Diff $diff
if (-not $actual) {
    Complete-Check -Ok $false -Sha $sha -Reason "commit $($sha.Substring(0, 7)) has an empty diff; nothing to prove" -Present $true -Level 'FAIL'
}
if ($actual -ne $m.Groups['fp'].Value) {
    Complete-Check -Ok $false -Sha $sha -Reason "fingerprint mismatch on $($sha.Substring(0, 7)): the commit's diff is not the work that was verified and reviewed" -Present $true -Level 'FAIL'
}
Complete-Check -Ok $true -Sha $sha -Reason "fp matches (verify=pass, review=$($m.Groups['review'].Value))" -Present $true -Level 'PASS'
