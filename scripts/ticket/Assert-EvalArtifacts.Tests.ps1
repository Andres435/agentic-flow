#Requires -Version 7
#Requires -Modules Pester
<#
.SYNOPSIS
    Pester 5 tests for Assert-EvalArtifacts.ps1 (start gate over kept eval workspaces).
#>

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot 'Assert-EvalArtifacts.ps1'
    $script:Fixture = Join-Path $PSScriptRoot 'fixtures/plans'
    . (Join-Path $PSScriptRoot 'lib/TicketPrefix.ps1')
    $script:Prefix = Get-TicketPrefix
    $script:Ticket = "$($script:Prefix)00001"

    # Copies a fixture file into $Plans, renaming WI00001 to $Ticket in its name and text.
    function Copy-Fixture([string]$Name, [string]$Plans, [string]$Ticket = $script:Ticket) {
        $text = (Get-Content -LiteralPath (Join-Path $script:Fixture $Name) -Raw) -replace 'WI00001', $Ticket
        Set-Content -LiteralPath (Join-Path $Plans ($Name -replace 'WI00001', $Ticket)) -Value $text -NoNewline
    }

    # Builds <tmp>/out/trace.jsonl and <tmp>/home/cwd/plans like a kept eval workspace, and a
    # results JSON pointing at it. -Good copies the fixture ticket as $Ticket, otherwise plans/ is empty.
    function New-EvalResults([string]$Name, [switch]$Good, [string]$Ticket = $script:Ticket) {
        $tmp = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path (Join-Path $tmp 'out') -Force | Out-Null
        $plans = Join-Path $tmp 'home/cwd/plans'
        New-Item -ItemType Directory -Path $plans -Force | Out-Null
        if ($Good) {
            Copy-Fixture 'WI00001-manifest.json' $plans $Ticket
            Copy-Fixture 'WI00001-feature-plan.md' $plans $Ticket
        }
        $trace = Join-Path $tmp 'out/trace.jsonl'
        Set-Content -LiteralPath $trace -Value '{}'
        $json = Join-Path $TestDrive "$Name.json"
        @{ cases = @(@{ name = 'start-x'; arms = @{ with = @(@{ tracePath = $trace }) } }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $json
        return $json
    }
}

Describe 'Assert-EvalArtifacts' {
    It 'passes a run whose plans/ satisfy the start gate' {
        $json = New-EvalResults 'good' -Good
        $out = & $script:Script -Results $json | Out-String
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match ('\[PASS\] eval-gate: start-x run 1 ' + [regex]::Escape($script:Ticket))
    }

    It 'fails a run that wrote no manifest' {
        $json = New-EvalResults 'empty'
        $out = & $script:Script -Results $json | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match ('wrote no ' + [regex]::Escape("$($script:Prefix)*-manifest.json"))
    }

    It 'gates only manifests with the profile prefix unless -Prefix names another' {
        $json = New-EvalResults 'other-prefix' -Good -Ticket 'OTHER-00001'
        & $script:Script -Results $json | Out-Null
        $LASTEXITCODE | Should -Be 1
        $out = & $script:Script -Results $json -Prefix 'OTHER-' | Out-String
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '\[PASS\] eval-gate: start-x run 1 OTHER-00001'
    }

    It 'fails a run whose plan lacks a required heading' {
        $json = New-EvalResults 'bad-plan' -Good
        $plan = Join-Path $TestDrive "bad-plan/home/cwd/plans/$($script:Ticket)-feature-plan.md"
        Set-Content -LiteralPath $plan -Value '# nothing useful here'
        $out = & $script:Script -Results $json | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match ('\[FAIL\] eval-gate: start-x run 1 ' + [regex]::Escape($script:Ticket))
    }

    It 'grades a close-named case with the close gate' {
        $json = New-EvalResults 'close-good' -Good
        Copy-Fixture 'ticket-ledger.md' (Join-Path $TestDrive 'close-good/home/cwd/plans')
        $raw = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
        $raw.cases[0].name = 'close-bug'
        $raw | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $json
        $out = & $script:Script -Results $json | Out-String
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match ('\[PASS\] eval-gate: close-bug run 1 ' + [regex]::Escape($script:Ticket))
    }

    Context 'expect.json' {
        BeforeAll {
            function Set-Expect([string]$Outcome) {
                $dir = Join-Path $TestDrive 'evals/start-x'
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                @{ outcome = $Outcome } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'expect.json')
                return (Join-Path $TestDrive 'evals')
            }
        }

        It 'passes a refuse case that wrote no ticket files' {
            $evals = Set-Expect 'refuse'
            $json = New-EvalResults 'refused'
            $out = & $script:Script -Results $json -EvalDir $evals | Out-String
            $LASTEXITCODE | Should -Be 0
            $out | Should -Match 'refused and wrote no ticket files'
        }

        It 'fails a refuse case that wrote a manifest and plan' {
            $evals = Set-Expect 'refuse'
            $json = New-EvalResults 'not-refused' -Good
            $out = & $script:Script -Results $json -EvalDir $evals | Out-String
            $LASTEXITCODE | Should -Be 1
            $t = [regex]::Escape($script:Ticket)
            $out | Should -Match "should have refused but wrote $t-feature-plan\.md, $t-manifest\.json"
        }

        It 'fails a refuse case whose ticket files use another prefix' {
            $evals = Set-Expect 'refuse'
            $json = New-EvalResults 'not-refused-other' -Good -Ticket 'OTHER-00001'
            $out = & $script:Script -Results $json -EvalDir $evals | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'should have refused but wrote OTHER-00001'
        }

        It 'skips the gate for a graders case' {
            $evals = Set-Expect 'graders'
            $json = New-EvalResults 'graders-only'
            $out = & $script:Script -Results $json -EvalDir $evals | Out-String
            $LASTEXITCODE | Should -Be 0
            $out | Should -Match 'graders decide'
        }

        It 'fails on an unknown outcome' {
            $evals = Set-Expect 'maybe'
            $json = New-EvalResults 'unknown' -Good
            $out = & $script:Script -Results $json -EvalDir $evals | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match "unknown outcome 'maybe'"
        }
    }

    It 'fails when a run has no tracePath' {
        $json = Join-Path $TestDrive 'notrace.json'
        @{ cases = @(@{ name = 'start-x'; arms = @{ with = @(@{ error = 'x' }) } }) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $json
        $out = & $script:Script -Results $json | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'no tracePath'
    }
}
