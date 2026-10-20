#Requires -Version 7
<#
.SYNOPSIS
    Sum closed work spans into capped hours and a story-point bucket.

.DESCRIPTION
    Hours come from closed spans, not from the wall clock between the first start
    and the last close. Original and reopen spans are the manifest timestamps.
    A pr-feedback span is written by -BeginSpan and -EndSpan. A ticket parked before
    /complete-task (Park-Ticket.ps1) closes its original span at the park time, and
    Resume-Ticket.ps1 opens a resume span, so the idle gap is never counted. Weekends and US
    federal holidays count as zero. Each local calendar day is capped at 8 hours
    across every span. Gaps between spans are zero. The point bucket is printed
    only. This script does not write a tracker field.

.PARAMETER Ticket
    Ticket id, with or without the profile prefix.

.PARAMETER Root
    Override the workflow repo root (tests).

.PARAMETER Json
    Emit hours, points, days, and holidays as JSON.

.PARAMETER Preview
    Count a span that has started but not closed (no completedAtUtc, or a reopen with no
    reclosedAtUtc) up to now, without writing. For the approval package before close;
    Close-Ticket.ps1 stamps the close and computes the real value.
.PARAMETER BeginSpan
    Open a pr-feedback span at the current UTC time.

.PARAMETER EndSpan
    Close the latest open pr-feedback span.

.EXAMPLE
    .\Get-SessionHours.ps1 -Ticket TICKET-42 -Json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Ticket,
    [string]$Root,
    [switch]$Json,
    [switch]$Preview,
    [ValidateSet('pr-feedback')][string]$BeginSpan,
    [ValidateSet('pr-feedback')][string]$EndSpan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path $PSScriptRoot 'lib') 'ManifestFields.ps1')

$Key = Get-TicketKeyFromRaw -Ticket $Ticket
$RepoRoot = if ($Root) { $Root } else { Get-CursorRepoRoot -FromScriptRoot $PSScriptRoot }
$manifestPath = Get-TicketManifestFile -RepoRoot $RepoRoot -TicketKey $Key
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifest not found: $manifestPath" }

function Get-Prop {
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return $null }
    if ($Obj.PSObject.Properties.Name -notcontains $Name) { return $null }
    return $Obj.$Name
}

function ConvertTo-Utc {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    return [DateTime]::Parse([string]$Value, $null, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
}

function Get-Zone {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = 'America/Los_Angeles' }
    $windows = $Name
    $converted = $null
    if ([TimeZoneInfo]::TryConvertIanaIdToWindowsId($Name, [ref]$converted)) { $windows = $converted }
    return [TimeZoneInfo]::FindSystemTimeZoneById($windows)
}

function Get-NthWeekday {
    param([int]$Year, [int]$Month, [DayOfWeek]$Day, [int]$N, [switch]$Last)
    if ($Last) {
        $cursor = [datetime]::new($Year, $Month, [DateTime]::DaysInMonth($Year, $Month))
        while ($cursor.DayOfWeek -ne $Day) { $cursor = $cursor.AddDays(-1) }
        return $cursor.Date
    }
    $cursor = [datetime]::new($Year, $Month, 1)
    while ($cursor.DayOfWeek -ne $Day) { $cursor = $cursor.AddDays(1) }
    return $cursor.AddDays(7 * ($N - 1)).Date
}

function Get-Observed {
    param([datetime]$Date)
    if ($Date.DayOfWeek -eq [DayOfWeek]::Saturday) { return $Date.AddDays(-1).Date }
    if ($Date.DayOfWeek -eq [DayOfWeek]::Sunday) { return $Date.AddDays(1).Date }
    return $Date.Date
}

