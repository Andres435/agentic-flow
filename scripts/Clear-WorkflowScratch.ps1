#Requires -Version 7
<#
.SYNOPSIS
    Prune workflow scratch: old tmp/ items, closed tickets' evidence folders, leftover
    claude-eval-* temp folders, and old evals/results runs. Best effort; never fails.

.DESCRIPTION
    Rules (cutoff = now - Days; the age of a folder is the newest write time of any file in it):
      1 tmp          <Root>/tmp/ top-level entries older than the cutoff, except anything a
                     plans/*-manifest.json references (a tmp/ path in its text), the marker
                     tmp/.last-sweep, and tmp/tickets itself (its entries follow the same rule).
      2 evidence     <plans>/evidence/<ticket>/ (plans = <Root>/plans and each <Root>/apps/<id>/plans) when that ticket closed (max of completedAtUtc and
                     reclosedAtUtc) more than Days ago. A ticket with no completedAtUtc, or reopened
                     after its last close, is kept. A folder with no manifest goes by its own age.
      3 eval temp    <TempRoot>/claude-eval-XXXXXX folders older than the cutoff.
      4 eval results <Root>/evals/results/ run folders beyond the newest KeepEvalRuns (by name).
    Every deletion path is checked to sit under its expected root (both sides through GetFullPath, so an
    8.3 short TEMP path is not rejected), and a folder containing a junction or symlink is skipped and
    reported. Nothing outside those four places is touched. A real run writes tmp/.last-sweep (UTC date).

.PARAMETER Days
    Retention in days (default 14).

.PARAMETER KeepEvalRuns
    How many evals/results run folders to keep (default 5).

.PARAMETER Root
    Workflow (host) root (default: the repo this script lives in).

.PARAMETER TempRoot
    Where claude-eval-* folders live (default $env:TEMP).

.PARAMETER WhatIf
    Print what would be removed; delete and write nothing.

.PARAMETER Quiet
    Print only when something was removed (or would be) or something was skipped.

.EXAMPLE
    .\scripts\Clear-WorkflowScratch.ps1 -WhatIf
#>

[CmdletBinding()]
param(
    [int]$Days = 14,
    [int]$KeepEvalRuns = 5,
    [string]$Root,
    [string]$TempRoot,
    [switch]$WhatIf,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
if (-not $TempRoot) { $TempRoot = $env:TEMP }
$Root = [System.IO.Path]::GetFullPath($Root)
$cutoff = (Get-Date).AddDays(-$Days)
$nowUtc = [DateTime]::UtcNow
$sep = [System.IO.Path]::DirectorySeparatorChar

$script:Lines = [System.Collections.Generic.List[string]]::new()
$script:Skips = [System.Collections.Generic.List[string]]::new()
$script:Stats = @{
    tmp      = @{ n = 0; bytes = [long]0 }
    evidence = @{ n = 0; bytes = [long]0 }
    evaltemp = @{ n = 0; bytes = [long]0 }
    evalres  = @{ n = 0; bytes = [long]0 }
}

function Get-NormalPath {
    param([string]$Path)
    return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\', '/')
}

function Test-UnderRoot {
    param([string]$Path, [string]$Base)
    $p = Get-NormalPath $Path
    $b = Get-NormalPath $Base
    return $p.StartsWith($b + $sep, [StringComparison]::OrdinalIgnoreCase)
}

# Walks a tree without following junctions or symlinks. Returns newest write time, byte total,
# and whether a reparse point was found anywhere inside.
function Get-TreeInfo {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    $info = @{ newest = $item.LastWriteTime; bytes = [long]0; reparse = $false; hasFiles = $false }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { $info.reparse = $true; return $info }
    if (-not $item.PSIsContainer) {
        $info.bytes = $item.Length
        return $info
    }
    $newest = $null
    $stack = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $stack.Push([System.IO.DirectoryInfo]$item)
    while ($stack.Count) {
        $dir = $stack.Pop()
        foreach ($child in $dir.EnumerateFileSystemInfos()) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { $info.reparse = $true; continue }
            if ($child -is [System.IO.DirectoryInfo]) { $stack.Push($child); continue }
            $info.hasFiles = $true
            $info.bytes += $child.Length
            if ($null -eq $newest -or $child.LastWriteTime -gt $newest) { $newest = $child.LastWriteTime }
        }
    }
    if ($null -ne $newest) { $info.newest = $newest }
    return $info
}

function Remove-Scratch {
    param([string]$Path, [string]$Base, [string]$Category, [string]$Label)
    try {
        if (-not (Test-UnderRoot -Path $Path -Base $Base)) {
            $script:Skips.Add("skipped: $Label is outside $Category root"); return
        }
        $info = Get-TreeInfo -Path $Path
        if ($info.reparse) {
            $script:Skips.Add("skipped: $Label contains a junction or symlink"); return
        }
        if ($WhatIf) {
            $script:Lines.Add("would remove $Category`: $Label")
        }
        else {
            try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop }
            catch { $script:Skips.Add("skipped: $Label could not be removed ($($_.Exception.Message))"); return }
        }
        $script:Stats[$Category].n++
        $script:Stats[$Category].bytes += $info.bytes
    }
    catch {
        $script:Skips.Add("skipped: $Label ($($_.Exception.Message))")
    }
}

function ConvertTo-UtcDate {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    $parsed = [DateTime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([DateTime]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) { return $parsed }
    return $null
}

function Get-ManifestField {
    param($Manifest, [string]$Name)
    if ($Manifest.PSObject.Properties.Name -contains $Name) { return $Manifest.$Name }
    return $null
}

# The host's plans/ plus each app overlay's plans/ (apps/<id>/plans): Set-VerifyReceipt writes evidence
# beside the manifest of whichever app was active, so the sweep looks in every one.
$plansDirs = [System.Collections.Generic.List[string]]::new()
$plansDirs.Add((Join-Path $Root 'plans'))
$appsDir = Join-Path $Root 'apps'
if (Test-Path -LiteralPath $appsDir -PathType Container) {
    foreach ($a in @(Get-ChildItem -LiteralPath $appsDir -Directory -ErrorAction SilentlyContinue)) {
        $ap = Join-Path $a.FullName 'plans'
        if (Test-Path -LiteralPath $ap -PathType Container) { $plansDirs.Add($ap) }
    }
}
$tmpDir = Join-Path $Root 'tmp'

# ---- 1 tmp --------------------------------------------------------------------
try {
    if (Test-Path -LiteralPath $tmpDir -PathType Container) {
        $refs = [System.Collections.Generic.List[string]]::new()
        $refRegex = [regex]'(?i)(?<![A-Za-z0-9_-])tmp[/\\]+[^"\s,''<>|]+'
        foreach ($pd in $plansDirs) {
            if (-not (Test-Path -LiteralPath $pd)) { continue }
            foreach ($mf in @(Get-ChildItem -LiteralPath $pd -Filter '*-manifest.json' -File -ErrorAction SilentlyContinue)) {
                try { $text = [System.IO.File]::ReadAllText($mf.FullName) } catch { continue }
                foreach ($m in $refRegex.Matches($text)) {
                    $rel = ($m.Value -replace '[/\\]+', '/').TrimEnd('.', '/')
                    $refs.Add((Get-NormalPath (Join-Path $Root $rel)))
                }
            }
        }
        $tmpNorm = Get-NormalPath $tmpDir
        $isReferenced = {
            param([string]$p)
            $pn = Get-NormalPath $p
            foreach ($r in $refs) {
                if ($pn -ieq $r) { return $true }
                if ($r.StartsWith($pn + $sep, [StringComparison]::OrdinalIgnoreCase)) { return $true }
                if ($pn.StartsWith($r + $sep, [StringComparison]::OrdinalIgnoreCase)) { return $true }
            }
            return $false
        }
        $candidates = [System.Collections.Generic.List[System.IO.FileSystemInfo]]::new()
        foreach ($e in @(Get-ChildItem -LiteralPath $tmpDir -Force)) {
            if ($e.Name -eq '.last-sweep') { continue }
            if ($e.PSIsContainer -and $e.Name -eq 'tickets' -and -not ($e.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                foreach ($t in @(Get-ChildItem -LiteralPath $e.FullName -Force)) { $candidates.Add($t) }
                continue
            }
            $candidates.Add($e)
        }
        foreach ($c in $candidates) {
            try {
                $info = Get-TreeInfo -Path $c.FullName
                if ($info.newest -ge $cutoff) { continue }
                if (& $isReferenced $c.FullName) { continue }
                $label = $c.FullName.Substring($tmpNorm.Length).TrimStart('\', '/') -replace '\\', '/'
                Remove-Scratch -Path $c.FullName -Base $tmpDir -Category 'tmp' -Label "tmp/$label"
            }
            catch { $script:Skips.Add("skipped: tmp/$($c.Name) ($($_.Exception.Message))") }
        }
    }
}
catch { $script:Skips.Add("skipped: tmp sweep ($($_.Exception.Message))") }

# ---- 2 evidence ---------------------------------------------------------------
try {
  foreach ($plansDir in $plansDirs) {
    $evRoot = Join-Path $plansDir 'evidence'
    if (Test-Path -LiteralPath $evRoot -PathType Container) {
        $evLabel = ((Get-NormalPath $plansDir).Substring((Get-NormalPath $Root).Length).TrimStart('\', '/')) -replace '\\', '/'
        foreach ($d in @(Get-ChildItem -LiteralPath $evRoot -Directory -Force)) {
            try {
                $mfPath = Join-Path $plansDir "$($d.Name)-manifest.json"
                $remove = $false
                if (Test-Path -LiteralPath $mfPath -PathType Leaf) {
                    $m = [System.IO.File]::ReadAllText($mfPath) | ConvertFrom-Json
                    $completed = ConvertTo-UtcDate (Get-ManifestField $m 'completedAtUtc')
                    $reclosed = ConvertTo-UtcDate (Get-ManifestField $m 'reclosedAtUtc')
                    $reopened = ConvertTo-UtcDate (Get-ManifestField $m 'reopenedAtUtc')
                    if ($null -eq $completed) { continue }
                    $closed = if ($reclosed -and $reclosed -gt $completed) { $reclosed } else { $completed }
                    if ($reopened -and $reopened -gt $closed) { continue }
                    $remove = (($nowUtc - $closed).TotalDays -gt $Days)
                }
                else {
                    $remove = ((Get-TreeInfo -Path $d.FullName).newest -lt $cutoff)
                }
                if ($remove) { Remove-Scratch -Path $d.FullName -Base $evRoot -Category 'evidence' -Label "$evLabel/evidence/$($d.Name)" }
            }
            catch { $script:Skips.Add("skipped: $evLabel/evidence/$($d.Name) ($($_.Exception.Message))") }
        }
    }
  }
}
catch { $script:Skips.Add("skipped: evidence sweep ($($_.Exception.Message))") }

# ---- 3 claude-eval temp folders -------------------------------------------------
try {
    if ($TempRoot -and (Test-Path -LiteralPath $TempRoot -PathType Container)) {
        foreach ($d in @(Get-ChildItem -LiteralPath $TempRoot -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($d.Name -notmatch '^claude-eval-[A-Za-z0-9]{6}$') { continue }
            try {
                if ((Get-TreeInfo -Path $d.FullName).newest -lt $cutoff) {
                    Remove-Scratch -Path $d.FullName -Base $TempRoot -Category 'evaltemp' -Label $d.Name
                }
            }
            catch { $script:Skips.Add("skipped: $($d.Name) ($($_.Exception.Message))") }
        }
    }
}
catch { $script:Skips.Add("skipped: eval temp sweep ($($_.Exception.Message))") }

# ---- 4 evals/results ------------------------------------------------------------
try {
    $resDir = Join-Path (Join-Path $Root 'evals') 'results'
    if (Test-Path -LiteralPath $resDir -PathType Container) {
        $runs = @(Get-ChildItem -LiteralPath $resDir -Directory -Force | Sort-Object Name -Descending)
        foreach ($r in @($runs | Select-Object -Skip ([Math]::Max($KeepEvalRuns, 0)))) {
            Remove-Scratch -Path $r.FullName -Base $resDir -Category 'evalres' -Label "evals/results/$($r.Name)"
        }
    }
}
catch { $script:Skips.Add("skipped: eval results sweep ($($_.Exception.Message))") }

# ---- marker and output ----------------------------------------------------------
if (-not $WhatIf) {
    try {
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $tmpDir '.last-sweep'), [DateTime]::UtcNow.ToString('yyyy-MM-dd'))
    }
    catch { $script:Skips.Add("skipped: could not write tmp/.last-sweep ($($_.Exception.Message))") }
}

$verb = if ($WhatIf) { 'would remove' } else { 'removed' }
$mb = { param($b) ('{0:N1} MB' -f ($b / 1MB)) }
$summary = @(
    @{ k = 'tmp'; text = "tmp: $verb $($script:Stats.tmp.n) item(s), $(& $mb $script:Stats.tmp.bytes)" }
    @{ k = 'evidence'; text = "evidence: $verb $($script:Stats.evidence.n) ticket folder(s)" }
    @{ k = 'evaltemp'; text = "eval temp: $verb $($script:Stats.evaltemp.n) folder(s)" }
    @{ k = 'evalres'; text = "eval results: $verb $($script:Stats.evalres.n) run(s)" }
)
foreach ($l in $script:Lines) { if (-not $Quiet) { Write-Output $l } }
foreach ($s in $summary) {
    if ($Quiet -and $script:Stats[$s.k].n -eq 0) { continue }
    Write-Output $s.text
}
foreach ($l in $script:Skips) { Write-Output $l }
