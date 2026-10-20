#Requires -Version 7
<#
.SYNOPSIS
    Record one repo's verify-repo result on the ticket manifest (manifest.verify).

.DESCRIPTION
    /complete-task step 1 calls this once per verify-repo packet. It writes
    manifest.verify.repos.<repo>; calling again for the same repo replaces that
    entry and keeps the others. The manifest is the one record: there is no
    separate verify file. Assert-TicketArtifacts -Phase close requires an entry
    with boolean pass true for every local affected repo (spikes are exempt).

    pass is true only when tests passed (or were not run, with a reason) and
    Sonar did not report an error, and no failing test names were given.

.PARAMETER Ticket
    Work item, with or without the ticket prefix.

.PARAMETER Repo
    Repo name as it appears in the manifest's affectedRepos.

.PARAMETER Tests
    pass | fail | not-run, from the verify-repo packet.

.PARAMETER Sonar
    ok | error | not-run. Map the packet's skipped(...) to not-run.

.PARAMETER Failing
    Failing test or check names. Any entry makes pass false.

.PARAMETER Reason
    Required when -Tests is not-run (for example "docs-only change").

.PARAMETER RepoPath
    Repo working tree, to record the work the result was taken on: HEAD plus the
    staged diff's fingerprint (same shape as a reviewReady entry). -Phase close
    compares that to the repo, so a receipt taken before a later fix fails.
    Resolved through Resolve-TicketRoot when omitted.

.PARAMETER Evidence
    Required with -Tests pass or fail; ignored for not-run. A test result file (.trx)
    or a captured console log. It is copied to evidence/<Key>/<Repo>-verify<ext> in
    the plans folder next to the manifest (plans/, or apps/<id>/plans/ for an app; a re-run overwrites it;
    the source is left alone), and that path (relative to the folder holding plans/), its
    sha256, byte size and kind (trx|log) are recorded on the entry. A .trx also records counts (total, passed, failed); a pass
    is refused when failed > 0 or total is 0. Close re-hashes the file if it still exists.

.PARAMETER Root
    Override the workflow repo root (tests).

.EXAMPLE
    .\Set-VerifyReceipt.ps1 -Ticket TICKET-42 -Repo app -Tests pass -Sonar ok -Evidence TestResults/run.trx
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Ticket,
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][ValidateSet('pass', 'fail', 'not-run')][string]$Tests,
    [Parameter(Mandatory)][ValidateSet('ok', 'error', 'not-run')][string]$Sonar,
    [string[]]$Failing,
    [string]$Reason,
    [string]$RepoPath,
    [string]$Evidence,
    [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path $PSScriptRoot 'lib') 'ManifestFields.ps1')

if ($Tests -eq 'not-run' -and [string]::IsNullOrWhiteSpace($Reason)) {
    throw "-Tests not-run needs -Reason (why no tests ran)."
}

$Key = Get-TicketKeyFromRaw -Ticket $Ticket
$RepoRoot = if ($Root) { $Root } else { Get-CursorRepoRoot -FromScriptRoot $PSScriptRoot }
$manifestPath = Get-TicketManifestFile -RepoRoot $RepoRoot -TicketKey $Key
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest not found: $manifestPath"
}

