#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for the Work Plan content checks in Assert-TicketArtifacts.ps1
    (-Phase start, -CheckDigest block: heading, numbered steps, difficulty tags,
    and the architect requirement on [high] steps).

.DESCRIPTION
    Pester 5 syntax (GitHub Actions installs 5.x). Run with:
    Invoke-Pester ./scripts/ticket/Assert-TicketArtifacts.Tests.ps1 -Output Detailed

    Each test builds a minimal ticket root under $TestDrive (plans/WI00009-manifest.json
    + plans/WI00009-feature-plan.md) and shells out to the real script, the same pattern
    Resolve-TicketRoot.Tests.ps1 uses for its fixture-based Describe blocks.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot 'Assert-TicketArtifacts.ps1'
    if (-not (Test-Path -LiteralPath $script:ScriptPath)) {
        throw "Missing Assert-TicketArtifacts.ps1 at $script:ScriptPath - cannot run tests"
    }

    function Get-PowerShell7Path {
        $cmd = Get-Command 'pwsh' -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { return $cmd.Source }
        throw "PowerShell 7 (pwsh) is required. See MACHINE-SETUP.md."
    }
    $script:PwshHost = Get-PowerShell7Path
    $script:Ticket = 'WI00009'
    $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    # Writes plans/WI00009-manifest.json + plans/WI00009-feature-plan.md under $Root
    # and returns the paths. Every plan body already gets '## Plan Digest' and
    # '## Engineering Decisions' baked in by the caller (spec: "Every plan fixture
    # must also include ## Plan Digest and ## Engineering Decisions so the earlier
    # checks pass") -- callers pass only the Work Plan section (and anything after).
    function New-FixtureRoot {
        param(
            [Parameter(Mandatory)] [string]$Root,
            [Parameter(Mandatory)] [string]$EngineeringDecisions,
            [Parameter(Mandatory)] [string]$WorkPlanSection
        )
        $plansDir = Join-Path $Root 'plans'
        New-Item -ItemType Directory -Path $plansDir -Force | Out-Null

        $manifest = [ordered]@{
            ticket       = $script:Ticket
            mode         = 'branch'
            workType     = 'feature'
            startedAtUtc = '2026-09-01T10:00:00Z'
        }
        $manifestPath = Join-Path $plansDir "$script:Ticket-manifest.json"
        [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), $script:Utf8NoBom)

        $planBody = @"
# $script:Ticket Feature Plan

## Plan Digest

Test fixture for Assert-TicketArtifacts.Tests.ps1.

## Engineering Decisions

$EngineeringDecisions

$WorkPlanSection
"@
        $planPath = Join-Path $plansDir "$script:Ticket-feature-plan.md"
        [System.IO.File]::WriteAllText($planPath, $planBody, $script:Utf8NoBom)

        return @{ Root = $Root; ManifestPath = $manifestPath; PlanPath = $planPath }
    }

    function Invoke-Assert {
        param(
            [Parameter(Mandatory)] [string]$Root,
            [ValidateSet('start', 'implement', 'prepush', 'close')] [string]$Phase = 'start'
        )
        $out = & $script:PwshHost -NonInteractive -NoProfile -File $script:ScriptPath `
            -Ticket $script:Ticket -Phase $Phase -Root $Root 2>&1
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output   = ($out -join "`n")
        }
    }
}

