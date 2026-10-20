#Requires -Version 7
<#
.SYNOPSIS
    Resolves whether a ticket runs in branch mode (canonical clones) or worktree
    mode (source\worktrees\<ticket>), and returns the per-repo paths to work in.

.DESCRIPTION
    /start-ticket defaults to BRANCH mode: branches in the canonical clones under
    source\repos. Worktree mode (--worktree) mirrors the repos under
    source\worktrees\<ticket> and is the special case.

    Every later command needs the same answer -- prep-pr, review-changes,
    complete-task, address-pr-comments, and the review/verify subagents all used
    to hardcode source\worktrees\<ticket>\<repo> with an improvised canonical
    fallback. This script is the single answer so they stop guessing.

    Mode precedence:
      1. manifest "mode"  -- what /start-ticket actually decided (source: manifest)
      2. branch           -- the default (source: default)

    A leftover populated source\worktrees\<ticket> folder does NOT flip the default
    to worktree. Only an explicit manifest mode of worktree uses that tree.
    When the manifest says worktree but the folder is gone, rootExists is false
    and callers stop rather than working in the canonical clones.

.PARAMETER Ticket
    Work item, with or without the profile ticketPrefix (TICKET-42, 42, AB#42).

.PARAMETER Json
    Emit the resolution object as JSON instead of human-readable lines.

.EXAMPLE
    .\Resolve-TicketRoot.ps1 -Ticket TICKET-42

.EXAMPLE
    .\Resolve-TicketRoot.ps1 -Ticket 22132 -Json

.NOTES
    Contract: .cursor/_shared/ticket-artifacts.md
    See also: New-TicketWorktree.ps1, Get-TicketWorktrees.ps1, Assert-TicketArtifacts.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Ticket,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path $PSScriptRoot -Parent) '_ServiceLauncherLib.ps1')

$Key = ConvertTo-LauncherTicketId -Raw $Ticket
if (-not $Key) {
    throw "Could not read a work item number from '$Ticket'. Use TICKET-42, 42, or AB#42."
}

# $PSScriptRoot is <root>\.cursor\scripts. Inside a ticket window .cursor is a
# junction, so canonicalize before deriving anything (see Get-CanonicalReposRoot).
$ReposRoot    = Get-CanonicalReposRoot -ReposRoot (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent)
$WorktreeRoot = Get-TicketWorktreeRoot -ReposRoot $ReposRoot -TicketId $Key

$manifest     = Get-TicketManifest -ScriptRoot $PSScriptRoot -Ticket $Key
$manifestMode = Get-LauncherManifestValue -Manifest $manifest -Property 'mode'

# A worktree root only counts once it holds at least one repo. New-TicketWorktree
# creates the folder and the .cursor junction before adding any repo worktree, so
# an empty (or junction-only) folder is a half-provisioned ticket, not a mode.
$worktreePopulated = $false
if (Test-Path -LiteralPath $WorktreeRoot) {
    $worktreePopulated = [bool](@(Get-ChildItem -LiteralPath $WorktreeRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Name.StartsWith('.') }).Count)
}

$resolvedMode = Resolve-TicketMode -ManifestMode $manifestMode
$mode = [string]$resolvedMode.mode
$modeSource = [string]$resolvedMode.modeSource

$root = if ($mode -eq 'worktree') { $WorktreeRoot } else { $ReposRoot }
$rootExists = if ($mode -eq 'worktree') { $worktreePopulated } else { Test-Path -LiteralPath $ReposRoot }

# affectedRepos is [{repo, local}], but older manifests wrote bare strings.
$repoNames = @()
$affected = Get-LauncherManifestValue -Manifest $manifest -Property 'affectedRepos'
foreach ($entry in @($affected)) {
    if (-not $entry) { continue }
    if ($entry -is [string]) {
        $repoNames += $entry
        continue
    }
    $name = Get-LauncherManifestValue -Manifest $entry -Property 'repo'
    if (-not $name) { continue }
    # local:false means "not cloned on this machine" -- there is no path to hand back.
    $local = Get-LauncherManifestValue -Manifest $entry -Property 'local'
    if ($null -ne $local -and -not $local) { continue }
    $repoNames += $name
}

$repos = foreach ($name in $repoNames) {
    $path = Join-Path $root $name
    [pscustomobject]@{
        repo   = $name
        path   = $path
        exists = [bool](Test-Path -LiteralPath $path)
        isGit  = Test-GitWorktree -Path $path
    }
}

$result = [pscustomobject]@{
    ticket        = $Key
    mode          = $mode
    modeSource    = $modeSource
    root          = $root
    rootExists    = $rootExists
    canonicalRoot = $ReposRoot
    worktreeRoot  = $WorktreeRoot
    hasManifest   = [bool]$manifest
    repos         = @($repos)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 4
    if (-not $rootExists) { exit 1 }
    exit 0
}

$modeColor = if ($mode -eq 'worktree') { 'Cyan' } else { 'Green' }
Write-Host ("{0}: {1} mode (from {2})" -f $Key, $mode, $modeSource) -ForegroundColor $modeColor
Write-Host ("    root {0}" -f $root) -ForegroundColor DarkGray

if (-not $rootExists) {
    Write-LauncherFail "Root does not exist. Do not fall back to another tree -- re-run /start-ticket $Key."
    exit 1
}

if (-not $repos) {
    $why = if ($manifest) { "manifest has no local affectedRepos" } else { "no $Key-manifest.json yet" }
    Write-LauncherSkip "No repos resolved ($why)."
    exit 0
}

foreach ($r in $repos) {
    if ($r.isGit) {
        $branch = (git -C $r.path rev-parse --abbrev-ref HEAD).Trim()
        Write-LauncherOk ("{0,-26} {1}" -f $r.repo, $branch)
    }
    elseif ($r.exists) {
        Write-LauncherFail ("{0,-26} present but not a git repo" -f $r.repo)
    }
    else {
        Write-LauncherFail ("{0,-26} missing at {1}" -f $r.repo, $r.path)
    }
}

exit 0
