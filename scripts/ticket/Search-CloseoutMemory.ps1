#Requires -Version 7
<#
.SYNOPSIS
    Search prior ticket memory for compact lessons matching this ticket.

.DESCRIPTION
    Used by ticket-router at /start-ticket. Reads plans/closeout-index.md (product
    lessons) and _shared/workflow-failure-catalog.md (WF-* workflow defects). Prints
    JSON: [{ ticket, lesson }, ...] (max 8). Never dumps whole closeout files or the
    catalog into docSet.

.PARAMETER Query
    Free-text keywords from the work-item title / area.

.PARAMETER Repos
    Affected repo names (comma-separated or array).

.PARAMETER Integration
    an integration name from environments/, or empty.

.PARAMETER MaxResults
    Cap (default 8).

.PARAMETER IndexPath
    Override plans/closeout-index.md (tests).

.EXAMPLE
    .\Search-CloseoutMemory.ps1 -Query "document download" -Repos app -Integration payments
#>

[CmdletBinding()]
param(
    [string]$Query = '',
    [string[]]$Repos = @(),
    [string]$Integration = '',
    [int]$MaxResults = 8,
    [string]$IndexPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$PlansDir = Join-Path $RepoRoot 'plans'
$resolver = Join-Path (Split-Path $PSScriptRoot -Parent) 'lib/Resolve-AgenticApp.ps1'
if (Test-Path -LiteralPath $resolver) {
    . $resolver
    $app = Resolve-AgenticApp -HostRoot $RepoRoot
    if ($app.Id) { $PlansDir = $app.PlansDir }
}
if (-not $IndexPath) { $IndexPath = Join-Path $PlansDir 'closeout-index.md' }

if ($Repos.Count -eq 1 -and $Repos[0] -match ',') {
    $Repos = @($Repos[0] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

$terms = [System.Collections.Generic.List[string]]::new()
foreach ($piece in @($Query, $Integration) + @($Repos)) {
    if ([string]::IsNullOrWhiteSpace($piece)) { continue }
    foreach ($tok in ($piece -split '[^\w]+')) {
        if ($tok.Length -ge 3) { [void]$terms.Add($tok.ToLowerInvariant()) }
    }
}
$terms = @($terms | Select-Object -Unique)
if ($terms.Count -eq 0) {
    '[]'
    return
}

function Get-TermScore {
    param([string]$Text)
    $lower = $Text.ToLowerInvariant()
    $n = 0
    foreach ($t in $terms) {
        if ($lower.Contains($t)) { $n++ }
    }
    return $n
}

$hits = @()

if (Test-Path $IndexPath) {
    # Read ticket prefix so the row-pattern matches the configured format.
    . (Join-Path (Join-Path $PSScriptRoot 'lib') 'TicketPrefix.ps1')
    $prefixPat = Get-TicketPrefix -Root $RepoRoot
    $rowPattern = "^\|\s*$([regex]::Escape($prefixPat))\d+"

    Get-Content -Path $IndexPath | ForEach-Object {
        if ($_ -notmatch $rowPattern) { return }
        $score = Get-TermScore $_
        if ($score -le 0) { return }
        $cols = @($_.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($cols.Count -lt 3) { return }
        # Ticket | Domain | Lesson | Status | Added. A superseded lesson is history, not advice.
        if ($cols.Count -ge 4 -and $cols[3] -match '^(?i)superseded') { return }
        $hits += [pscustomobject]@{
            Ticket = $cols[0]
            Lesson = $cols[2]
            Score  = $score
        }
    }
}

$CatalogPath = Join-Path $RepoRoot '_shared\workflow-failure-catalog.md'
if (Test-Path -LiteralPath $CatalogPath) {
    $catalogTerms = [System.Collections.Generic.List[string]]::new()
    foreach ($tok in ($Query -split '[^\w]+')) {
        if ($tok.Length -ge 3) { [void]$catalogTerms.Add($tok.ToLowerInvariant()) }
    }
    $catalogTerms = @($catalogTerms | Select-Object -Unique)
    if ($catalogTerms.Count -gt 0) {
        $raw = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8
        $headingRx = [regex]'(?m)^## (WF-\d+)\b'
        $ms = $headingRx.Matches($raw)
        for ($i = 0; $i -lt $ms.Count; $i++) {
            $id = $ms[$i].Groups[1].Value
            $start = $ms[$i].Index
            $end = if ($i -lt $ms.Count - 1) { $ms[$i + 1].Index } else { $raw.Length }
            $block = $raw.Substring($start, $end - $start)
            $lower = $block.ToLowerInvariant()
            $score = 0
            foreach ($t in $catalogTerms) {
                if ([regex]::IsMatch($lower, ('\b{0}\b' -f [regex]::Escape($t)))) { $score++ }
            }
            if ($score -le 0) { continue }
            $lesson = $block
            if ($block -match '(?s)\*\*Shape to expect\.\*\*\s*(.+?)(?:\r?\n\r?\n|\r?\n---|\z)') {
                $lesson = ($Matches[1] -replace '\s+', ' ').Trim()
            }
            if ($lesson.Length -gt 220) { $lesson = $lesson.Substring(0, 217) + '...' }
            $hits += [pscustomobject]@{
                Ticket = $id
                Lesson = $lesson
                Score  = $score
            }
        }
    }
}

# There is deliberately no fall-through to plans/<ticket>-closeout.md. Those files are
# now written only for the rare ticket whose retrospective earned a page, and that
# ticket's lesson is already an index row -- scanning them would re-read whole
# files to rediscover a line that is one grep away. The catalog is scored against
# -Query only (not repo names) so a repo name in a WF- shape does not fire on every ticket.

$result = @(
    $hits |
        Sort-Object Score -Descending |
        Select-Object -First $MaxResults |
        ForEach-Object {
            [ordered]@{ ticket = $_.Ticket; lesson = $_.Lesson }
        }
)

if ($result.Count -eq 0) {
    '[]'
} else {
    $json = $result | ConvertTo-Json -Compress
    if ($result.Count -eq 1 -and $json -notmatch '^\s*\[') { "[$json]" } else { $json }
}
