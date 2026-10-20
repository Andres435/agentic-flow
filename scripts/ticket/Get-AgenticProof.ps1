#Requires -Version 7
<#
.SYNOPSIS
    Print the one-line Agentic-Proof commit trailer for the staged work of one repo.

.DESCRIPTION
    Reads the ticket manifest and, only when the repo was verified and reviewed on exactly the
    staged work, prints:

      Agentic-Proof: v1 fp=<sha256> verify=pass evidence=<12 hex|none> review=<ready|ready-with-fixes>

    fp is the SHA-256 fingerprint of the staged diff, computed exactly as the verify and review
    stamps compute it (ManifestFields.ps1 Get-StagedDiffFingerprint). A staged diff taken just
    before `git commit` is byte-identical to that commit's diff against its first parent, so
    Assert-AgenticProof.ps1 can recompute it from the commit alone. Only hashes and verdict
    words appear: no ticket text, paths, or code. The proof is self-asserted (forgeable by hand).

    Throws (no output line) unless: verify.repos.<repo> has pass true and tests pass or
    not-run-with-reason (a tests=pass receipt with evidenceVersion must carry evidence.sha256);
    reviewReady.repos.<repo> is Ready or Ready with fixes; the staged diff is non-empty; and both
    stamps still describe the staged work (Test-ReviewedWorkPresent).

.PARAMETER Ticket
    Work item, with or without the profile ticketPrefix.

.PARAMETER Repo
    Repo name as it appears in the manifest's verify/reviewReady entries.

.PARAMETER RepoPath
    Repo working tree. Resolved through Resolve-TicketRoot when omitted and no -Root.

.PARAMETER Root
    Override the workflow repo root (tests).

.EXAMPLE
    git commit -m "msg" -m "$(.\Get-AgenticProof.ps1 -Ticket WI21961 -Repo app)"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Ticket,
    [Parameter(Mandatory)][string]$Repo,
    [string]$RepoPath,
    [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path $PSScriptRoot 'lib') 'ManifestFields.ps1')

$Key = Get-TicketKeyFromRaw -Ticket $Ticket
$RepoRoot = if ($Root) { $Root } else { Get-CursorRepoRoot -FromScriptRoot $PSScriptRoot }
$manifestPath = Get-TicketManifestFile -RepoRoot $RepoRoot -TicketKey $Key
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest not found: $manifestPath"
}

if (-not $RepoPath -and -not $Root) {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $resolvedJson = & (Join-Path $PSScriptRoot 'Resolve-TicketRoot.ps1') -Ticket $Key -Json 2>$null
        if ($LASTEXITCODE -eq 0 -and $resolvedJson) {
            $hit = @(($resolvedJson | ConvertFrom-Json).repos) | Where-Object { $_ -and $_.repo -eq $Repo } | Select-Object -First 1
            if ($hit -and $hit.path) { $RepoPath = [string]$hit.path }
        }
    } finally {
        $ErrorActionPreference = $prevEap
    }
}
if (-not $RepoPath -or -not (Test-Path -LiteralPath $RepoPath)) {
    throw "No working tree found for $Repo; pass -RepoPath."
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$names = @($manifest.PSObject.Properties.Name)

function Get-RepoEntry {
    param($Section, [string]$Name)
    if (-not $Section) { return $null }
    if (-not ($Section.PSObject.Properties.Name -contains 'repos') -or -not $Section.repos) { return $null }
    if (-not ($Section.repos.PSObject.Properties.Name -contains $Name)) { return $null }
    return $Section.repos.$Name
}

$verifySection = if ($names -contains 'verify') { $manifest.verify } else { $null }
$reviewSection = if ($names -contains 'reviewReady') { $manifest.reviewReady } else { $null }
$verify = Get-RepoEntry -Section $verifySection -Name $Repo
$review = Get-RepoEntry -Section $reviewSection -Name $Repo
$reviewStampMode = Get-StampEntryValue $reviewSection 'mode'
if (-not $reviewStampMode) { $reviewStampMode = 'staged' }

# Verify receipt: boolean pass, tests pass or not-run with a reason.
if (-not $verify) { throw "No verify receipt for $Repo; run verify-repo, then Set-VerifyReceipt.ps1." }
$vNames = @($verify.PSObject.Properties.Name)
if (-not (($vNames -contains 'pass') -and ($verify.pass -is [bool]) -and $verify.pass)) {
    throw "verify.repos.$Repo.pass is not boolean true; fix the failures and re-run Set-VerifyReceipt.ps1."
}
$tests = Get-StampEntryValue $verify 'tests'
$evidenceShort = 'none'
if ($tests -eq 'not-run') {
    if ([string]::IsNullOrWhiteSpace((Get-StampEntryValue $verify 'reason'))) {
        throw "verify.repos.$Repo has tests not-run without a reason."
    }
} elseif ($tests -eq 'pass') {
    if ($vNames -contains 'evidenceVersion') {
        $sha = ''
        if (($vNames -contains 'evidence') -and $verify.evidence -and ($verify.evidence.PSObject.Properties.Name -contains 'sha256')) {
            $sha = [string]$verify.evidence.sha256
        }
        if ($sha -notmatch '^[0-9a-fA-F]{64}$') {
            throw "verify.repos.$Repo has no evidence.sha256; re-run Set-VerifyReceipt.ps1 with -Evidence <.trx or log>."
        }
        $evidenceShort = $sha.Substring(0, 12).ToLowerInvariant()
    }
} else {
    throw "verify.repos.$Repo tests is '$tests'; only pass or not-run (with a reason) can be proven."
}

# Review stamp.
if (-not $review) { throw "No reviewReady entry for $Repo; run /review-changes, then Set-ReviewReady.ps1." }
$verdict = (Get-StampEntryValue $review 'verdict').Replace('*', '').Trim()
$verdictWord = switch -Regex ($verdict) {
    '^(?i)Ready$' { 'ready'; break }
    '^(?i)Ready with fixes$' { 'ready-with-fixes'; break }
    '^(?i)No change$' { throw "reviewReady.repos.$Repo is 'No change': there is nothing to prove." }
    default { throw "reviewReady.repos.$Repo verdict is '$verdict'; only Ready or Ready with fixes can be proven." }
}

$fp = Get-StagedDiffFingerprint -RepoPath $RepoPath
if (-not $fp) { throw "Nothing staged in $RepoPath; stage the verified and reviewed change first." }

$vCheck = Test-ReviewedWorkPresent -RepoPath $RepoPath -Entry $verify
if (-not $vCheck.ok) { throw "verify receipt is stale ($($vCheck.reason)); re-run verify-repo, then Set-VerifyReceipt.ps1." }
$rCheck = Test-ReviewedWorkPresent -RepoPath $RepoPath -Entry $review -StampMode $reviewStampMode
if (-not $rCheck.ok) { throw "review stamp is stale ($($rCheck.reason)); re-review, then Set-ReviewReady.ps1." }

Write-Output "Agentic-Proof: v1 fp=$fp verify=pass evidence=$evidenceShort review=$verdictWord"
