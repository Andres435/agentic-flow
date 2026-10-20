#Requires -Version 7
#Requires -Modules Pester
<#
.SYNOPSIS
    Pester 5 tests for Park-Ticket.ps1 and Resume-Ticket.ps1: a ticket that stops before
    /complete-task gets a closed span, a parked ledger row and a passing park gate; a resume
    opens a new span so the idle gap is excluded; the final close sums every span.

.DESCRIPTION
    Each test builds a ticket root under $TestDrive (plans/TICKET-9-manifest.json) and runs the
    real scripts against it with -Root.
#>

BeforeAll {
    $script:ParkScript = Join-Path $PSScriptRoot 'Park-Ticket.ps1'
    $script:ResumeScript = Join-Path $PSScriptRoot 'Resume-Ticket.ps1'
    $script:CloseScript = Join-Path $PSScriptRoot 'Close-Ticket.ps1'
    $script:HoursScript = Join-Path $PSScriptRoot 'Get-SessionHours.ps1'
    $script:AssertScript = Join-Path $PSScriptRoot 'Assert-TicketArtifacts.ps1'
    $script:PwshHost = (Get-Command pwsh).Source
    $script:Utf8 = New-Object System.Text.UTF8Encoding($false)
    $env:TMO_CTX_USAGE_FILE = Join-Path $TestDrive 'no-ctx-usage.json'
    $script:RealTemp = $env:TEMP
    $env:TEMP = Join-Path $TestDrive 'empty-temp'
    New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null

    function New-TicketRoot {
        param([string]$Name, [hashtable]$Extra = @{})
        $root = Join-Path $TestDrive $Name
        $plans = Join-Path $root 'plans'
        New-Item -ItemType Directory -Path $plans -Force | Out-Null
        $entry = [pscustomobject]@{ verdict = 'Ready'; mode = 'staged'; fingerprint = ('ab' * 32); fpVersion = 2 }
        $manifest = [ordered]@{
            ticket        = 'TICKET-9'
            mode          = 'branch'
            workType      = 'bug'
            startedAtUtc  = [DateTime]::UtcNow.AddDays(-3).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            ctxPct        = @{ start = 40; review = 50 }
            affectedRepos = @([pscustomobject]@{ repo = 'app'; local = $true })
            reviewReady   = [pscustomobject]@{ mode = 'staged'; repos = [pscustomobject]@{ app = $entry } }
            verify        = @{ repos = @{ app = @{ pass = $true; tests = 'pass'; sonar = 'ok' } } }
        }
        foreach ($k in $Extra.Keys) { $manifest[$k] = $Extra[$k] }
        [System.IO.File]::WriteAllText((Join-Path $plans 'TICKET-9-manifest.json'), ($manifest | ConvertTo-Json -Depth 8), $script:Utf8)
        return $root
    }

    function Invoke-Script {
        param([string]$Script, [string[]]$Arguments)
        $out = & $script:PwshHost -NoProfile -NonInteractive -File $Script @Arguments 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($out -join "`n") }
    }

    function Invoke-Park { param([string]$Root, [string]$Outcome = 'more-info')
        Invoke-Script $script:ParkScript @('-Ticket', 'TICKET-9', '-Outcome', $Outcome, '-Root', $Root) }
    function Invoke-Resume { param([string]$Root)
        Invoke-Script $script:ResumeScript @('-Ticket', 'TICKET-9', '-Root', $Root) }

    function Get-Manifest([string]$Root) {
        Get-Content -LiteralPath (Join-Path $Root 'plans/TICKET-9-manifest.json') -Raw | ConvertFrom-Json
    }

    function Get-LedgerRows([string]$Root) {
        $ledger = Join-Path $Root 'plans/ticket-ledger.md'
        if (-not (Test-Path -LiteralPath $ledger)) { return @() }
        return @(Get-Content -LiteralPath $ledger | Where-Object { $_ -match '^\|\s*TICKET-9\s*\|' })
    }

    function Get-LedgerCells([string]$Row) {
        return @(($Row.Trim() -replace '^\|', '' -replace '\|$', '') -split '\|' | ForEach-Object { $_.Trim() })
    }
}