function Get-HolidaySet {
    param([int[]]$Years)
    $set = @{}
    foreach ($year in $Years) {
        foreach ($monthDay in @(@(1, 1), @(6, 19), @(7, 4), @(11, 11), @(12, 25))) {
            $set[(Get-Observed ([datetime]::new($year, $monthDay[0], $monthDay[1]))).ToString('yyyy-MM-dd')] = $true
        }
        $set[(Get-NthWeekday $year 1 Monday 3).ToString('yyyy-MM-dd')] = $true
        $set[(Get-NthWeekday $year 2 Monday 3).ToString('yyyy-MM-dd')] = $true
        $set[(Get-NthWeekday $year 5 Monday 1 -Last).ToString('yyyy-MM-dd')] = $true
        $set[(Get-NthWeekday $year 9 Monday 1).ToString('yyyy-MM-dd')] = $true
        $set[(Get-NthWeekday $year 11 Thursday 4).ToString('yyyy-MM-dd')] = $true
    }
    return $set
}

function Get-SpanList {
    param($Manifest)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($span in @($(Get-Prop $Manifest 'spans'))) {
        if (-not $span) { continue }
        $list.Add([pscustomobject]@{
            kind         = [string](Get-Prop $span 'kind')
            startedAtUtc = Get-Prop $span 'startedAtUtc'
            endedAtUtc   = Get-Prop $span 'endedAtUtc'
        })
    }
    return ,$list
}