Describe 'Assert-TicketArtifacts -Phase start: Work Plan content checks' {

    It 'fails a bug plan whose first step is not RED, and passes RED or no-test with a reason' -ForEach @(
        @{ Step = '1. [med] Change the null check in LoanService.Save'; Pass = $false }
        @{ Step = '1. [low] Add a failing regression test for the null payee'; Pass = $true }
        @{ Step = '1. [high] no-test: the legacy page has no test project; change the gate'; Pass = $true }
        @{ Step = '1. [low] no-test: n/a'; Pass = $false }
    ) {
        $fixture = New-FixtureRoot -Root (Join-Path $TestDrive ('red-' + [guid]::NewGuid().ToString('N').Substring(0, 6))) `
            -EngineeringDecisions '- architect skipped: single-function fix' `
            -WorkPlanSection "## Work Plan`n`n$Step`n2. [low] Run the focused tests"
        $manifest = Get-Content -LiteralPath $fixture.ManifestPath -Raw | ConvertFrom-Json
        $manifest.workType = 'bug'
        [System.IO.File]::WriteAllText($fixture.ManifestPath, ($manifest | ConvertTo-Json -Depth 6), $script:Utf8NoBom)
        $result = Invoke-Assert -Root $fixture.Root -Phase 'start'
        if ($Pass) {
            $result.Output | Should -Not -Match 'must be RED'
        } else {
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match "first Work Plan step must be RED"
        }
    }

    It 'passes: plain/bold/backtick/whole-bold tag styles together, indented sub-lists ignored, lowercase "Work plan" heading accepted' {
        $fixture = New-FixtureRoot -Root $TestDrive `
            -EngineeringDecisions 'None -- fixture, no scope or contract calls to make.' `
            -WorkPlanSection @'
## Work plan

1. [low] Fixture step one
2. **[med]** Fixture step two
3. `[low]` Fixture step three
4. **[med] Fixture step four**
   - indented note without a tag
   - another indented note
'@
        $result = Invoke-Assert -Root $fixture.Root -Phase 'start'
        $result.ExitCode | Should -Be 0
    }

    It 'passes: steps grouped under ### subheadings inside the Work Plan' {
        $fixture = New-FixtureRoot -Root $TestDrive `
            -EngineeringDecisions 'None -- fixture, no scope or contract calls to make.' `
            -WorkPlanSection @'
## Work Plan

### Foundational
1. **[low]** Fixture step one

### Verification
2. **[low]** Fixture step two
'@
        $result = Invoke-Assert -Root $fixture.Root -Phase 'start'
        $result.ExitCode | Should -Be 0
    }

    It 'passes: a sibling ## section after the Work Plan is not read as steps' {
        $fixture = New-FixtureRoot -Root $TestDrive `
            -EngineeringDecisions 'None -- fixture, no scope or contract calls to make.' `
            -WorkPlanSection @'
## Work Plan

1. [low] Fixture step one

## Testing Plan

1. Untagged numbered line that belongs to another section
'@
        $result = Invoke-Assert -Root $fixture.Root -Phase 'start'
        $result.ExitCode | Should -Be 0
    }

    It 'fails: an untagged step, naming the step number' {
        $fixture = New-FixtureRoot -Root $TestDrive `
            -EngineeringDecisions 'None -- fixture, no scope or contract calls to make.' `
            -WorkPlanSection @'
## Work Plan

1. [low] Fixture step one
2. Fixture step two without a tag
'@
        $result = Invoke-Assert -Root $fixture.Root -Phase 'start'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'Work Plan step\(s\) 2 missing a \[low\]\|\[med\]\|\[high\] tag'
    }

    It 'fails: missing Work Plan heading' {
        $fixture = New-FixtureRoot -Root $TestDrive `
            -EngineeringDecisions 'None -- fixture, no scope or contract calls to make.' `
            -WorkPlanSection @'
## Approach

1. [low] Fixture step one
'@
        $result = Invoke-Assert -Root $fixture.Root -Phase 'start'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "missing 'Work Plan' heading"
    }

    It 'fails: a [high] step with Engineering Decisions that never mentions architect' {
        $fixture = New-FixtureRoot -Root $TestDrive `
            -EngineeringDecisions 'None -- fixture, no scope or contract calls to make.' `
            -WorkPlanSection @'
## Work Plan

1. **[high]** Fixture step one
'@
        $result = Invoke-Assert -Root $fixture.Root -Phase 'start'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'has a \[high\] step but Engineering Decisions records no architect result'
    }

    It 'passes: a [high] step with an explicit "architect skipped: <reason>" in Engineering Decisions' {
        $fixture = New-FixtureRoot -Root $TestDrive `
            -EngineeringDecisions '- architect skipped: single-function fix' `
            -WorkPlanSection @'
## Work Plan

1. **[high]** Fixture step one
'@
        $result = Invoke-Assert -Root $fixture.Root -Phase 'start'
        $result.ExitCode | Should -Be 0
    }

    It 'fails when Engineering Decisions omits a priorFindings id' {
        $fixture = New-FixtureRoot -Root (Join-Path $TestDrive 'start-lesson-miss') `
            -EngineeringDecisions 'None -- fixture, no scope or contract calls to make.' `
            -WorkPlanSection @'
## Work Plan

1. [low] Fixture step one
'@
        $manifest = Get-Content -LiteralPath $fixture.ManifestPath -Raw | ConvertFrom-Json
        $manifest | Add-Member -NotePropertyName priorFindings -NotePropertyValue @([pscustomobject]@{ ticket = 'WI11111'; lesson = 'do not default the flag' })
        [System.IO.File]::WriteAllText($fixture.ManifestPath, ($manifest | ConvertTo-Json -Depth 6), $script:Utf8NoBom)
        $result = Invoke-Assert -Root $fixture.Root -Phase 'start'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'WI11111'
    }

    It 'passes when Engineering Decisions cites each priorFindings id' {
        $fixture = New-FixtureRoot -Root (Join-Path $TestDrive 'start-lesson-hit') `
            -EngineeringDecisions 'lesson unchanged: WI11111 -- this ticket does not touch that flag.' `
            -WorkPlanSection @'
## Work Plan

1. [low] Fixture step one
'@
        $manifest = Get-Content -LiteralPath $fixture.ManifestPath -Raw | ConvertFrom-Json
        $manifest | Add-Member -NotePropertyName priorFindings -NotePropertyValue @([pscustomobject]@{ ticket = 'WI11111'; lesson = 'do not default the flag' })
        [System.IO.File]::WriteAllText($fixture.ManifestPath, ($manifest | ConvertTo-Json -Depth 6), $script:Utf8NoBom)
        $result = Invoke-Assert -Root $fixture.Root -Phase 'start'
        $result.ExitCode | Should -Be 0
    }
}