AfterAll {
    Remove-Item Env:TMO_CTX_USAGE_FILE -ErrorAction SilentlyContinue
    $env:TEMP = $script:RealTemp
}

Describe 'Park-Ticket' {
    It 'closes the open span, stamps the park, writes an Outcome row with no scorecard, passes the park gate' {
        $root = New-TicketRoot 'park'
        $r = Invoke-Park -Root $root
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match '\[PASS\] TICKET-9 parked'
        $m = Get-Manifest $root
        $m.parkedAtUtc | Should -Not -BeNullOrEmpty
        $m.parkedState | Should -Be 'More Info Needed'
        $m.parkedOutcome | Should -Be 'more-info'
        $m.PSObject.Properties.Name | Should -Not -Contain 'completedAtUtc'
        @($m.spans).Count | Should -Be 1
        @($m.spans)[0].kind | Should -Be 'original'
        @($m.spans)[0].endedAtUtc | Should -Not -BeNullOrEmpty
        $rows = @(Get-LedgerRows $root)
        $rows.Count | Should -Be 1
        $cells = Get-LedgerCells $rows[0]
        $cells[5] | Should -BeNullOrEmpty   # Pts
        $cells[6] | Should -BeNullOrEmpty   # E
        $cells[18] | Should -Be 'more-info'
    }

    It 'records closed-by-ado with the default Closed state' {
        $root = New-TicketRoot 'ado'
        (Invoke-Park -Root $root -Outcome 'closed-by-ado').ExitCode | Should -Be 0
        (Get-Manifest $root).parkedState | Should -Be 'Closed'
        (Get-LedgerCells @(Get-LedgerRows $root)[0])[18] | Should -Be 'closed-by-ado'
    }

    It 'a repeat park keeps the first stamp and one row' {
        $root = New-TicketRoot 'repeat'
        (Invoke-Park -Root $root).ExitCode | Should -Be 0
        $first = (Get-Manifest $root).parkedAtUtc
        (Invoke-Park -Root $root).ExitCode | Should -Be 0
        (Get-Manifest $root).parkedAtUtc | Should -Be $first
        @(Get-LedgerRows $root).Count | Should -Be 1
    }

    It 'refuses a ticket already closed through /complete-task' {
        $root = New-TicketRoot 'closed' @{ completedAtUtc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
        $r = Invoke-Park -Root $root
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'park step 1'
        @(Get-LedgerRows $root).Count | Should -Be 0
    }

    It '-WhatIf writes nothing' {
        $root = New-TicketRoot 'whatif'
        $r = Invoke-Script $script:ParkScript @('-Ticket', 'TICKET-9', '-Outcome', 'more-info', '-Root', $root, '-WhatIf')
        $r.ExitCode | Should -Be 0
        (Get-Manifest $root).PSObject.Properties.Name | Should -Not -Contain 'parkedAtUtc'
        @(Get-LedgerRows $root).Count | Should -Be 0
    }
}

Describe 'Assert-TicketArtifacts -Phase park' {
    It 'passes a parked ticket' {
        $root = New-TicketRoot 'gate-ok'
        (Invoke-Park -Root $root).ExitCode | Should -Be 0
        (Invoke-Script $script:AssertScript @('-Ticket', 'TICKET-9', '-Phase', 'park', '-Root', $root)).ExitCode | Should -Be 0
    }

    It 'fails a ticket with no park stamp' {
        $root = New-TicketRoot 'gate-none'
        $r = Invoke-Script $script:AssertScript @('-Ticket', 'TICKET-9', '-Phase', 'park', '-Root', $root)
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'parkedAtUtc'
    }

    It 'fails a parked ticket that still has an open span' {
        $root = New-TicketRoot 'gate-open' @{
            parkedAtUtc = '2026-03-02T17:00:00Z'; parkedState = 'More Info Needed'
            spans = @([pscustomobject]@{ kind = 'original'; startedAtUtc = '2026-03-02T15:00:00Z'; endedAtUtc = $null })
        }
        $r = Invoke-Script $script:AssertScript @('-Ticket', 'TICKET-9', '-Phase', 'park', '-Root', $root)
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'still open'
    }
}

Describe 'Resume-Ticket' {
    It 'opens a resume span, clears the park stamp and keeps it in parkHistory' {
        $root = New-TicketRoot 'resume'
        (Invoke-Park -Root $root).ExitCode | Should -Be 0
        $r = Invoke-Resume -Root $root
        $r.ExitCode | Should -Be 0
        $m = Get-Manifest $root
        $m.parkedAtUtc | Should -BeNullOrEmpty
        @($m.parkHistory).Count | Should -Be 1
        $open = @($m.spans | Where-Object { -not $_.endedAtUtc })
        $open.Count | Should -Be 1
        $open[0].kind | Should -Be 'resume'
    }

    It 'fails on a ticket that is not parked' {
        $root = New-TicketRoot 'resume-none'
        (Invoke-Resume -Root $root).ExitCode | Should -Be 1
    }

    It 'a hand-stamped park (no spans) resumes with the pre-park work kept as an original span' {
        $root = New-TicketRoot 'resume-hand' @{ parkedAtUtc = '2026-03-02T17:00:00Z'; startedAtUtc = '2026-03-02T15:00:00Z' }
        (Invoke-Resume -Root $root).ExitCode | Should -Be 0
        $kinds = @((Get-Manifest $root).spans | ForEach-Object { $_.kind })
        $kinds | Should -Be @('original', 'resume')
    }

    It 'hours count the spans, not the idle gap between them' {
        # Mon 2026-03-02 2 h, then a week idle, then Mon 2026-03-09 1 h: 3.0, not a week of work.
        $root = New-TicketRoot 'hours' @{
            startedAtUtc = '2026-03-02T15:00:00Z'
            completedAtUtc = '2026-03-09T16:00:00Z'
            spans = @(
                [pscustomobject]@{ kind = 'original'; startedAtUtc = '2026-03-02T15:00:00Z'; endedAtUtc = '2026-03-02T17:00:00Z' },
                [pscustomobject]@{ kind = 'resume'; startedAtUtc = '2026-03-09T15:00:00Z'; endedAtUtc = '2026-03-09T16:00:00Z' })
        }
        $r = Invoke-Script $script:HoursScript @('-Ticket', 'TICKET-9', '-Root', $root, '-Json')
        $r.ExitCode | Should -Be 0
        ($r.Output | ConvertFrom-Json).hours | Should -Be 3.0
    }

    It 'Close-Ticket refuses a parked ticket, then closes a resumed one with every span ended' {
        $root = New-TicketRoot 'close'
        (Invoke-Park -Root $root).ExitCode | Should -Be 0
        $args9 = @('-Ticket', 'TICKET-9', '-Efficiency', '4', '-Contextualization', '4', '-CostTokens', '3', '-Root', $root)
        $refused = Invoke-Script $script:CloseScript $args9
        $refused.ExitCode | Should -Be 1
        $refused.Output | Should -Match 'parked'

        (Invoke-Resume -Root $root).ExitCode | Should -Be 0
        $r = Invoke-Script $script:CloseScript $args9
        $r.ExitCode | Should -Be 0
        $m = Get-Manifest $root
        $m.completedAtUtc | Should -Not -BeNullOrEmpty
        @($m.spans | Where-Object { -not $_.endedAtUtc }).Count | Should -Be 0
        @($m.spans).Count | Should -Be 2
        $rows = @(Get-LedgerRows $root)
        $rows.Count | Should -Be 1
        (Get-LedgerCells $rows[0])[18] | Should -BeNullOrEmpty
        (Get-LedgerCells $rows[0])[6] | Should -Be '4'
    }
}