function Add-DerivedSpan {
    param($List, $Manifest, [string]$Kind, [string]$StartName, [string]$EndName)
    if (@($List | Where-Object { $_.kind -eq $Kind }).Count -gt 0) { return }
    $start = Get-Prop $Manifest $StartName
    $end = Get-Prop $Manifest $EndName
    if ($start -and $end) {
        $List.Add([pscustomobject]@{ kind = $Kind; startedAtUtc = [string]$start; endedAtUtc = [string]$end })
    }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$spans = Get-SpanList $manifest

if ($BeginSpan) {
    $spans.Add([pscustomobject]@{
        kind         = $BeginSpan
        startedAtUtc = [DateTime]::UtcNow.ToString('o')
        endedAtUtc   = $null
    })
    Merge-TicketManifestFields -ManifestPath $manifestPath -Patch @{ spans = @($spans) }
    Write-Output "Opened $BeginSpan span on $Key"
    exit 0
}

if ($EndSpan) {
    $open = $null
    for ($i = $spans.Count - 1; $i -ge 0; $i--) {
        if ($spans[$i].kind -eq $EndSpan -and -not $spans[$i].endedAtUtc) { $open = $spans[$i]; break }
    }
    if (-not $open) { throw "No open $EndSpan span on $Key" }
    $open.endedAtUtc = [DateTime]::UtcNow.ToString('o')
    Merge-TicketManifestFields -ManifestPath $manifestPath -Patch @{ spans = @($spans) }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $spans = Get-SpanList $manifest
}

if ($Preview) {
    $nowIso = [DateTime]::UtcNow.ToString('o')
    $startedAt = Get-Prop $manifest 'startedAtUtc'
    # A resumed ticket carries an explicit original span (written by Park-Ticket.ps1) and an
    # open resume span; count the open one to now instead of re-deriving the original.
    foreach ($open in @($spans | Where-Object { $_.startedAtUtc -and -not $_.endedAtUtc })) { $open.endedAtUtc = $nowIso }
    $hasOriginal = @($spans | Where-Object { $_.kind -eq 'original' }).Count -gt 0
    if ($startedAt -and -not $hasOriginal -and -not (Get-Prop $manifest 'completedAtUtc')) {
        $spans.Add([pscustomobject]@{ kind = 'original'; startedAtUtc = [string]$startedAt; endedAtUtc = $nowIso })
    }
    $reopenedAt = Get-Prop $manifest 'reopenedAtUtc'
    if ($reopenedAt -and -not (Get-Prop $manifest 'reclosedAtUtc')) {
        $spans.Add([pscustomobject]@{ kind = 'reopen'; startedAtUtc = [string]$reopenedAt; endedAtUtc = $nowIso })
    }
}
Add-DerivedSpan $spans $manifest 'original' 'startedAtUtc' 'completedAtUtc'
Add-DerivedSpan $spans $manifest 'reopen' 'reopenedAtUtc' 'reclosedAtUtc'

$zone = Get-Zone ([string](Get-Prop $manifest 'timezone'))
$closed = @($spans | Where-Object { $_.startedAtUtc -and $_.endedAtUtc })
$years = @()
foreach ($span in $closed) {
    $years += (ConvertTo-Utc $span.startedAtUtc).Year
    $years += (ConvertTo-Utc $span.endedAtUtc).Year
}
if (-not $years) { $years = @([DateTime]::UtcNow.Year) }
$holidays = Get-HolidaySet ($years | Select-Object -Unique)

$byDay = @{}
foreach ($span in $closed) {
    $localStart = [TimeZoneInfo]::ConvertTimeFromUtc((ConvertTo-Utc $span.startedAtUtc), $zone)
    $localEnd = [TimeZoneInfo]::ConvertTimeFromUtc((ConvertTo-Utc $span.endedAtUtc), $zone)
    if ($localEnd -le $localStart) { continue }
    $day = $localStart.Date
    while ($day -le $localEnd.Date) {
        $key = $day.ToString('yyyy-MM-dd')
        $windowStart = $day
        $windowEnd = $day.AddDays(1)
        $segStart = if ($localStart -gt $windowStart) { $localStart } else { $windowStart }
        $segEnd = if ($localEnd -lt $windowEnd) { $localEnd } else { $windowEnd }
        if ($segEnd -gt $segStart) {
            if (-not $byDay.ContainsKey($key)) { $byDay[$key] = New-Object System.Collections.Generic.List[object] }
            $byDay[$key].Add([pscustomobject]@{ Start = $segStart; End = $segEnd })
        }
        $day = $day.AddDays(1)
    }
}

$dayRows = @()
$flagged = @()
$total = 0.0
foreach ($key in ($byDay.Keys | Sort-Object)) {
    $date = [datetime]::Parse($key)
    $merged = New-Object System.Collections.Generic.List[object]
    foreach ($piece in ($byDay[$key] | Sort-Object Start)) {
        if ($merged.Count -eq 0 -or $piece.Start -gt $merged[$merged.Count - 1].End) {
            $merged.Add([pscustomobject]@{ Start = $piece.Start; End = $piece.End })
        }
        elseif ($piece.End -gt $merged[$merged.Count - 1].End) {
            $merged[$merged.Count - 1].End = $piece.End
        }
    }
    $hours = 0.0
    foreach ($piece in $merged) { $hours += ($piece.End - $piece.Start).TotalHours }
    $weekend = $date.DayOfWeek -in @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)
    $holiday = $holidays.ContainsKey($key)
    if ($holiday) { $flagged += $key }
    if ($weekend -or $holiday) { $hours = 0 }
    elseif ($hours -gt 8) { $hours = 8 }
    $hours = [math]::Round($hours, 1)
    $total += $hours
    $dayRows += [pscustomobject]@{ date = $key; hours = $hours }
}
$total = [math]::Round($total, 1)

$points = $null
if ($total -gt 0 -and $total -le 2) { $points = 1 }
elseif ($total -le 4 -and $total -gt 0) { $points = 2 }
elseif ($total -le 16 -and $total -gt 0) { $points = 3 }
elseif ($total -le 24 -and $total -gt 0) { $points = 5 }
elseif ($total -le 40 -and $total -gt 0) { $points = 8 }
elseif ($total -gt 40) { $points = 13 }

if ($Json) {
    [pscustomobject]@{
        ticket   = $Key
        hours    = $total
        points   = $points
        holidays = @($flagged)
        days     = @($dayRows)
    } | ConvertTo-Json -Depth 5
    exit 0
}

Write-Output "Session hours for $Key : $total h"
if ($null -ne $points) { Write-Output "Story points: $points" }
foreach ($row in $dayRows) { Write-Output ("  {0}: {1} h" -f $row.date, $row.hours) }
if ($flagged) { Write-Output ("Holidays flagged: " + ($flagged -join ', ')) }
exit 0
