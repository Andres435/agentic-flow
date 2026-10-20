#Requires -Modules Pester
<#
.SYNOPSIS
    Pester 5 tests for ledger column migration (11-col to CtxS%/CtxR%/Ctx%).
#>

BeforeAll {
    function Get-PowerShell7Path {
        $cmd = Get-Command 'pwsh' -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { return $cmd.Source }
        throw "PowerShell 7 (pwsh) is required. See MACHINE-SETUP.md."
    }
    $script:PwshHost = Get-PowerShell7Path
    $script:LedgerScript = Join-Path $PSScriptRoot 'Update-TicketLedger.ps1'
}

Describe 'Update-TicketLedger column migration' {
    It 'keeps old Ctx% in Ctx% and inserts empty CtxS%/CtxR%' {
        $root = Join-Path $TestDrive 'ledger-root'
        $plans = Join-Path $root 'plans'
        New-Item -ItemType Directory -Path $plans -Force | Out-Null
        $old = @(
            '# Ticket ledger'
            ''
            '| Tickets | Scored | Avg E | Avg C | Avg $tok | Avg Ctx% |'
            '|---|---|---|---|---|---|'
            '| 1 | 1 | 4 | 4 | 3 | 45% |'
            ''
            '| Ticket | Type | Closed | Mode | Hours | Pts | E | C | $tok | Ctx% | PR |'
            '|---|---|---|---|---|---|---|---|---|---|---|'
            '| WI00001 | feature | 2026-09-01 | branch | 4 | 2 | 4 | 4 | 3 | 45 | 123 |'
        ) -join "`n"
        [System.IO.File]::WriteAllText((Join-Path $plans 'ticket-ledger.md'), $old + "`n", (New-Object System.Text.UTF8Encoding $false))

        & $script:PwshHost -NonInteractive -NoProfile -File $script:LedgerScript -Rewrite -Root $root
        $LASTEXITCODE | Should -Be 0

        $text = Get-Content -LiteralPath (Join-Path $plans 'ticket-ledger.md') -Raw -Encoding UTF8
        $text | Should -Match 'CtxS%'
        $text | Should -Match 'CtxR%'
        $hdr = ($text -split "`n" | Where-Object { $_ -match 'Ticket.*Type.*Closed' } | Select-Object -First 1)
        $hdr | Should -Match 'CtxS%'
        $row = ($text -split "`n" | Where-Object { $_ -match '^\|\s*WI00001' } | Select-Object -First 1)
        $cells = @(($row.Trim() -replace '^\|', '' -replace '\|$', '') -split '\|' | ForEach-Object { $_.Trim() })
        $cells.Count | Should -Be 19
        ($cells[14..17] -join '|') | Should -Be '|||'
        $cells[9] | Should -Be ''
        $cells[10] | Should -Be ''
        $cells[11] | Should -Be '45'
        $cells[12] | Should -Be '123'
        $cells[13] | Should -Be ''
    }

    It 'writes Lanes and a CtxS coverage line without backfilling older rows' {
        $root = Join-Path $TestDrive 'lanes-root'
        $plans = Join-Path $root 'plans'
        New-Item -ItemType Directory -Path $plans -Force | Out-Null
        & $script:PwshHost -NonInteractive -NoProfile -File $script:LedgerScript `
            -Root $root -Ticket WI00002 -Type bug -Mode branch -Efficiency 4 -Contextualization 4 -CostTokens 3 `
            -ContextPct 40 -ContextPctStart 55 -Lanes 'f1/s0/d0 inline:d2'
        $LASTEXITCODE | Should -Be 0
        $text = Get-Content -LiteralPath (Join-Path $plans 'ticket-ledger.md') -Raw -Encoding UTF8
        $text | Should -Match 'f1/s0/d0 inline:d2'
        $text | Should -Match 'CtxS on 1 of 1 scored branch rows'
    }

    It 'refuses a free-text Lanes value and writes no row' {
        $root = Join-Path $TestDrive 'lanes-free-text'
        $plans = Join-Path $root 'plans'
        New-Item -ItemType Directory -Path $plans -Force | Out-Null
        $out = & $script:PwshHost -NonInteractive -NoProfile -File $script:LedgerScript `
            -Root $root -Ticket TICKET-00003 -Type spike -Mode investigate -Efficiency 3 -Contextualization 3 -CostTokens 4 `
            -Lanes 'opus x3 verify (deep)' 2>&1 | Out-String
        $LASTEXITCODE | Should -Not -Be 0
        $out | Should -Match 'is not fN/sN/dN'
        Test-Path -LiteralPath (Join-Path $plans 'ticket-ledger.md') | Should -BeFalse
    }
}

