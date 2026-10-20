#Requires -Version 7
<#
.SYNOPSIS
    Rewrite or check the generated command table and chat-count regions.

.DESCRIPTION
    The rows in this script are the source. USER-MANUAL.md holds the command
    table between gen:commands markers. README.md holds the branch-mode chat
    counts between gen:chats markers. environments/local-dev.md holds the
    services table (from profile.json stacks.services) between gen:ports markers;
    a project that dropped the markers is skipped. -Check fails when a marked region differs.

.PARAMETER Check
    Compare the committed regions to the source and exit 1 on drift.

.EXAMPLE
    .\Sync-GeneratedDocs.ps1 -Check
#>

[CmdletBinding()]
param(
    [switch]$Check,
    [string]$Root = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$commands = @(
    @{ Want = 'Fill the profile for a new project'; Type = '`/start-new-project`' }
    @{ Want = 'Attach an existing GitHub checkout'; Type = '`/adopt-project`' }
    @{ Want = 'Search X on a spike (optional)'; Type = '`/research-x`' }
    @{ Want = 'Machine setup after the profile exists'; Type = '`/onboard`' }
    @{ Want = 'Pin model routing for the chat'; Type = '`/engineering-mode`' }
    @{ Want = 'Health check (profile, hooks, gates, lanes)'; Type = '`/doctor`' }
    @{ Want = 'Start a ticket'; Type = '`/start-ticket <ticket> bug|feature|spike|refactor`' }
    @{ Want = 'Build the approved plan (resume / worktree)'; Type = '`/implement <ticket>`' }
    @{ Want = 'Run the local apps'; Type = '`/start-stack <ticket>`' }
    @{ Want = 'Give the stack to another ticket / stop it'; Type = '`/swap-stack <ticket>` / `/stop-stack`' }
    @{ Want = 'Review ticket files; stage the clean ones'; Type = '`/review-changes`' }
    @{ Want = 'Closeout and approval package'; Type = '`/complete-task`' }
    @{ Want = 'Commit / push / PR / tracker write-back, after you approve'; Type = '`/prep-pr`' }
    @{ Want = 'Address PR comments'; Type = '`/address-pr-comments <ticket>`' }
    @{ Want = 'Peer-review a coworker''s PR'; Type = '`/peer-review <id>`' }
)

$wantWidth = ($commands | ForEach-Object { $_.Want.Length } | Measure-Object -Maximum).Maximum
$typeWidth = ($commands | ForEach-Object { $_.Type.Length } | Measure-Object -Maximum).Maximum
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('| ' + ('You want'.PadRight($wantWidth)) + ' | ' + ('Type'.PadRight($typeWidth)) + ' |')
$lines.Add('| ' + ('-' * $wantWidth) + ' | ' + ('-' * $typeWidth) + ' |')
foreach ($row in $commands) {
    $lines.Add('| ' + $row.Want.PadRight($wantWidth) + ' | ' + $row.Type.PadRight($typeWidth) + ' |')
}
$commandTable = ($lines -join "`n")

$chatCounts = @'
```text
Chat 1  /start-ticket <ticket> bug|feature|spike|refactor   → approve plan → build in this chat
Chat 2  /review-changes
Chat 3  /complete-task → /prep-pr
```
'@.TrimEnd()

function Get-Region {
    param([string]$Text, [string]$Name)
    $pattern = "(?s)<!-- gen:${Name}:start -->\r?\n(.*?)\r?\n<!-- gen:${Name}:end -->"
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { throw "Missing gen:${Name} markers" }
    return $match.Groups[1].Value.TrimEnd()
}

function Set-Region {
    param([string]$Text, [string]$Name, [string]$Body)
    $pattern = "(?s)<!-- gen:${Name}:start -->\r?\n.*?\r?\n<!-- gen:${Name}:end -->"
    $replacement = "<!-- gen:${Name}:start -->`n$Body`n<!-- gen:${Name}:end -->"
    return [regex]::Replace($Text, $pattern, $replacement, 1)
}

# Services table from profile.stacks.services.
$portLines = New-Object System.Collections.Generic.List[string]
$portLines.Add('| Service | Port | URL | Starts after |')
$portLines.Add('|---|---|---|---|')
$profileFile = Join-Path $Root 'profile.json'
if (Test-Path -LiteralPath $profileFile) {
    $stackBlock = (Get-Content -LiteralPath $profileFile -Raw | ConvertFrom-Json).stacks
    $svcs = @()
    if ($stackBlock -and $stackBlock.PSObject.Properties['services']) { $svcs = @($stackBlock.services) }
    foreach ($s in $svcs) {
        $p = if ($s.PSObject.Properties['port']) { [string]$s.port } else { '' }
        $u = if ($s.PSObject.Properties['url']) { [string]$s.url } else { '' }
        $d = if ($s.PSObject.Properties['dependsOn']) { (@($s.dependsOn) -join ', ') } else { '' }
        $portLines.Add("| $($s.name) | $p | $u | $d |")
    }
    if ($svcs.Count -eq 0) { $portLines.Add('| _none_ | | | |') }
}
$portsTable = ($portLines -join "`n")

$targets = @(
    @{ File = 'USER-MANUAL.md'; Name = 'commands'; Body = $commandTable }
    @{ File = 'README.md'; Name = 'chats'; Body = $chatCounts }
    @{ File = 'environments/local-dev.md'; Name = 'ports'; Body = $portsTable; Optional = $true }
)

$failed = $false
$utf8 = New-Object System.Text.UTF8Encoding $false
foreach ($target in $targets) {
    $path = Join-Path $Root $target.File
    if ($target.ContainsKey('Optional') -and -not (Test-Path -LiteralPath $path)) { continue }
    $text = [IO.File]::ReadAllText($path)
    if ($target.ContainsKey('Optional') -and $text -notmatch "gen:$($target.Name):start") { continue }
    $current = Get-Region $text $target.Name
    $expected = $target.Body.Replace("`r`n", "`n").TrimEnd()
    $actual = $current.Replace("`r`n", "`n").TrimEnd()
    if ($actual -eq $expected) { continue }
    if ($Check) {
        Write-Output "[FAIL] generated-docs: $($target.File) gen:$($target.Name) does not match the source. Run Sync-GeneratedDocs.ps1."
        $failed = $true
        continue
    }
    $updated = Set-Region $text $target.Name $expected
    [IO.File]::WriteAllText($path, $updated, $utf8)
    Write-Output "Updated $($target.File) gen:$($target.Name)"
}

if ($failed) { exit 1 }
if ($Check) { Write-Output '[PASS] generated-docs: command table and chat counts match.' }
exit 0