Describe 'Assert-TicketArtifacts -Phase implement: not retroactive' {
    It 'passes on a plan with an untagged Work Plan step -- implement does not re-check plan content' {
        # -Phase implement runs Test-Manifest + Test-PlanFile (existence only, no
        # -CheckDigest), so the same untagged plan that fails -Phase start above must
        # still pass here: a plan approved before the tag requirement existed (or, in
        # this repo, before the Work Plan checks existed at all) must not retroactively
        # fail implement.
        $fixture = New-FixtureRoot -Root $TestDrive `
            -EngineeringDecisions 'None -- fixture, no scope or contract calls to make.' `
            -WorkPlanSection @'
## Work Plan

1. [low] Fixture step one
2. Fixture step two without a tag
'@
        $result = Invoke-Assert -Root $fixture.Root -Phase 'implement'
        $result.ExitCode | Should -Be 0
    }
}

Describe 'Assert-TicketArtifacts -Phase close: context percents' {
    BeforeAll {
    function New-CloseRoot {
        param(
            [Parameter(Mandatory)][string]$Root,
            [Parameter(Mandatory)][string]$WorkType,
            [hashtable]$Ctx,
            [bool]$ReviewSkipped = $false
        )
        $plans = Join-Path $Root 'plans'
        New-Item -ItemType Directory -Path $plans -Force | Out-Null
        $manifest = [ordered]@{
            ticket         = 'WI00009'
            mode           = 'branch'
            workType       = $WorkType
            startedAtUtc   = '2026-09-01T10:00:00Z'
            completedAtUtc = '2026-09-02T10:00:00Z'
        }
        if ($ReviewSkipped) { $manifest.reviewSkipped = $true }
        if ($Ctx) { $manifest.ctxPct = $Ctx }
        if ($WorkType -ne 'spike') {
            $manifest.verify = @{ repos = @{ app = @{ pass = $true; tests = 'pass'; sonar = 'ok' } } }
        }
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText((Join-Path $plans 'WI00009-manifest.json'), ($manifest | ConvertTo-Json -Depth 6), $utf8)
        $ledger = @(
            '# Ticket ledger'
            ''
            '| Ticket | Type |'
            '|---|---|'
            '| WI00009 | bug |'
        ) -join "`n"
        [System.IO.File]::WriteAllText((Join-Path $plans 'ticket-ledger.md'), $ledger + "`n", $utf8)
    }

    # Adds top-level fields to the WI00009 manifest under $Root.
    function Add-ManifestFields([string]$Root, [hashtable]$Fields) {
        $manifestPath = Join-Path $Root 'plans/WI00009-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        foreach ($k in $Fields.Keys) { $manifest | Add-Member -NotePropertyName $k -NotePropertyValue $Fields[$k] -Force }
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8) + "`n", $utf8)
    }

    # Replaces manifest.verify with the given JSON object.
    function Set-VerifyJson([string]$Root, [string]$Json) {
        Add-ManifestFields $Root @{ verify = ($Json | ConvertFrom-Json) }
    }

    # One affected repo 'app' with no local path, so the stamp is checked as JSON only.
    function New-StampedCloseRoot([string]$Root, [string]$Verdict = 'Ready') {
        New-CloseRoot -Root $Root -WorkType 'bug' -Ctx @{ start = 40; review = 50; close = 60 }
        $entry = [pscustomobject]@{ verdict = $Verdict; mode = 'staged'; fingerprint = ('ab' * 32); fpVersion = 2 }
        Add-ManifestFields $Root @{
            affectedRepos = @([pscustomobject]@{ repo = 'app'; local = $true })
            reviewReady   = [pscustomobject]@{ mode = 'staged'; repos = [pscustomobject]@{ app = $entry } }
        }
    }
    }

    It 'passes when ctxPct.start was not measured (blank is honest)' {
        $root = Join-Path $TestDrive 'close-no-start'
        New-CloseRoot -Root $root -WorkType 'bug' -Ctx @{ close = 10; review = 10 }
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 0
    }

    It 'fails when a recorded ctxPct is not 0-100' {
        $root = Join-Path $TestDrive 'close-bad-start'
        New-CloseRoot -Root $root -WorkType 'bug' -Ctx @{ start = 140; close = 10; review = 10 }
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'ctxPct.start'
    }

    It 'passes when start, review, and close are 0-100' {
        $root = Join-Path $TestDrive 'close-ok'
        New-CloseRoot -Root $root -WorkType 'bug' -Ctx @{ start = 40; review = 50; close = 60 }
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 0
    }

    It 'passes a spike without ctxPct.review' {
        $root = Join-Path $TestDrive 'close-spike'
        New-CloseRoot -Root $root -WorkType 'spike' -Ctx @{ start = 20; close = 30 }
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 0
    }

    It 'passes a bug close without optional stackSmoke' {
        $root = Join-Path $TestDrive 'close-no-smoke'
        New-CloseRoot -Root $root -WorkType 'bug' -Ctx @{ start = 40; review = 50; close = 60 }
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Not -Match 'stackSmoke'
    }

    It 'passes a bug close when stackSmoke is present' {
        $root = Join-Path $TestDrive 'close-with-smoke'
        New-CloseRoot -Root $root -WorkType 'bug' -Ctx @{ start = 40; review = 50; close = 60 }
        $manifestPath = Join-Path $root 'plans/WI00009-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest | Add-Member -NotePropertyName stackSmoke -NotePropertyValue ([pscustomobject]@{ status = 'passed'; notes = 'fixture' })
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6) + "`n", $utf8)
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 0
    }

    It 'fails a frontend close without a current passed stackSmoke and passes once stamped' {
        $root = Join-Path $TestDrive 'close-frontend'
        New-StampedCloseRoot $root
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $profileJson = @{ repos = @(@{ name = 'app'; path = '.'; layers = @('frontend') }) } | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText((Join-Path $root 'profile.json'), $profileJson + "`n", $utf8)
        $fail = Invoke-Assert -Root $root -Phase 'close'
        $fail.ExitCode | Should -Be 1
        $fail.Output | Should -Match 'stackSmoke'
        Add-ManifestFields $root @{ stackSmoke = [pscustomobject]@{ status = 'passed'; notes = 'user confirmed' } }
        $ok = Invoke-Assert -Root $root -Phase 'close'
        $ok.ExitCode | Should -Be 0
    }

    It 'fails close when the verify receipt was taken before a later fix, and passes after re-verify' {
        $root = Join-Path $TestDrive 'close-stale-receipt'
        New-CloseRoot -Root $root -WorkType 'bug' -Ctx @{ start = 40; review = 50; close = 60 }
        $repo = Join-Path $TestDrive 'close-stale-receipt-repo'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        & git -C $repo init -q
        & git -C $repo config user.email 't@example.com'
        & git -C $repo config user.name 't'
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'one'
        & git -C $repo add a.txt
        & git -C $repo commit -q -m init
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'first try'
        & git -C $repo add a.txt
        Add-ManifestFields $root @{ affectedRepos = @([pscustomobject]@{ repo = 'app'; local = $true; path = $repo }) }
        $ev = Join-Path $TestDrive 'stale-receipt-evidence.log'
        Set-Content -LiteralPath $ev -Value 'Passed! total 3'
        & (Join-Path $PSScriptRoot 'Set-VerifyReceipt.ps1') -Ticket WI00009 -Repo app -Tests pass -Sonar ok -Evidence $ev -RepoPath $repo -Root $root
        # Review finds a Major; the fix is staged and re-reviewed, but verify is not re-run.
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'fixed'
        & git -C $repo add a.txt
        $paths = @{ app = $repo } | ConvertTo-Json -Compress
        & (Join-Path $PSScriptRoot 'Set-ReviewReady.ps1') -Ticket WI00009 -Mode staged -Verdicts '{"app":"Ready"}' -RepoPaths $paths -Root $root
        $stale = Invoke-Assert -Root $root -Phase 'close'
        $stale.ExitCode | Should -Be 1
        $stale.Output | Should -Match 'tests ran on older work'
        & (Join-Path $PSScriptRoot 'Set-VerifyReceipt.ps1') -Ticket WI00009 -Repo app -Tests pass -Sonar ok -Evidence $ev -RepoPath $repo -Root $root
        $fresh = Invoke-Assert -Root $root -Phase 'close'
        $fresh.ExitCode | Should -Be 0
        Get-ChildItem -LiteralPath $repo -Recurse -Force -File | ForEach-Object { $_.IsReadOnly = $false }
    }

    It 'checks verify evidence: missing, malformed, changed file fail; intact and legacy pass' {
        $sha = 'ab' * 32
        $evFile = Join-Path $TestDrive 'close-evidence.log'
        [System.IO.File]::WriteAllText($evFile, 'Passed! total 3')
        $realSha = (Get-FileHash -LiteralPath $evFile -Algorithm SHA256).Hash.ToLowerInvariant()
        $cases = @(
            @{ name = 'missing'; fail = 'evidence missing'; json = '{"repos":{"app":{"pass":true,"tests":"pass","sonar":"ok","evidenceVersion":1}}}' }
            @{ name = 'malformed'; fail = 'evidence missing'; json = '{"repos":{"app":{"pass":true,"tests":"pass","sonar":"ok","evidenceVersion":1,"evidence":{"path":"x.log","sha256":"nothex","bytes":1,"kind":"log"}}}}' }
            @{ name = 'changed'; fail = 'evidence file changed'; json = ('{"repos":{"app":{"pass":true,"tests":"pass","sonar":"ok","evidenceVersion":1,"evidence":{"path":"' + ($evFile -replace '\\', '/') + '","sha256":"' + $sha + '","bytes":1,"kind":"log"}}}}') }
            @{ name = 'intact'; fail = $null; json = ('{"repos":{"app":{"pass":true,"tests":"pass","sonar":"ok","evidenceVersion":1,"evidence":{"path":"' + ($evFile -replace '\\', '/') + '","sha256":"' + $realSha + '","bytes":15,"kind":"log"}}}}') }
            @{ name = 'gone'; fail = $null; json = ('{"repos":{"app":{"pass":true,"tests":"pass","sonar":"ok","evidenceVersion":1,"evidence":{"path":"' + ($TestDrive -replace '\\', '/') + '/deleted.trx","sha256":"' + $sha + '","bytes":1,"kind":"trx"}}}}') }
            @{ name = 'legacy'; fail = $null; json = '{"repos":{"app":{"pass":true,"tests":"pass","sonar":"ok"}}}' }
        )
        foreach ($c in $cases) {
            $root = Join-Path $TestDrive "close-evidence-$($c.name)"
            New-StampedCloseRoot $root
            Set-VerifyJson $root $c.json
            $result = Invoke-Assert -Root $root -Phase 'close'
            if ($c.fail) {
                $result.ExitCode | Should -Be 1 -Because $c.name
                $result.Output | Should -Match $c.fail -Because $c.name
            } else {
                $result.ExitCode | Should -Be 0 -Because $c.name
            }
        }
    }

    It 'resolves plans/evidence/ receipts against the workflow root: passes intact, fails altered, legacy tmp path still passes' {
        $src = Join-Path $TestDrive 'evidence-src.log'
        [System.IO.File]::WriteAllText($src, 'Passed! total 3')
        $root = Join-Path $TestDrive 'close-evidence-folder'
        New-StampedCloseRoot $root
        & (Join-Path $PSScriptRoot 'Set-VerifyReceipt.ps1') -Ticket WI00009 -Repo app -Tests pass -Sonar ok -Evidence $src -Root $root
        $copy = Join-Path $root 'plans/evidence/WI00009/app-verify.log'
        Test-Path -LiteralPath $copy | Should -BeTrue
        (Invoke-Assert -Root $root -Phase 'close').ExitCode | Should -Be 0
        [System.IO.File]::WriteAllText($copy, 'Passed! total 4 (edited)')
        $altered = Invoke-Assert -Root $root -Phase 'close'
        $altered.ExitCode | Should -Be 1
        $altered.Output | Should -Match 'evidence file changed'

        # A legacy receipt that points into tmp/ keeps resolving as before.
        $legacyFile = Join-Path $TestDrive 'legacy-tmp.log'
        [System.IO.File]::WriteAllText($legacyFile, 'Passed! total 3')
        $legacySha = (Get-FileHash -LiteralPath $legacyFile -Algorithm SHA256).Hash.ToLowerInvariant()
        $legacyRoot = Join-Path $TestDrive 'close-evidence-legacy-tmp'
        New-StampedCloseRoot $legacyRoot
        Set-VerifyJson $legacyRoot ('{"repos":{"app":{"pass":true,"tests":"pass","sonar":"ok","evidenceVersion":1,"evidence":{"path":"' + ($legacyFile -replace '\\', '/') + '","sha256":"' + $legacySha + '","bytes":15,"kind":"log"}}}}')
        (Invoke-Assert -Root $legacyRoot -Phase 'close').ExitCode | Should -Be 0
        [System.IO.File]::WriteAllText($legacyFile, 'edited')
        (Invoke-Assert -Root $legacyRoot -Phase 'close').ExitCode | Should -Be 1
    }

    It 'fails a bug close with no verify results on the manifest' {
        $root = Join-Path $TestDrive 'close-no-verify'
        New-CloseRoot -Root $root -WorkType 'bug' -Ctx @{ start = 40; review = 50; close = 60 }
        $manifestPath = Join-Path $root 'plans/WI00009-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.PSObject.Properties.Remove('verify')
        [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'verify'
    }

    It 'fails when an affected repo has no review fingerprint' {
        $root = Join-Path $TestDrive 'close-no-fp'
        New-CloseRoot -Root $root -WorkType 'bug' -Ctx @{ start = 40; review = 50; close = 60 }
        $manifestPath = Join-Path $root 'plans/WI00009-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest | Add-Member -NotePropertyName affectedRepos -NotePropertyValue @([pscustomobject]@{ repo = 'app'; local = $true })
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6) + "`n", $utf8)
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'no review stamp'
    }

    It 'fails when the repo path exists and the fingerprint does not match the commit' {
        $root = Join-Path $TestDrive 'close-mismatch'
        $repo = Join-Path $root 'app'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        & git -C $repo init -q
        & git -C $repo config user.email 't@example.com'
        & git -C $repo config user.name 't'
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'one'
        & git -C $repo add a.txt
        & git -C $repo commit -q -m init
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'two'
        & git -C $repo add a.txt
        & git -C $repo commit -q -m change
        New-CloseRoot -Root $root -WorkType 'bug' -Ctx @{ start = 40; review = 50; close = 60 }
        $manifestPath = Join-Path $root 'plans/WI00009-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $stamp = [pscustomobject]@{
            mode  = 'staged'
            repos = [pscustomobject]@{
                app = [pscustomobject]@{
                    verdict     = 'Ready'
                    fingerprint = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
                }
            }
        }
        $manifest | Add-Member -NotePropertyName affectedRepos -NotePropertyValue @([pscustomobject]@{ repo = 'app'; local = $true; path = $repo })
        $manifest | Add-Member -NotePropertyName reviewReady -NotePropertyValue $stamp
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8) + "`n", $utf8)
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'does not match'
    }

    It 'passes a stamped repo with a passing verify entry' {
        $root = Join-Path $TestDrive 'close-stamped'
        New-StampedCloseRoot $root
        (Invoke-Assert -Root $root -Phase 'close').ExitCode | Should -Be 0
    }

    It 'fails a stamp whose verdict is <verdict>' -ForEach @(
        @{ verdict = 'Not ready' }
        @{ verdict = '' }
    ) {
        $root = Join-Path $TestDrive "close-verdict-$($verdict.Length)"
        New-StampedCloseRoot $root -Verdict $verdict
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'needs Ready'
    }

    It 'fails a verify entry whose pass is the string <value>' -ForEach @(
        @{ value = 'false' }
        @{ value = 'true' }
    ) {
        $root = Join-Path $TestDrive "close-pass-string-$value"
        New-StampedCloseRoot $root
        Set-VerifyJson $root "{ `"repos`": { `"app`": { `"pass`": `"$value`" } } }"
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'boolean true'
    }

    It 'fails when verify has no entry for an affected repo' {
        $root = Join-Path $TestDrive 'close-receipt-missing-repo'
        New-StampedCloseRoot $root
        Set-VerifyJson $root '{ "repos": { "other": { "pass": true } } }'
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'verify.repos.app -- missing'
    }

    It 'passes a verify entry whose tests were not run, with a reason' {
        $root = Join-Path $TestDrive 'close-receipt-not-run'
        New-StampedCloseRoot $root
        Set-VerifyJson $root '{ "repos": { "app": { "pass": true, "tests": "not-run", "reason": "docs-only" } } }'
        (Invoke-Assert -Root $root -Phase 'close').ExitCode | Should -Be 0
    }

    It 'fails close while the review stamp records a Major finding' {
        $root = Join-Path $TestDrive 'close-open-major'
        New-StampedCloseRoot $root 'Ready with fixes'
        Set-VerifyJson $root '{ "repos": { "app": { "pass": true, "tests": "not-run", "reason": "docs-only" } } }'
        (Invoke-Assert -Root $root -Phase 'close').ExitCode | Should -Be 0

        $manifestPath = Join-Path $root 'plans/WI00009-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.reviewReady.repos.app | Add-Member -NotePropertyName findings -NotePropertyValue @('Major: null check missing in LoanService.Save', 'Minor: rename x')
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8) + "`n", $utf8)
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '0 Blocker and 1 Major finding\(s\) open'
        $result.Output | Should -Match 're-run /review-changes'
    }

    It 'prepush checks the work, not the artifacts written at close' {
        $root = Join-Path $TestDrive 'prepush'
        New-StampedCloseRoot $root
        Add-ManifestFields $root @{ verify = $null; completedAtUtc = $null }
        Remove-Item -LiteralPath (Join-Path $root 'plans/ticket-ledger.md')
        $fail = Invoke-Assert -Root $root -Phase 'prepush'
        $fail.ExitCode | Should -Be 1
        $fail.Output | Should -Match 'no verify results'
        $fail.Output | Should -Not -Match 'ticket-ledger|completedAtUtc'

        Set-VerifyJson $root '{ "repos": { "app": { "pass": true, "tests": "pass" } } }'
        (Invoke-Assert -Root $root -Phase 'prepush').ExitCode | Should -Be 0
    }

    It 'fails a spike close when the work item is a Bug' {
        $root = Join-Path $TestDrive 'spike-bug'
        New-CloseRoot -Root $root -WorkType 'spike' -Ctx @{ start = 40; close = 60 }
        (Invoke-Assert -Root $root -Phase 'close').ExitCode | Should -Be 0
        Add-ManifestFields $root @{ ticket = [pscustomobject]@{ title = 't'; adoType = 'Bug' } }
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'workType is spike but the work item is a Bug'
    }

    It 'fails a local:false repo that is checked out after all' {
        $root = Join-Path $TestDrive 'local-false'
        New-StampedCloseRoot $root
        $there = Join-Path $root 'other-repo'
        New-Item -ItemType Directory -Path $there -Force | Out-Null
        Add-ManifestFields $root @{ affectedRepos = @(
            [pscustomobject]@{ repo = 'app'; local = $true }
            [pscustomobject]@{ repo = 'other'; local = $false; path = $there }
        ) }
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'affectedRepos.other is local:false but it is checked out'
    }

    Context 'with a git repo branched from main' {
        BeforeAll {
            # A repo with a main base branch and one ticket-branch commit that changes $Files.
            function New-WorkRepo([string]$Path, [string[]]$Files) {
                New-Item -ItemType Directory -Path $Path -Force | Out-Null
                & git -C $Path init -q -b main
                & git -C $Path config user.email 't@example.com'
                & git -C $Path config user.name 't'
                Set-Content -LiteralPath (Join-Path $Path 'base.txt') -Value 'base'
                & git -C $Path add -A
                & git -C $Path commit -q -m base
                & git -C $Path switch -q -c ticket
                foreach ($f in $Files) {
                    $p = Join-Path $Path $f
                    New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force | Out-Null
                    Set-Content -LiteralPath $p -Value 'change'
                }
                & git -C $Path add -A
                & git -C $Path commit -q -m ticket
            }
        }

        It 'accepts tests not-run only for a docs-only change' {
            $root = Join-Path $TestDrive 'not-run-code'
            New-StampedCloseRoot $root
            $repo = Join-Path $root 'app'
            New-WorkRepo $repo @('docs/notes.md', 'src/Loan.cs')
            Add-ManifestFields $root @{ affectedRepos = @([pscustomobject]@{ repo = 'app'; local = $true; path = $repo }) }
            Set-VerifyJson $root '{ "repos": { "app": { "pass": true, "tests": "not-run", "reason": "docs-only" } } }'
            $result = Invoke-Assert -Root $root -Phase 'prepush'
            $result.Output | Should -Match 'tests not run \(docs-only\) but the change touches code \(src/Loan.cs\)'

            $docs = Join-Path $TestDrive 'not-run-docs'
            New-StampedCloseRoot $docs
            $docsRepo = Join-Path $docs 'app'
            New-WorkRepo $docsRepo @('docs/notes.md', 'README.md')
            Add-ManifestFields $docs @{ affectedRepos = @([pscustomobject]@{ repo = 'app'; local = $true; path = $docsRepo }) }
            Set-VerifyJson $docs '{ "repos": { "app": { "pass": true, "tests": "not-run", "reason": "docs-only" } } }'
            (Invoke-Assert -Root $docs -Phase 'prepush').Output | Should -Not -Match 'touches code'
        }

        It 'requires the frontend Drive only when UI files changed (profile uiGlobs)' {
            $utf8 = New-Object System.Text.UTF8Encoding($false)
            $profileJson = @{ repos = @(@{ name = 'app'; path = '.'; layers = @('backend', 'frontend') }); uiGlobs = @('*.tsx', '*.js') } | ConvertTo-Json -Depth 5

            $stamp = Join-Path $PSScriptRoot 'Set-ReviewReady.ps1'

            $backend = Join-Path $TestDrive 'ui-backend-only'
            New-CloseRoot -Root $backend -WorkType 'bug' -Ctx @{ start = 40; review = 50; close = 60 }
            [System.IO.File]::WriteAllText((Join-Path $backend 'profile.json'), $profileJson, $utf8)
            $backendRepo = Join-Path $backend 'app'
            New-WorkRepo $backendRepo @('server/Loan.cs')
            Add-ManifestFields $backend @{ affectedRepos = @([pscustomobject]@{ repo = 'app'; local = $true; path = $backendRepo }) }
            & $stamp -Ticket $script:Ticket -Mode pre-merge -Verdicts '{"app":"Ready"}' -RepoPaths (@{ app = $backendRepo } | ConvertTo-Json -Compress) -Root $backend
            $r1 = Invoke-Assert -Root $backend -Phase 'prepush'
            $r1.Output | Should -Not -Match 'need a current passed stackSmoke'
            $r1.ExitCode | Should -Be 0

            $ui = Join-Path $TestDrive 'ui-page'
            New-CloseRoot -Root $ui -WorkType 'bug' -Ctx @{ start = 40; review = 50; close = 60 }
            [System.IO.File]::WriteAllText((Join-Path $ui 'profile.json'), $profileJson, $utf8)
            $uiRepo = Join-Path $ui 'app'
            New-WorkRepo $uiRepo @('server/Loan.cs', 'web/pages/loan.js')
            Add-ManifestFields $ui @{ affectedRepos = @([pscustomobject]@{ repo = 'app'; local = $true; path = $uiRepo }) }
            & $stamp -Ticket $script:Ticket -Mode pre-merge -Verdicts '{"app":"Ready"}' -RepoPaths (@{ app = $uiRepo } | ConvertTo-Json -Compress) -Root $ui
            $r2 = Invoke-Assert -Root $ui -Phase 'prepush'
            $r2.ExitCode | Should -Be 1
            $r2.Output | Should -Match 'need a current passed stackSmoke'
        }
    }

    It 'end to end: stamp, commit, base merge, receipt passes; a later commit fails' {
        $root = Join-Path $TestDrive 'close-e2e'
        $repo = Join-Path $root 'app'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        & git -C $repo init -q -b main
        & git -C $repo config user.email 't@example.com'
        & git -C $repo config user.name 't'
        & git -C $repo config commit.gpgsign false
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'one'
        & git -C $repo add a.txt
        & git -C $repo commit -q -m init
        & git -C $repo branch dev
        New-CloseRoot -Root $root -WorkType 'bug' -Ctx @{ start = 40; review = 50; close = 60 }
        Add-ManifestFields $root @{ affectedRepos = @([pscustomobject]@{ repo = 'app'; local = $true; path = $repo }) }

        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'two'
        & git -C $repo add a.txt
        $paths = @{ app = $repo } | ConvertTo-Json -Compress
        & (Join-Path $PSScriptRoot 'Set-ReviewReady.ps1') -Ticket WI00009 -Mode staged -Verdicts '{"app":"Ready"}' -RepoPaths $paths -Root $root
        & git -C $repo commit -q -m change
        & git -C $repo checkout -q dev
        Set-Content -LiteralPath (Join-Path $repo 'dev.txt') -Value 'dev'
        & git -C $repo add dev.txt
        & git -C $repo commit -q -m dev
        & git -C $repo checkout -q main
        & git -C $repo merge -q --no-ff dev -m 'merge dev' 2>$null | Out-Null
        $ev = Join-Path $TestDrive 'merge-evidence.log'
        Set-Content -LiteralPath $ev -Value 'Passed! total 3'
        & (Join-Path $PSScriptRoot 'Set-VerifyReceipt.ps1') -Ticket WI00009 -Repo app -Tests pass -Sonar not-run -Evidence $ev -RepoPath $repo -Root $root

        (Invoke-Assert -Root $root -Phase 'close').ExitCode | Should -Be 0

        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'three'
        & git -C $repo add a.txt
        & git -C $repo commit -q -m 'unreviewed'
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 're-review'
    }

    It 'passes a legacy stamp (no headSha) that matches the last commit' {
        $root = Join-Path $TestDrive 'close-match'
        $repo = Join-Path $root 'app'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        & git -C $repo init -q
        & git -C $repo config user.email 't@example.com'
        & git -C $repo config user.name 't'
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'one'
        & git -C $repo add a.txt
        & git -C $repo commit -q -m init
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'two'
        & git -C $repo add a.txt
        & git -C $repo commit -q -m change
        . (Join-Path $PSScriptRoot 'lib/ManifestFields.ps1')
        $fp = Get-WorkDiffFingerprint -RepoPath $repo -Version 1
        New-CloseRoot -Root $root -WorkType 'bug' -Ctx @{ start = 40; review = 50; close = 60 }
        $manifestPath = Join-Path $root 'plans/WI00009-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $stamp = [pscustomobject]@{
            mode  = 'staged'
            repos = [pscustomobject]@{
                app = [pscustomobject]@{
                    verdict     = 'Ready'
                    fingerprint = $fp
                }
            }
        }
        $manifest | Add-Member -NotePropertyName affectedRepos -NotePropertyValue @([pscustomobject]@{ repo = 'app'; local = $true; path = $repo })
        $manifest | Add-Member -NotePropertyName reviewReady -NotePropertyValue $stamp
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8) + "`n", $utf8)
        $result = Invoke-Assert -Root $root -Phase 'close'
        $result.ExitCode | Should -Be 0
    }
}
