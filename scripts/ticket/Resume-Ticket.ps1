#Requires -Version 7
<#
.SYNOPSIS
    Resume a ticket parked by Park-Ticket.ps1: open a new work span at now so the idle gap
    stays out of the hours.

.DESCRIPTION
    Run by /start-ticket when the manifest carries parkedAtUtc. It appends an open
    { kind: 'resume', startedAtUtc: now } span, moves the park stamps into parkHistory[]
    and clears parkedAtUtc/parkedState/parkedOutcome/parkedHours, so the ticket reads as open
    again. Close-Ticket.ps1 closes the resume span at the final close and sums every span.
    The parked ledger row stays until that close replaces it.

.PARAMETER Ticket
    Work item, with or without the WI prefix.

.PARAMETER Root
    Override the tmo-agentic repo root (tests).

.EXAMPLE
    .\scripts\ticket\Resume-Ticket.ps1 -Ticket WI22758
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Ticket,
    [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path $PSScriptRoot 'lib') 'ManifestFields.ps1')

$Key = Get-TicketKeyFromRaw -Ticket $Ticket
$RepoRoot = if ($Root) { $Root } else { Get-CursorRepoRoot -FromScriptRoot $PSScriptRoot }
$manifestPath = Get-TicketManifestFile -RepoRoot $RepoRoot -TicketKey $Key
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifest not found: $manifestPath" }

function Get-Field {
    param($Obj, [string]$Name)
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $null
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$parkedAt = Get-Field $manifest 'parkedAtUtc'
if (-not $parkedAt) {
    Write-Output "[FAIL] $Key is not parked (no parkedAtUtc); nothing to resume."
    exit 1
}

if (-not $PSCmdlet.ShouldProcess($Key, 'resume parked ticket')) {
    Write-Output "[WhatIf] $Key parked at $parkedAt; would open a resume span at now and clear the park stamps"
    exit 0
}

$now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$spans = New-Object System.Collections.Generic.List[object]
foreach ($s in @(Get-Field $manifest 'spans')) { if ($s) { $spans.Add($s) } }
# A hand-stamped park has no explicit span for the work before it; without one the final close
# would drop that work (the original span is only derived from completedAtUtc).
$startedAt = Get-Field $manifest 'startedAtUtc'
if ($startedAt -and -not (Get-Field $manifest 'completedAtUtc') -and
    @($spans | Where-Object { (Get-Field $_ 'kind') -eq 'original' }).Count -eq 0) {
    $spans.Add([pscustomobject]@{ kind = 'original'; startedAtUtc = ConvertTo-IsoUtcText $startedAt; endedAtUtc = ConvertTo-IsoUtcText $parkedAt })
}
$spans.Add([pscustomobject]@{ kind = 'resume'; startedAtUtc = $now; endedAtUtc = $null })

$history = New-Object System.Collections.Generic.List[object]
foreach ($h in @(Get-Field $manifest 'parkHistory')) { if ($h) { $history.Add($h) } }
$history.Add([pscustomobject]@{
    parkedAtUtc   = ConvertTo-IsoUtcText $parkedAt
    parkedState   = [string](Get-Field $manifest 'parkedState')
    parkedOutcome = [string](Get-Field $manifest 'parkedOutcome')
    parkedHours   = Get-Field $manifest 'parkedHours'
    resumedAtUtc  = $now
})

Merge-TicketManifestFields -ManifestPath $manifestPath -Patch @{
    spans         = $spans.ToArray()
    parkHistory   = $history.ToArray()
    parkedAtUtc   = $null
    parkedState   = $null
    parkedOutcome = $null
    parkedHours   = $null
}
Write-Output "[PASS] $Key resumed at $now; new resume span opened, idle gap excluded."
exit 0
