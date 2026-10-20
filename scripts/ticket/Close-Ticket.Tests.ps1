#Requires -Version 7
#Requires -Modules Pester
<#
.SYNOPSIS
    Pester 5 tests for Close-Ticket.ps1: one call stamps, scores, writes the ledger row and
    passes the close gate; a re-close updates in place; any failure stops before later writes.

.DESCRIPTION
    Each test builds a ticket root under $TestDrive (plans/TICKET-9-manifest.json with a verify
    receipt and a review stamp, the same shape Assert-TicketArtifacts.Tests.ps1 closes with)
    and runs the real script against it with -Root.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot 'Close-Ticket.ps1'
    $script:PwshHost = (Get-Command pwsh).Source
    $script:Utf8 = New-Object System.Text.UTF8Encoding($false)
    $env:TMO_CTX_USAGE_FILE = Join-Path $TestDrive 'no-ctx-usage.json'
    # The close-time sweep also looks in TEMP; point it at an empty folder so a test never touches the real one.
    $script:RealTemp = $env:TEMP
    $env:TEMP = Join-Path $TestDrive 'empty-temp'
    New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null

    function New-ClosableRoot {
        param([string]$Name, [switch]$NoVerify)
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
        }
        if (-not $NoVerify) {
            $manifest.verify = @{ repos = @{ app = @{ pass = $true; tests = 'pass'; sonar = 'ok' } } }
        }
        [System.IO.File]::WriteAllText((Join-Path $plans 'TICKET-9-manifest.json'), ($manifest | ConvertTo-Json -Depth 8), $script:Utf8)
        return $root
    }

    function Invoke-Close {
        param([string]$Root, [int]$E = 4, [string[]]$Extra = @())
        $out = & $script:PwshHost -NoProfile -NonInteractive -File $script:ScriptPath -Ticket TICKET-9 `
            -Efficiency $E -Contextualization 4 -CostTokens 3 -Root $Root @Extra 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($out -join "`n") }
    }

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

Describe 'Close-Ticket' {
    It 'closes a closable ticket: timestamp, ledger row, close gate' {
        $root = New-ClosableRoot 'ok'
        $before = (Get-Manifest $root).startedAtUtc
        $r = Invoke-Close -Root $root
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match '\[PASS\] TICKET-9 closed'
        $m = Get-Manifest $root
        $m.completedAtUtc | Should -Not -BeNullOrEmpty
        $m.startedAtUtc | Should -Be $before
        @(Get-LedgerRows $root).Count | Should -Be 1
        (Get-LedgerCells @(Get-LedgerRows $root)[0])[1] | Should -Be 'bug'
    }

    It 'a second close after a reopen writes reclosedAtUtc and updates the row in place' {
        $root = New-ClosableRoot 'reclose'
        (Invoke-Close -Root $root -E 4).ExitCode | Should -Be 0
        $first = (Get-Manifest $root).completedAtUtc
        $path = Join-Path $root 'plans/TICKET-9-manifest.json'
        $m = Get-Manifest $root
        $m | Add-Member -NotePropertyName reopenedAtUtc -NotePropertyValue ([DateTime]::UtcNow.AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')) -Force
        [System.IO.File]::WriteAllText($path, ($m | ConvertTo-Json -Depth 8), $script:Utf8)
        $r = Invoke-Close -Root $root -E 2
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match 'reclosedAtUtc ='
        $after = Get-Manifest $root
        $after.reclosedAtUtc | Should -Not -BeNullOrEmpty
        $after.completedAtUtc | Should -Be $first
        $rows = @(Get-LedgerRows $root)
        $rows.Count | Should -Be 1
        (Get-LedgerCells $rows[0])[6] | Should -Be '2'
    }

    It 'stops at step 1 when the verify receipt is missing, before any write' {
        $root = New-ClosableRoot 'no-verify' -NoVerify
        $r = Invoke-Close -Root $root
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match '\[FAIL\] close step 1 \(resolve\)'
        (Get-Manifest $root).PSObject.Properties.Name | Should -Not -Contain 'completedAtUtc'
        Test-Path -LiteralPath (Join-Path $root 'plans/ticket-ledger.md') | Should -BeFalse
    }

    It 'rejects a score outside 1-5 before writing anything' {
        $root = New-ClosableRoot 'bad-score'
        $r = Invoke-Close -Root $root -E 9
        $r.ExitCode | Should -Not -Be 0
        (Get-Manifest $root).PSObject.Properties.Name | Should -Not -Contain 'completedAtUtc'
        Test-Path -LiteralPath (Join-Path $root 'plans/ticket-ledger.md') | Should -BeFalse
    }

    It 'fails step 1 when there is no manifest' {
        $root = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path (Join-Path $root 'plans') -Force | Out-Null
        $r = Invoke-Close -Root $root
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match '\[FAIL\] close step 1 \(resolve\): no manifest'
    }

    It 'runs the scratch sweep after a passing close (and not as a numbered step)' {
        $root = New-ClosableRoot 'sweep-ok'
        $old = Join-Path $root 'tmp/old-scratch.txt'
        New-Item -ItemType Directory -Path (Split-Path $old -Parent) -Force | Out-Null
        [System.IO.File]::WriteAllText($old, 'x')
        (Get-Item -LiteralPath $old).LastWriteTime = (Get-Date).AddDays(-30)
        $r = Invoke-Close -Root $root
        $r.ExitCode | Should -Be 0
        Test-Path -LiteralPath $old | Should -BeFalse
        $r.Output | Should -Not -Match 'close step 7'
        $r.Output | Should -Match '\[OK\] close step 5'
    }

    It 'does not run the sweep when the close fails' {
        $root = New-ClosableRoot 'sweep-fail' -NoVerify
        $old = Join-Path $root 'tmp/old-scratch.txt'
        New-Item -ItemType Directory -Path (Split-Path $old -Parent) -Force | Out-Null
        [System.IO.File]::WriteAllText($old, 'x')
        (Get-Item -LiteralPath $old).LastWriteTime = (Get-Date).AddDays(-30)
        $r = Invoke-Close -Root $root
        $r.ExitCode | Should -Be 1
        Test-Path -LiteralPath $old | Should -BeTrue
    }

    It 'a throwing sweep does not change the close result' {
        $root = New-ClosableRoot 'sweep-throws'
        $boom = Join-Path $PSScriptRoot 'fixtures/Throwing-Sweep.ps1'
        $r = Invoke-Close -Root $root -Extra @('-SweepScript', $boom)
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match '\[PASS] TICKET-9 closed'
        $r.Output | Should -Not -Match 'sweep exploded'
    }

    It '-WhatIf lists the steps and writes nothing' {
        $root = New-ClosableRoot 'whatif'
        $r = Invoke-Close -Root $root -Extra @('-WhatIf')
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match 'close step 5 \(ledger\)'
        (Get-Manifest $root).PSObject.Properties.Name | Should -Not -Contain 'completedAtUtc'
        Test-Path -LiteralPath (Join-Path $root 'plans/ticket-ledger.md') | Should -BeFalse
    }
}
