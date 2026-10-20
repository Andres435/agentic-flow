#Requires -Version 7
<#
.SYNOPSIS
    Close a ticket in one call after the user approved the approval package: stamp the close
    time, compute hours, record context, write the ledger row, and run the close gate.

.DESCRIPTION
    Replaces the hand sequence of /complete-task (timestamp edit, Get-SessionHours,
    Set-TicketCtxPct, Update-TicketLedger, Assert-TicketArtifacts -Phase close). Run it once,
    after approval. It stops on the first failure with
    "[FAIL] close step N (<name>): <what to fix>" and a non-zero exit, so nothing later is
    written on a ticket that cannot close.

    Steps:
      1 resolve    manifest found, workType known, and the work checks of close (verify
                   receipts, review stamps, Drive) pass -- before anything is written
      2 timestamp  completedAtUtc = now UTC; when completedAtUtc is already set and the ticket
                   was reopened (reopenedAtUtc), reclosedAtUtc = now instead. startedAtUtc and
                   an existing completedAtUtc are never overwritten. A repeat close with no
                   reopen keeps the stamp (a retry after a failed later step).
      3 hours      Get-SessionHours.ps1 -Json: hours, and story points (not for a spike)
      4 ctx        Set-TicketCtxPct.ps1 -Phase close (measured value, or blank)
      5 ledger     Update-TicketLedger.ps1 (Type from the manifest workType; a re-close
                   replaces the ticket's row)
      6 gate       Assert-TicketArtifacts.ps1 -Phase close

    -WhatIf lists the steps and writes nothing.

.PARAMETER Ticket
    Work item, with or without the profile ticket prefix.

.PARAMETER Efficiency
.PARAMETER Contextualization
.PARAMETER CostTokens
    Session scorecard axes, 1-5 (5 = excellent). Required, validated before anything is written.

.PARAMETER Pr
    PR number or URL, if one was created.

.PARAMETER Root
    Override the workflow repo root (tests). Also puts the close gate in fixture mode.

.PARAMETER SweepScript
    Test seam: path of the scratch-sweep script to run after a passing close; default is
    scripts/Clear-WorkflowScratch.ps1 beside this folder.

.EXAMPLE
    .\scripts\ticket\Close-Ticket.ps1 -Ticket TICKET-42 -Efficiency 4 -Contextualization 4 -CostTokens 3 -Pr 1234
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Ticket,
    [Parameter(Mandatory)][ValidateRange(1, 5)][int]$Efficiency,
    [Parameter(Mandatory)][ValidateRange(1, 5)][int]$Contextualization,
    [Parameter(Mandatory)][ValidateRange(1, 5)][int]$CostTokens,
    [string]$Pr,
    [string]$Root,
    [string]$SweepScript
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path $PSScriptRoot 'lib') 'ManifestFields.ps1')

$Key = Get-TicketKeyFromRaw -Ticket $Ticket
$RepoRoot = if ($Root) { $Root } else { Get-CursorRepoRoot -FromScriptRoot $PSScriptRoot }
$manifestPath = Get-TicketManifestFile -RepoRoot $RepoRoot -TicketKey $Key
# Child scripts get -Root only when the caller did; the close gate treats -Root as fixture mode.
$rootArgs = if ($Root) { @{ Root = $Root } } else { @{} }

$stepNames = @('resolve', 'timestamp', 'hours', 'ctx', 'ledger', 'gate')

function Stop-Close {
    param([int]$N, [string]$Fix, [string]$Detail)
    Write-Output "[FAIL] close step $N ($($stepNames[$N - 1])): $Fix"
    foreach ($line in @(($Detail -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 8)) {
        Write-Output "       $($line.Trim())"
    }
    exit 1
}

# Runs one sibling script in-process; returns its merged output, or stops the close.
function Invoke-CloseScript {
    param([int]$N, [string]$Script, [hashtable]$Splat, [string]$Fix)
    $global:LASTEXITCODE = 0
    try { $out = (& (Join-Path $PSScriptRoot $Script) @Splat *>&1 | Out-String) }
    catch { Stop-Close -N $N -Fix $Fix -Detail $_.Exception.Message }
    if ($global:LASTEXITCODE -ne 0) { Stop-Close -N $N -Fix $Fix -Detail $out }
    return $out
}

function Read-Manifest { Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }

function Get-Field {
    param($Obj, [string]$Name)
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $null
}

# ---- 1 resolve + preflight (read only) ---------------------------------------
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Stop-Close -N 1 -Fix "no manifest at $manifestPath; run /start-ticket first, or pass the right -Ticket/-Root" -Detail ''
}
$manifest = Read-Manifest
$workType = [string](Get-Field $manifest 'workType')
if ($workType -notin @('bug', 'feature', 'spike', 'refactor')) {
    Stop-Close -N 1 -Fix "manifest workType '$workType' is not bug|feature|spike|refactor; fix it, then re-run" -Detail ''
}
$mode = [string](Get-Field $manifest 'mode')
$null = Invoke-CloseScript -N 1 -Script 'Assert-TicketArtifacts.ps1' `
    -Splat (@{ Ticket = $Key; Phase = 'prepush' } + $rootArgs) `
    -Fix 'the work checks of close fail (verify receipt, review stamp, Drive); fix what is listed and re-run. Nothing was written'

