<#
.SYNOPSIS
    Advisory one-stack-at-a-time ownership across ticket worktrees.

.DESCRIPTION
    Dot-sourced by scripts/_ServiceLauncherLib.ps1. Do not run directly.
#>

Set-StrictMode -Version Latest

# Fallbacks when _ServiceLauncherLib.ps1 is not loaded. Checked one by one: that lib defines
# the Write-* helpers but not Use-LauncherLock.
if (-not (Get-Command Write-LauncherSkip -ErrorAction SilentlyContinue)) {
    function Write-LauncherSkip { param([string]$Message) Write-Host $Message }
}
if (-not (Get-Command Write-LauncherOk -ErrorAction SilentlyContinue)) {
    function Write-LauncherOk { param([string]$Message) Write-Host $Message }
}
if (-not (Get-Command Write-LauncherFail -ErrorAction SilentlyContinue)) {
    function Write-LauncherFail { param([string]$Message) Write-Host $Message -ForegroundColor Red }
}
if (-not (Get-Command Use-LauncherLock -ErrorAction SilentlyContinue)) {
    function Use-LauncherLock {
        param([string]$Name, [int]$TimeoutMs, $OnTimeoutAction, [scriptblock]$Body)
        & $Body
    }
}


# ---------------------------------------------------------------------------
# Active-stack ownership (parallel worktrees, one app stack at a time)
#
# Only one full local app stack is meant to run at a time across all ticket
# worktrees (see environments/worktrees.md). These helpers manage a
# small advisory owner file (.active-stack.json) so Set-ActiveStack.ps1,
# Get-TicketWorktrees.ps1, and (optionally) the Start-* launchers can agree on
# who holds the stack. No port templating - purely cooperative.
# ---------------------------------------------------------------------------

# One owner file for every caller: scripts\.active-stack.json, beside this lib's parent.
# Callers used to pass their own $PSScriptRoot, which split the owner across
# scripts\runtime and scripts\worktree. -ScriptRoot is kept so call sites need no change;
# it no longer picks the folder. TMO_ACTIVE_STACK_DIR overrides the scripts folder (tests).
function Get-ActiveStackFile {
    param([string]$ScriptRoot)
    $scriptsDir = if ($env:TMO_ACTIVE_STACK_DIR) { $env:TMO_ACTIVE_STACK_DIR } else { Split-Path $PSScriptRoot -Parent }
    $file = Join-Path $scriptsDir ".active-stack.json"
    if (-not (Test-Path -LiteralPath $file)) {
        # One-time move of a claim written to an old per-caller location (newest wins).
        $legacy = @('runtime', 'worktree') |
            ForEach-Object { Join-Path (Join-Path $scriptsDir $_) ".active-stack.json" } |
            Where-Object { Test-Path -LiteralPath $_ } |
            ForEach-Object { Get-Item -LiteralPath $_ -Force } |  # -Force: dot-files are hidden on Linux/macOS
            Sort-Object LastWriteTimeUtc -Descending
        if ($legacy) {
            Move-Item -LiteralPath @($legacy)[0].FullName -Destination $file -Force
        }
    }
    return $file
}

function Get-ActiveStackState {
    param([Parameter(Mandatory)][string]$ScriptRoot)
    $file = Get-ActiveStackFile -ScriptRoot $ScriptRoot
    if (-not (Test-Path $file)) { return $null }
    try {
        return (Get-Content $file -Raw | ConvertFrom-Json)
    } catch {
        Write-LauncherSkip "Could not parse active-stack file - ignoring it: $file"
        return $null
    }
}

