#Requires -Version 7
<#
.SYNOPSIS
    Starts the local stack described in profile.json stacks.services.

.DESCRIPTION
    Each service: name, command (long-running), cwd, setup, stop, env, port, url, ready,
    dependsOn. Services start in dependsOn order; the launcher waits for a service's ready
    probe before starting the next. -Preset picks a subset (stacks.presets). An old profile
    with only stacks.startCommand runs as one implicit service named "app" and prints a
    migration warning. Writes scripts/runtime/.stack-services.state.json for Stop-TicketStack.ps1.

.PARAMETER Ticket
    Ticket id. Recorded as the stack owner when supplied.

.PARAMETER Preset
    Name from stacks.presets. Default: stacks.default when it names a preset, else every service.

.PARAMETER Setup
    Also run each service's setup command (install, restore) before starting it.

.PARAMETER Force
    Take the stack owner even when another ticket holds it.

.PARAMETER ProfilePath
    profile.json to read. Defaults to the repo root beside this scripts folder.

.EXAMPLE
    ./scripts/runtime/Start-TicketStack.ps1 -Ticket TICKET-12 -Preset web -Setup
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Ticket,
    [string]$Preset,
    [switch]$Setup,
    [switch]$Force,
    [string]$ProfilePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib/StackServices.ps1')
$resolver = Join-Path (Split-Path $PSScriptRoot -Parent) 'lib/Resolve-AgenticApp.ps1'
if (Test-Path -LiteralPath $resolver) { . $resolver }

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$app = $null
if (Get-Command Resolve-AgenticApp -ErrorAction SilentlyContinue) {
    $app = Resolve-AgenticApp -HostRoot $repoRoot
}
if (-not $ProfilePath) {
    $ProfilePath = if ($app -and $app.Id) { $app.ProfilePath } else { Join-Path $repoRoot 'profile.json' }
}
if (-not (Test-Path -LiteralPath $ProfilePath)) {
    Write-Error "profile.json not found at $ProfilePath."
    exit 1
}
$profileJson = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
$stack = Get-StackField $profileJson 'stacks'
if (-not $stack) {
    Write-Error 'profile.json does not define stacks.'
    exit 1
}

$list = Get-StackServiceList -Stack $stack
if ($list.Services.Count -eq 0) {
    Write-Error 'Stack is disabled or has no services. Fill profile.stacks.services (see CUSTOMIZE.md, Stack recipes).'
    exit 1
}
if ($list.Warning) { Write-Host "[WARN] $($list.Warning)" -ForegroundColor Yellow }

try {
    $ordered = @(Resolve-StackSelection -Stack $stack -Services $list.Services -Preset $Preset)
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

if ($Ticket) {
    $owner = Join-Path $PSScriptRoot 'Set-ActiveStack.ps1'
    $ownerArgs = @('-NoProfile', '-File', $owner, '-Ticket', $Ticket)
    if ($Force) { $ownerArgs += '-Force' }
    if ($PSCmdlet.ShouldProcess($Ticket, 'Claim stack owner')) {
        & pwsh @ownerArgs
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}

$statePath = Join-Path $PSScriptRoot '.stack-services.state.json'
try {
    $stackRoot = if ($app -and $app.Id -and $app.CheckoutRoot) { $app.CheckoutRoot } else { $repoRoot }
    $started = @(Start-StackServices -Services $ordered -RepoRoot $stackRoot -StatePath $statePath -Setup:$Setup -Cmdlet $PSCmdlet)
} catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '       Services already started are recorded; run Stop-TicketStack.ps1 to clean up.'
    exit 1
}

Write-Host "[PASS] Started $($started.Count) service(s)."
foreach ($entry in $started) {
    if ($entry.url) { Write-Host "  $($entry.url)" }
}
exit 0