if (-not $PSCmdlet.ShouldProcess($Key, 'close ticket (timestamp, hours, ctx, ledger row, close gate)')) {
    Write-Output "[WhatIf] $Key ($workType, $mode): resolve and preflight passed; the rest would run in order, writing nothing now:"
    Write-Output '[WhatIf] close step 2 (timestamp): completedAtUtc = now UTC, or reclosedAtUtc after a reopen'
    Write-Output '[WhatIf] close step 3 (hours): Get-SessionHours.ps1 -Json (hours; points unless a spike)'
    Write-Output '[WhatIf] close step 4 (ctx): Set-TicketCtxPct.ps1 -Phase close (measured value or blank)'
    Write-Output "[WhatIf] close step 5 (ledger): Update-TicketLedger.ps1 -Type $workType -Efficiency $Efficiency -Contextualization $Contextualization -CostTokens $CostTokens$(if ($Pr) { " -Pr $Pr" })"
    Write-Output '[WhatIf] close step 6 (gate): Assert-TicketArtifacts.ps1 -Phase close'
    exit 0
}

# ---- 2 timestamp --------------------------------------------------------------
$now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$manifest = Read-Manifest
$completed = [string](Get-Field $manifest 'completedAtUtc')
$reopened = [string](Get-Field $manifest 'reopenedAtUtc')
try {
    if (-not $completed) {
        Merge-TicketManifestFields -ManifestPath $manifestPath -Patch @{ completedAtUtc = $now }
        Write-Output "[OK] close step 2 (timestamp): completedAtUtc = $now"
    }
    elseif ($reopened) {
        Merge-TicketManifestFields -ManifestPath $manifestPath -Patch @{ reclosedAtUtc = $now }
        Write-Output "[OK] close step 2 (timestamp): reclosedAtUtc = $now"
    }
    else {
        Write-Output "[OK] close step 2 (timestamp): completedAtUtc already $completed and no reopen; kept"
    }
}
catch { Stop-Close -N 2 -Fix 'could not write the close timestamp to the manifest' -Detail $_.Exception.Message }

# ---- 3 hours ------------------------------------------------------------------
$hoursOut = Invoke-CloseScript -N 3 -Script 'Get-SessionHours.ps1' `
    -Splat (@{ Ticket = $Key; Json = $true } + $rootArgs) `
    -Fix 'session hours could not be computed; check startedAtUtc and the spans on the manifest'
try { $session = $hoursOut | ConvertFrom-Json }
catch { Stop-Close -N 3 -Fix 'Get-SessionHours.ps1 did not return JSON' -Detail $hoursOut }
$hours = [double]$session.hours
$points = if ($workType -ne 'spike' -and $null -ne $session.points) { [string]$session.points } else { $null }
Write-Output ("[OK] close step 3 (hours): {0} h, points {1}" -f $hours.ToString([cultureinfo]::InvariantCulture), $(if ($points) { $points } else { 'none' }))

# ---- 4 ctx --------------------------------------------------------------------
$null = Invoke-CloseScript -N 4 -Script 'Set-TicketCtxPct.ps1' `
    -Splat (@{ Ticket = $Key; Phase = 'close' } + $rootArgs) `
    -Fix 'ctxPct.close could not be recorded; re-run Set-TicketCtxPct.ps1 -Phase close'
Write-Output '[OK] close step 4 (ctx): ctxPct.close recorded (measured, or blank)'

# ---- 5 ledger -----------------------------------------------------------------
$ledger = @{
    Ticket            = $Key
    Type              = $workType
    Hours             = $hours.ToString([cultureinfo]::InvariantCulture)
    Efficiency        = $Efficiency
    Contextualization = $Contextualization
    CostTokens        = $CostTokens
}
if ($points) { $ledger.Points = $points }
if ($mode -in @('branch', 'worktree', 'investigate')) { $ledger.Mode = $mode }
if ($Pr) { $ledger.Pr = $Pr }
$null = Invoke-CloseScript -N 5 -Script 'Update-TicketLedger.ps1' -Splat ($ledger + $rootArgs) `
    -Fix 'the ledger row was not written; fix the error above and re-run Close-Ticket.ps1'
Write-Output "[OK] close step 5 (ledger): row written for $Key"

# ---- 6 gate -------------------------------------------------------------------
$null = Invoke-CloseScript -N 6 -Script 'Assert-TicketArtifacts.ps1' `
    -Splat (@{ Ticket = $Key; Phase = 'close' } + $rootArgs) `
    -Fix 'the close gate still fails; fix what is listed (a stale receipt or review goes back to /complete-task step 1 or 2) and re-run'

# ---- tidy (not a numbered step): prune old scratch once the ticket has closed ---------
# Best effort: a failing sweep never changes the close result. -SweepScript is a test seam.
try {
    $sweepScript = if ($SweepScript) { $SweepScript } else { Join-Path (Split-Path $PSScriptRoot -Parent) 'Clear-WorkflowScratch.ps1' }
    $sweepArgs = @{ Quiet = $true }
    if ($Root) { $sweepArgs.Root = $Root }
    $sweepOut = (& $sweepScript @sweepArgs *>&1 | Out-String).Trim()
    if ($sweepOut) { Write-Output $sweepOut }
}
catch { Write-Verbose "scratch sweep skipped: $($_.Exception.Message)" }
Write-Output "[PASS] $Key closed: $($hours.ToString([cultureinfo]::InvariantCulture)) h, points $(if ($points) { $points } else { 'none' }), ledger row written, close gate passed."
exit 0