function Set-ActiveStackState {
    param(
        [Parameter(Mandatory)][string]$ScriptRoot,
        [Parameter(Mandatory)][string]$Ticket,
        [string]$Preset,
        [string[]]$Pieces
    )
    $file = Get-ActiveStackFile -ScriptRoot $ScriptRoot

    # .active-stack.json is a single machine-wide file (every ticket worktree's
    # workflow-repo junctions back to the same canonical scripts\ folder), so two
    # ticket windows claiming the stack close together can interleave this
    # read-merge-write. Losing a claim outright is worse than the rare race, so
    # run unlocked (with a loud warning) rather than silently skip the claim.
    Use-LauncherLock -Name "ActiveStackFile" -TimeoutMs 10000 -OnTimeoutAction RunUnlocked -Body {
        $prior = Get-ActiveStackState -ScriptRoot $ScriptRoot
        $priorPreset = $null
        $priorPieces = @()
        if ($prior) {
            if ($prior.PSObject.Properties['Preset']) { $priorPreset = $prior.Preset }
            if ($prior.PSObject.Properties['Pieces'] -and $prior.Pieces) { $priorPieces = @($prior.Pieces) }
        }
        $state = [PSCustomObject]@{
            Ticket   = $Ticket
            Preset   = $(if ($Preset) { $Preset } elseif ($priorPreset) { $priorPreset } else { $null })
            Pieces   = $(if ($Pieces) { @($Pieces) } elseif ($priorPieces.Count -gt 0) { $priorPieces } else { @() })
            SetAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        }
        try {
            $state | ConvertTo-Json -Depth 3 | Set-Content -Path $file -Encoding UTF8
        } catch {
            Write-LauncherSkip "Could not write active-stack file $file : $($_.Exception.Message)"
        }
    } | Out-Null
}

function Clear-ActiveStackState {
    param([Parameter(Mandatory)][string]$ScriptRoot)
    $file = Get-ActiveStackFile -ScriptRoot $ScriptRoot
    if (Test-Path $file) { Remove-Item -Force $file }
}

<#
.SYNOPSIS
    Returns the owning ticket if a DIFFERENT ticket currently owns the app
    stack, otherwise $null. Start-* launchers can call this and skip/prompt
    before starting a duplicate stack. Non-fatal by design.
#>
function Test-ActiveStackConflict {
    param(
        [Parameter(Mandatory)][string]$ScriptRoot,
        [string]$Ticket
    )
    $active = Get-ActiveStackState -ScriptRoot $ScriptRoot
    if (-not $active) { return $null }
    if ($Ticket -and $active.Ticket -eq $Ticket) { return $null }
    return $active.Ticket
}

<#
.SYNOPSIS
    Resolves the ticket that "this shell" is working, preferring an explicit
    value, then env TMO_ACTIVE_TICKET, then the recorded active-stack owner.
    Lets the launchers auto-target a ticket's worktree with no path typing.
#>
function Get-ActiveTicketId {
    param(
        [Parameter(Mandatory)][string]$ScriptRoot,
        [string]$Explicit
    )
    $id = ConvertTo-LauncherTicketId -Raw $Explicit
    if ($id) { return $id }
    $id = ConvertTo-LauncherTicketId -Raw $env:TMO_ACTIVE_TICKET
    if ($id) { return $id }
    $active = Get-ActiveStackState -ScriptRoot $ScriptRoot
    if ($active -and $active.Ticket) { return $active.Ticket }
    return $null
}

<#
.SYNOPSIS
    Stops a Start-* launcher when a different ticket owns the app stack,
    unless -Force is set. Uses -TicketHint when provided, otherwise reads <ticket>
    from env TMO_ACTIVE_TICKET (set by agents/scripts running inside a ticket
    worktree). When the hint matches the current owner, the start is allowed.
#>
function Assert-ActiveStackAllowed {
    param(
        [Parameter(Mandatory)][string]$ScriptRoot,
        [string]$TicketHint,
        [switch]$Force
    )
    if ($Force) { return }
    if (-not $TicketHint) { $TicketHint = ConvertTo-LauncherTicketId -Raw $env:TMO_ACTIVE_TICKET }
    $owner = Test-ActiveStackConflict -ScriptRoot $ScriptRoot -Ticket $TicketHint
    if ($owner) {
        Write-LauncherFail "Ticket $owner owns the local app stack. Run Set-ActiveStack.ps1 -Ticket <WI> (or Start-*.ps1 -Ticket <WI>) first, or pass -Force to override."
        throw "Active-stack conflict: owned by $owner"
    }
}
