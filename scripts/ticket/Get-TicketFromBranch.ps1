#Requires -Version 7
<#
.SYNOPSIS
    Name the ticket this workspace is on, from the current branch of each profile repo.

.DESCRIPTION
    A chat opened at the workspace root (branch mode) has no ticket folder in its path, so
    /review-changes, /complete-task, and ticket-context-load ask this before asking the user.
    Reads every profile.json repo under the repos root, takes `<prefix><digits>` from each
    current branch, and prefers a key whose manifest is still open (a reopened ticket counts).
    Prints the key, or nothing when there is no candidate or more than one (then ask the user).

    The session-start hook (hooks/core/session-context.js) uses the same branch rule but is
    stricter on purpose: it injects context unasked, so it only names a ticket with an open
    manifest. This script answers a command that is already asking, so a branch with no
    manifest yet is still a candidate (reason: branch).

.PARAMETER ReposRoot
    Folder holding the product clones. Defaults to the parent of this workflow repo.

.PARAMETER Json
    Emit { ticket, candidates, reason }.

.PARAMETER Root
    Override the workflow repo root (tests): profile.json and plans/ are read from it.

.EXAMPLE
    .\Get-TicketFromBranch.ps1 -Json
#>

[CmdletBinding()]
param(
    [string]$ReposRoot,
    [switch]$Json,
    [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path $PSScriptRoot 'lib') 'ManifestFields.ps1')

$RepoRoot = if ($Root) { $Root } else { Get-CursorRepoRoot -FromScriptRoot $PSScriptRoot }
if (-not $ReposRoot) { $ReposRoot = Split-Path $RepoRoot -Parent }

$prefix = 'TICKET-'
$names = @()
$profilePath = Join-Path $RepoRoot 'profile.json'
$plansDir = Join-Path $RepoRoot 'plans'
if (-not $Root -and (Get-Command Resolve-AgenticApp -ErrorAction SilentlyContinue)) {
    $app = Resolve-AgenticApp -HostRoot $RepoRoot
    if ($app.Id) {
        $profilePath = $app.ProfilePath
        $plansDir = $app.PlansDir
        if ($app.CheckoutRoot) { $ReposRoot = $app.CheckoutRoot }
    }
}
if (Test-Path -LiteralPath $profilePath) {
    $profileJson = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
    if ($profileJson.PSObject.Properties.Name -contains 'ticketPrefix' -and $profileJson.ticketPrefix) {
        $prefix = [string]$profileJson.ticketPrefix
    }
    if ($profileJson.PSObject.Properties.Name -contains 'repos') {
        $names = @($profileJson.repos | ForEach-Object { Get-ProfileRepoDir $_ } | Where-Object { $_ })
    }
}

$paths = @($names | ForEach-Object {
    if ($_ -eq '.') { $ReposRoot } else { Join-Path $ReposRoot $_ }
})
$result = Get-TicketKeyFromBranches -RepoPaths $paths -Prefix $prefix -PlansDir $plansDir

if ($Json) {
    $result | ConvertTo-Json -Compress
} elseif ($result.ticket) {
    $result.ticket
} else {
    Write-Host "No single ticket branch ($($result.reason)): $(@($result.candidates) -join ', ')" -ForegroundColor Yellow
}