$evidenceObj = $null
if ($Tests -ne 'not-run') {
    if ([string]::IsNullOrWhiteSpace($Evidence)) {
        throw "-Tests $Tests needs -Evidence <.trx or log file> so the result is backed by a file, not the agent's word."
    }
    if (-not (Test-Path -LiteralPath $Evidence -PathType Leaf)) {
        throw "Evidence file not found: $Evidence"
    }
    $evFull = (Resolve-Path -LiteralPath $Evidence).ProviderPath
    $evKind = if ($evFull -match '\.trx$') { 'trx' } else { 'log' }
    $counts = $null
    if ($evKind -eq 'trx') {
        $xml = New-Object System.Xml.XmlDocument
        $xml.Load($evFull)
        $counters = $xml.SelectSingleNode("//*[local-name()='ResultSummary']/*[local-name()='Counters']")
        if (-not $counters) { throw "Evidence $Evidence has no ResultSummary/Counters; not a test result file." }
        $counts = [ordered]@{
            total  = [int]$counters.GetAttribute('total')
            passed = [int]$counters.GetAttribute('passed')
            failed = [int]$counters.GetAttribute('failed')
        }
        if ($Tests -eq 'pass') {
            if ($counts.failed -gt 0) { throw "-Tests pass but $Evidence reports $($counts.failed) failed test(s)." }
            if ($counts.total -eq 0) { throw "-Tests pass but $Evidence ran zero tests; a pass with zero tests is not evidence." }
        }
    }

    # Keep the evidence in an evidence folder beside the manifest (plans/ or apps/<id>/plans/), one fixed name per ticket and
    # repo so a re-run overwrites the last result. The source stays where it was (tmp scratch).
    $evExt = [System.IO.Path]::GetExtension($evFull).ToLowerInvariant()
    $safeRepo = $Repo -replace '[^A-Za-z0-9._-]', '_'
    $evDir = Join-Path (Join-Path (Split-Path -Parent $manifestPath) 'evidence') $Key
    $evDest = Join-Path $evDir "$safeRepo-verify$evExt"
    New-Item -ItemType Directory -Path $evDir -Force | Out-Null
    $sameFile = (Test-Path -LiteralPath $evDest -PathType Leaf) -and
        ([System.IO.Path]::GetFullPath($evFull) -eq [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $evDest).ProviderPath))
    if (-not $sameFile) { Copy-Item -LiteralPath $evFull -Destination $evDest -Force }

    $evidenceObj = [ordered]@{
        path   = "plans/evidence/$Key/$safeRepo-verify$evExt"
        sha256 = (Get-FileHash -LiteralPath $evDest -Algorithm SHA256).Hash.ToLowerInvariant()
        bytes  = (Get-Item -LiteralPath $evDest).Length
        kind   = $evKind
    }
    if ($counts) { $evidenceObj.counts = [pscustomobject]$counts }
    $evidenceObj = [pscustomobject]$evidenceObj
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
$headSha = if ($RepoPath) { Get-GitHeadSha -RepoPath $RepoPath } else { $null }
# Same work identity as a review stamp: staged diff when there is one, else HEAD.
$fp = if ($RepoPath) { Get-StagedDiffFingerprint -RepoPath $RepoPath } else { $null }
$workMode = if ($fp) { 'staged' } else { 'pre-merge' }

$failingList = @($Failing | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$pass = ($Tests -ne 'fail') -and ($Sonar -ne 'error') -and ($failingList.Count -eq 0)

$entry = [pscustomobject]@{
    pass        = [bool]$pass
    tests       = $Tests
    sonar       = $Sonar
    failing     = $failingList
    reason      = if ($Reason) { $Reason } else { $null }
    headSha     = $headSha
    mode        = if ($headSha) { $workMode } else { $null }
    fingerprint = $fp
    fpVersion   = 2
    atUtc       = [DateTime]::UtcNow.ToString('o')
}
if ($evidenceObj) {
    $entry | Add-Member -NotePropertyName evidenceVersion -NotePropertyValue 1
    $entry | Add-Member -NotePropertyName evidence -NotePropertyValue $evidenceObj
}

# Upsert: keep the other repos' entries.
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$repos = New-Object PSObject
if (($manifest.PSObject.Properties.Name -contains 'verify') -and $manifest.verify -and
    ($manifest.verify.PSObject.Properties.Name -contains 'repos') -and $manifest.verify.repos) {
    foreach ($p in $manifest.verify.repos.PSObject.Properties) {
        if ($p.Name -ne $Repo) { $repos | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
    }
}
$repos | Add-Member -NotePropertyName $Repo -NotePropertyValue $entry

Merge-TicketManifestFields -ManifestPath $manifestPath -Patch @{ verify = [pscustomobject]@{ repos = $repos } }
$color = if ($pass) { 'Green' } else { 'Yellow' }
Write-Host "Wrote verify.repos.$Repo (pass: $pass) on $manifestPath" -ForegroundColor $color