Describe 'Update-TicketLedger objective outcome columns' {
    BeforeAll {
        function script:New-OutcomeRoot {
            param([string]$Name, [hashtable]$Manifests = @{})
            $root = Join-Path $TestDrive $Name
            $plans = Join-Path $root 'plans'
            New-Item -ItemType Directory -Path $plans -Force | Out-Null
            foreach ($k in $Manifests.Keys) {
                [System.IO.File]::WriteAllText((Join-Path $plans "$k-manifest.json"), $Manifests[$k], (New-Object System.Text.UTF8Encoding $false))
            }
            return $root
        }
        function script:Write-OldLedger {
            param([string]$Root, [string[]]$Rows)
            $lines = @(
                '# Ticket ledger'
                ''
                '| Ticket | Type | Closed | Mode | Hours | Pts | E | C | $tok | CtxS% | CtxR% | Ctx% | PR | Lanes | Epoch |'
                '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|'
            ) + $Rows
            [System.IO.File]::WriteAllText((Join-Path (Join-Path $Root 'plans') 'ticket-ledger.md'), ($lines -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
        }
        function script:Get-LedgerText {
            param([string]$Root)
            Get-Content -LiteralPath (Join-Path (Join-Path $Root 'plans') 'ticket-ledger.md') -Raw -Encoding UTF8
        }
        function script:Get-LedgerCells {
            param([string]$Root, [string]$Ticket)
            $row = ((Get-LedgerText -Root $Root) -split "`n" | Where-Object { $_ -match "^\|\s*$Ticket\b" } | Select-Object -First 1)
            return ,@(($row.Trim() -replace '^\|', '' -replace '\|$', '') -split '\|' | ForEach-Object { $_.Trim() })
        }
        function script:Invoke-Ledger {
            param([string[]]$LedgerArgs)
            & $script:PwshHost -NonInteractive -NoProfile -File $script:LedgerScript @LedgerArgs | Out-Null
        }
    }

    It 'has Reopened, Days and PRFind as the last header columns and the self-rated sentence' {
        $root = New-OutcomeRoot -Name 'hdr'
        Invoke-Ledger @('-Root', $root, '-Ticket', 'TICKET-00010', '-Type', 'bug', '-Mode', 'branch')
        $text = Get-LedgerText -Root $root
        $text | Should -Match '\| Epoch \| Reopened \| Days \| PRFind \|'
        $text | Should -Match 'self-rated; Reopened, Days and PRFind are computed from manifests'
        $text | Should -Match 'Reopened \| Avg Days'
    }

    It 'computes no, Days and a blank PRFind for a closed ticket without feedback' {
        $m = '{"startedAtUtc":"2026-10-02T15:00:00Z","completedAtUtc":"2026-10-04T03:00:00Z","reopenedAtUtc":null,"reclosedAtUtc":null}'
        $root = New-OutcomeRoot -Name 'plain' -Manifests @{ 'TICKET-00011' = $m }
        Invoke-Ledger @('-Root', $root, '-Ticket', 'TICKET-00011', '-Type', 'bug', '-Mode', 'branch')
        $c = Get-LedgerCells -Root $root -Ticket 'TICKET-00011'
        $c.Count | Should -Be 19
        ($c[15..17] -join '|') | Should -Be 'no|1.5|'
    }

    It 'uses the last reclosedAtUtc for a reopened ticket and counts only thread and sonar items' {
        $m = '{"startedAtUtc":"2026-10-01T00:00:00Z","completedAtUtc":"2026-10-02T00:00:00Z","reopenedAtUtc":"2026-10-05T00:00:00Z","reclosedAtUtc":"2026-10-06T12:00:00Z","feedback":{"prs":[],"items":[{"kind":"thread"},{"kind":"sonar"},{"kind":"metric"},{"kind":"thread"}]}}'
        $root = New-OutcomeRoot -Name 'reopen' -Manifests @{ 'TICKET-00012' = $m }
        Invoke-Ledger @('-Root', $root, '-Ticket', 'TICKET-00012', '-Type', 'bug', '-Mode', 'branch')
        $c = Get-LedgerCells -Root $root -Ticket 'TICKET-00012'
        ($c[15..17] -join '|') | Should -Be 'yes|5.5|3'
    }

    It 'uses completedAtUtc when reopened but not reclosed, and counts zero findings' {
        $m = '{"startedAtUtc":"2026-10-01T00:00:00Z","completedAtUtc":"2026-10-02T12:00:00Z","reopenedAtUtc":"2026-10-05T00:00:00Z","reclosedAtUtc":null,"feedback":{"prs":[],"items":[]}}'
        $root = New-OutcomeRoot -Name 'reopen-open' -Manifests @{ 'TICKET-00013' = $m }
        Invoke-Ledger @('-Root', $root, '-Ticket', 'TICKET-00013', '-Type', 'bug', '-Mode', 'branch')
        $c = Get-LedgerCells -Root $root -Ticket 'TICKET-00013'
        ($c[15..17] -join '|') | Should -Be 'yes|1.5|0'
    }

    It 'leaves all three blank when the manifest is missing' {
        $root = New-OutcomeRoot -Name 'nomanifest'
        Invoke-Ledger @('-Root', $root, '-Ticket', 'TICKET-00014', '-Type', 'bug', '-Mode', 'branch')
        $c = Get-LedgerCells -Root $root -Ticket 'TICKET-00014'
        ($c[15..17] -join '|') | Should -Be '||'
    }

    It '-Rewrite migrates a 15-column row to the new header without changing values' {
        $root = New-OutcomeRoot -Name 'migrate15'
        Write-OldLedger -Root $root -Rows @('| WI00020 | bug | 2026-10-02 | branch | 6.2 | 3 | 3 | 4 | 4 | 62 | | 30 | 14713 | f1/s0/d0 | abc12345 |')
        Invoke-Ledger @('-Root', $root, '-Rewrite')
        (Get-LedgerText -Root $root) | Should -Match '\| Epoch \| Reopened \| Days \| PRFind \|'
        $c = Get-LedgerCells -Root $root -Ticket 'WI00020'
        $c.Count | Should -Be 19
        ($c[0..14] -join '|') | Should -Be 'WI00020|bug|2026-10-02|branch|6.2|3|3|4|4|62||30|14713|f1/s0/d0|abc12345'
        ($c[15..17] -join '|') | Should -Be '||'
    }

    It '-Regenerate fills existing rows from manifests, touches no other cell, and skips a manifest-less row' {
        $m = '{"startedAtUtc":"2026-10-02T00:00:00Z","completedAtUtc":"2026-10-03T06:00:00Z","reopenedAtUtc":null,"reclosedAtUtc":null,"feedback":{"prs":[],"items":[{"kind":"sonar"}]}}'
        $root = New-OutcomeRoot -Name 'regen' -Manifests @{ WI00030 = $m }
        Write-OldLedger -Root $root -Rows @(
            '| WI00030 | bug | 2026-10-03 | branch | 6.2 | 3 | 3 | 4 | 4 | 62 | | 30 | 14713 | f1/s0/d0 | abc12345 |'
            '| WI00031 | spike | 2026-10-04 | investigate | 2 | 1 | 3 | 3 | 4 | | | | | | abc12345 |')
        Invoke-Ledger @('-Root', $root, '-Regenerate')
        $LASTEXITCODE | Should -Be 0
        $a = Get-LedgerCells -Root $root -Ticket 'WI00030'
        ($a[0..14] -join '|') | Should -Be 'WI00030|bug|2026-10-03|branch|6.2|3|3|4|4|62||30|14713|f1/s0/d0|abc12345'
        ($a[15..17] -join '|') | Should -Be 'no|1.3|1'
        $b = Get-LedgerCells -Root $root -Ticket 'WI00031'
        ($b[0..14] -join '|') | Should -Be 'WI00031|spike|2026-10-04|investigate|2|1|3|3|4||||||abc12345'
        ($b[15..17] -join '|') | Should -Be '||'
        (Get-LedgerText -Root $root) | Should -Match '\| 0 \| 1\.3 \|'
    }
}

Describe 'Update-TicketLedger -SeedFromCloseouts' {
    It 'seeds from closeouts named with the profile ticketPrefix' {
        $root = Join-Path $TestDrive 'seed-root'
        $plans = Join-Path $root 'plans'
        New-Item -ItemType Directory -Path $plans -Force | Out-Null
        $closeout = @(
            '---'
            'ticket: TICKET-00042'
            'closed: 2026-10-05'
            'type: bug'
            '---'
            ''
            '# TICKET-00042 Closeout'
        ) -join "`n"
        [System.IO.File]::WriteAllText((Join-Path $plans 'TICKET-00042-closeout.md'), $closeout + "`n", (New-Object System.Text.UTF8Encoding $false))

        & $script:PwshHost -NonInteractive -NoProfile -File $script:LedgerScript -SeedFromCloseouts -Root $root
        $LASTEXITCODE | Should -Be 0

        $text = Get-Content -LiteralPath (Join-Path $plans 'ticket-ledger.md') -Raw -Encoding UTF8
        $text | Should -Match '(?m)^\|\s*TICKET-00042\s*\|\s*bug\s*\|\s*2026-10-05\s*\|'
    }
}

Describe 'Update-TicketLedger Outcome column' {
    BeforeAll { $script:Led = Join-Path $PSScriptRoot 'Update-TicketLedger.ps1' }

    It 'records a parked row with an Outcome and no scorecard, and a later close replaces it' {
        $root = Join-Path $TestDrive 'outcome'
        New-Item -ItemType Directory -Path (Join-Path $root 'plans') -Force | Out-Null
        & $script:Led -Ticket TICKET-00031 -Type bug -Mode branch -Hours 2.5 -Outcome more-info -Root $root *> $null
        $row = @(Get-Content (Join-Path $root 'plans/ticket-ledger.md') | Where-Object { $_ -match '^\|\s*TICKET-00031' })
        $row.Count | Should -Be 1
        $cells = @(($row[0].Trim() -replace '^\|', '' -replace '\|$', '') -split '\|' | ForEach-Object { $_.Trim() })
        $cells[18] | Should -Be 'more-info'
        $cells[6] | Should -BeNullOrEmpty
        & $script:Led -Ticket TICKET-00031 -Type bug -Mode branch -Hours 4 -Efficiency 4 -Contextualization 4 -CostTokens 3 -Root $root *> $null
        $row = @(Get-Content (Join-Path $root 'plans/ticket-ledger.md') | Where-Object { $_ -match '^\|\s*TICKET-00031' })
        $row.Count | Should -Be 1
        @(($row[0].Trim() -replace '^\|', '' -replace '\|$', '') -split '\|' | ForEach-Object { $_.Trim() })[18] | Should -BeNullOrEmpty
    }
}
