#Requires -Modules Pester
<#
.SYNOPSIS
    Pester 5 tests for the manifest writers that replace per-ticket side files:
    Set-VerifyReceipt.ps1 (manifest.verify), Set-ReviewReady.ps1 -Findings
    (reviewReady.repos.<repo>.findings), and Set-TicketFeedback.ps1 (manifest.feedback).
#>

BeforeAll {
    $script:Verify = Join-Path $PSScriptRoot 'Set-VerifyReceipt.ps1'
    $script:Feedback = Join-Path $PSScriptRoot 'Set-TicketFeedback.ps1'
    function New-ManifestRoot([string]$Name) {
        $root = Join-Path $TestDrive $Name
        $plans = Join-Path $root 'plans'
        New-Item -ItemType Directory -Path $plans -Force | Out-Null
        '{"mode":"branch"}' | Set-Content -LiteralPath (Join-Path $plans 'WI00020-manifest.json') -Encoding UTF8
        return $root
    }
    function New-Evidence([string]$Name, [string]$Content = 'Passed! total 3') {
        $p = Join-Path $TestDrive $Name
        [System.IO.File]::WriteAllText($p, $Content)
        return $p
    }
    function New-Trx([string]$Name, [int]$Total, [int]$Passed, [int]$Failed) {
        $xml = '<?xml version="1.0" encoding="utf-8"?><TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><ResultSummary outcome="Completed"><Counters total="' + $Total + '" executed="' + $Total + '" passed="' + $Passed + '" failed="' + $Failed + '" error="0" /></ResultSummary></TestRun>'
        return New-Evidence $Name $xml
    }
    function Get-Manifest([string]$Root) {
        return (Get-Content -LiteralPath (Join-Path $Root 'plans/WI00020-manifest.json') -Raw | ConvertFrom-Json)
    }
}

Describe 'Set-VerifyReceipt' {
    It 'writes one entry per repo on the manifest and replaces a repo on a second call' {
        $root = New-ManifestRoot 'upsert'
        & $script:Verify -Ticket WI00020 -Repo app -Tests fail -Sonar ok -Failing 'SomeTest' -Evidence (New-Evidence 'u1.log') -Root $root
        & $script:Verify -Ticket WI00020 -Repo api -Tests pass -Sonar ok -Evidence (New-Evidence 'u2.log') -Root $root
        & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Evidence (New-Evidence 'u3.log') -Root $root
        $got = (Get-Manifest $root).verify.repos
        @($got.PSObject.Properties).Count | Should -Be 2
        $got.app.pass | Should -BeTrue
        $got.api.pass | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'plans/WI00020-verify.json') | Should -BeFalse
    }

    It 'records pass false for failing tests, a failing name, or a Sonar error' -ForEach @(
        @{ tests = 'fail'; sonar = 'ok'; failing = @() }
        @{ tests = 'pass'; sonar = 'error'; failing = @() }
        @{ tests = 'pass'; sonar = 'ok'; failing = @('Flaky') }
    ) {
        $root = New-ManifestRoot "fail-$tests-$sonar-$($failing.Count)"
        & $script:Verify -Ticket WI00020 -Repo app -Tests $tests -Sonar $sonar -Failing $failing -Evidence (New-Evidence 'f.log') -Root $root
        $entry = (Get-Manifest $root).verify.repos.app
        $entry.pass | Should -BeFalse
        $entry.pass | Should -BeOfType [bool]
    }

    It 'refuses not-run tests without a reason' {
        $root = New-ManifestRoot 'not-run'
        { & $script:Verify -Ticket WI00020 -Repo app -Tests not-run -Sonar not-run -Root $root } |
            Should -Throw '*-Reason*'
    }

    It 'passes not-run tests with a reason' {
        $root = New-ManifestRoot 'not-run-reason'
        & $script:Verify -Ticket WI00020 -Repo app -Tests not-run -Sonar not-run -Reason 'docs-only' -Root $root
        $entry = (Get-Manifest $root).verify.repos.app
        $entry.pass | Should -BeTrue
        $entry.reason | Should -Be 'docs-only'
    }

    It 'records the work it ran on: staged fingerprint, headSha, and mode' {
        $root = New-ManifestRoot 'work-identity'
        $repo = Join-Path $TestDrive 'receipt-repo'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        & git -C $repo init -q
        & git -C $repo config user.email 't@example.com'
        & git -C $repo config user.name 't'
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'one'
        & git -C $repo add a.txt
        & git -C $repo commit -q -m init
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'two'
        & git -C $repo add a.txt
        & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Evidence (New-Evidence 'w.log') -RepoPath $repo -Root $root
        $entry = (Get-Manifest $root).verify.repos.app
        $entry.mode | Should -Be 'staged'
        $entry.fingerprint | Should -Match '^[0-9a-f]{64}$'
        $entry.fpVersion | Should -Be 2
        $entry.headSha | Should -Match '^[0-9a-f]{40}$'
    }

    It 'records trx evidence with counts, hash, bytes and kind' {
        $root = New-ManifestRoot 'ev-trx'
        $trx = New-Trx 'ok.trx' 5 5 0
        & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Evidence $trx -Root $root
        $entry = (Get-Manifest $root).verify.repos.app
        $entry.evidenceVersion | Should -Be 1
        $entry.evidence.kind | Should -Be 'trx'
        $entry.evidence.sha256 | Should -Be (Get-FileHash -LiteralPath $trx -Algorithm SHA256).Hash.ToLowerInvariant()
        $entry.evidence.bytes | Should -Be (Get-Item -LiteralPath $trx).Length
        $entry.evidence.path | Should -Not -Match '\\'
        $entry.evidence.counts.total | Should -Be 5
        $entry.evidence.counts.passed | Should -Be 5
        $entry.evidence.counts.failed | Should -Be 0
    }

    It 'refuses pass or fail without -Evidence' -ForEach @('pass', 'fail') {
        $root = New-ManifestRoot "ev-none-$_"
        { & $script:Verify -Ticket WI00020 -Repo app -Tests $_ -Sonar ok -Root $root } | Should -Throw '*-Evidence*'
    }

    It 'refuses an evidence file that does not exist' {
        $root = New-ManifestRoot 'ev-missing'
        { & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Evidence (Join-Path $TestDrive 'nope.trx') -Root $root } |
            Should -Throw '*not found*'
    }

    It 'refuses a pass whose trx has failures or zero tests, but records a fail' {
        $root = New-ManifestRoot 'ev-bad-trx'
        { & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Evidence (New-Trx 'f.trx' 4 3 1) -Root $root } |
            Should -Throw '*failed*'
        { & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Evidence (New-Trx 'z.trx' 0 0 0) -Root $root } |
            Should -Throw '*zero*'
        (Get-Manifest $root).PSObject.Properties.Name | Should -Not -Contain 'verify'
        & $script:Verify -Ticket WI00020 -Repo app -Tests fail -Sonar ok -Evidence (New-Trx 'f2.trx' 4 3 1) -Root $root
        $entry = (Get-Manifest $root).verify.repos.app
        $entry.pass | Should -BeFalse
        $entry.evidence.counts.failed | Should -Be 1
    }

    It 'hashes a log evidence file only' {
        $root = New-ManifestRoot 'ev-log'
        & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Evidence (New-Evidence 'run.log') -Root $root
        $entry = (Get-Manifest $root).verify.repos.app
        $entry.evidence.kind | Should -Be 'log'
        $entry.evidence.sha256 | Should -Match '^[0-9a-f]{64}$'
        $entry.evidence.PSObject.Properties.Name | Should -Not -Contain 'counts'
    }

    It 'copies the evidence to plans/evidence/<Key>/<Repo>-verify<ext> and records the relative path' {
        $root = New-ManifestRoot 'ev-copy'
        $trx = New-Trx 'Scratch-Name.TRX' 5 5 0
        & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Evidence $trx -Root $root
        $copy = Join-Path $root 'plans/evidence/WI00020/app-verify.trx'
        Test-Path -LiteralPath $copy | Should -BeTrue
        Test-Path -LiteralPath $trx | Should -BeTrue
        $entry = (Get-Manifest $root).verify.repos.app
        $entry.evidence.path | Should -Be 'plans/evidence/WI00020/app-verify.trx'
        $entry.evidence.sha256 | Should -Be (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant()
        $entry.evidence.sha256 | Should -Be (Get-FileHash -LiteralPath $trx -Algorithm SHA256).Hash.ToLowerInvariant()
        $entry.evidence.counts.total | Should -Be 5
        $entry.evidenceVersion | Should -Be 1
    }

    It 'a second run with a different file overwrites the one copy and updates the sha' {
        $root = New-ManifestRoot 'ev-overwrite'
        $first = New-Trx 'full.trx' 5 5 0
        $second = New-Trx 'full2.trx' 9 9 0
        & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Evidence $first -Root $root
        $sha1 = (Get-Manifest $root).verify.repos.app.evidence.sha256
        & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Evidence $second -Root $root
        $files = @(Get-ChildItem -LiteralPath (Join-Path $root 'plans/evidence/WI00020') -File)
        $files.Count | Should -Be 1
        $files[0].Name | Should -Be 'app-verify.trx'
        $entry = (Get-Manifest $root).verify.repos.app
        $entry.evidence.sha256 | Should -Not -Be $sha1
        $entry.evidence.sha256 | Should -Be (Get-FileHash -LiteralPath $second -Algorithm SHA256).Hash.ToLowerInvariant()
        $entry.evidence.counts.total | Should -Be 9
    }

    It 'keeps one copy per repo and leaves the source untouched' {
        $root = New-ManifestRoot 'ev-two-repos'
        $a = New-Evidence 'a.log' 'alpha'
        & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Evidence $a -Root $root
        & $script:Verify -Ticket WI00020 -Repo api -Tests pass -Sonar ok -Evidence (New-Evidence 'b.LOG' 'beta') -Root $root
        $names = @(Get-ChildItem -LiteralPath (Join-Path $root 'plans/evidence/WI00020') -File | ForEach-Object Name | Sort-Object)
        $names | Should -Be @('api-verify.log', 'app-verify.log')
        [System.IO.File]::ReadAllText($a) | Should -Be 'alpha'
    }

    It 'does not error when the evidence already is the destination file' {
        $root = New-ManifestRoot 'ev-same'
        $dir = Join-Path $root 'plans/evidence/WI00020'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $dest = Join-Path $dir 'app-verify.log'
        [System.IO.File]::WriteAllText($dest, 'already here')
        & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Evidence $dest -Root $root
        [System.IO.File]::ReadAllText($dest) | Should -Be 'already here'
        (Get-Manifest $root).verify.repos.app.evidence.path | Should -Be 'plans/evidence/WI00020/app-verify.log'
    }

    It 'with an active app, copies the evidence beside the manifest of that app, not in the host plans/' {
        $root = Join-Path $TestDrive 'ev-app'
        $overlay = Join-Path $root 'apps/demo'
        New-Item -ItemType Directory -Path (Join-Path $overlay 'plans') -Force | Out-Null
        '{"mode":"branch"}' | Set-Content -LiteralPath (Join-Path $overlay 'plans/WI00020-manifest.json') -Encoding UTF8
        $prev = $env:AGENTIC_APP_OVERLAY
        $env:AGENTIC_APP_OVERLAY = $overlay
        try {
            & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Evidence (New-Evidence 'app-ev.log') -Root $root
        }
        finally {
            if ($null -eq $prev) { Remove-Item Env:AGENTIC_APP_OVERLAY -ErrorAction SilentlyContinue } else { $env:AGENTIC_APP_OVERLAY = $prev }
        }
        Test-Path -LiteralPath (Join-Path $overlay 'plans/evidence/WI00020/app-verify.log') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'plans/evidence') | Should -BeFalse
        $m = Get-Content -LiteralPath (Join-Path $overlay 'plans/WI00020-manifest.json') -Raw | ConvertFrom-Json
        $m.verify.repos.app.evidence.path | Should -Be 'plans/evidence/WI00020/app-verify.log'
    }

    It 'records no evidence for not-run' {
        $root = New-ManifestRoot 'ev-not-run'
        & $script:Verify -Ticket WI00020 -Repo app -Tests not-run -Sonar not-run -Reason 'docs-only' -Root $root
        $entry = (Get-Manifest $root).verify.repos.app
        $entry.evidence | Should -BeNullOrEmpty
        $entry.PSObject.Properties.Name | Should -Not -Contain 'evidenceVersion'
    }

    It 'refuses a ticket with no manifest' {
        $root = Join-Path $TestDrive 'no-manifest'
        New-Item -ItemType Directory -Path (Join-Path $root 'plans') -Force | Out-Null
        { & $script:Verify -Ticket WI00020 -Repo app -Tests pass -Sonar ok -Root $root } | Should -Throw '*Manifest not found*'
    }
}

Describe 'Set-ReviewReady -Findings' {
    It 'stores at most ten trimmed findings on the repo entry' {
        $root = New-ManifestRoot 'findings'
        $repo = Join-Path $TestDrive 'findings-repo'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        & git -C $repo init -q
        & git -C $repo config user.email 't@example.com'
        & git -C $repo config user.name 't'
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'one'
        & git -C $repo add a.txt
        $many = @(1..12 | ForEach-Object { " Major: finding $_ " }) | ConvertTo-Json -Compress
        $paths = @{ app = $repo } | ConvertTo-Json -Compress
        & (Join-Path $PSScriptRoot 'Set-ReviewReady.ps1') -Ticket WI00020 -Mode staged -Verdicts '{"app":"Ready with fixes"}' `
            -Findings "{`"app`":$many}" -RepoPaths $paths -Root $root
        $entry = (Get-Manifest $root).reviewReady.repos.app
        @($entry.findings).Count | Should -Be 10
        $entry.findings[0] | Should -Be 'Major: finding 1'
        Get-ChildItem -LiteralPath $repo -Recurse -Force -File | ForEach-Object { $_.IsReadOnly = $false }
    }

    It 'refuses a verdict its findings contradict, and accepts one they allow' {
        $root = New-ManifestRoot 'verdict-rules'
        $repo = Join-Path $TestDrive 'verdict-repo'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        & git -C $repo init -q
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'one'
        & git -C $repo add a.txt
        $stamp = Join-Path $PSScriptRoot 'Set-ReviewReady.ps1'
        $paths = @{ app = $repo } | ConvertTo-Json -Compress
        $major = '{"app":["Major: null check missing"]}'
        $blocker = '{"app":["**Blocker** SQL built from user input"]}'

        { & $stamp -Ticket WI00020 -Mode staged -Verdicts '{"app":"Ready"}' -Findings $major -RepoPaths $paths -Root $root } |
            Should -Throw '*Major finding(s) mean the verdict is Ready with fixes or Not ready*'
        { & $stamp -Ticket WI00020 -Mode staged -Verdicts '{"app":"Ready with fixes"}' -Findings $blocker -RepoPaths $paths -Root $root } |
            Should -Throw '*Blocker finding(s) mean the verdict is Not ready*'
        (Get-Manifest $root).PSObject.Properties.Name | Should -Not -Contain 'reviewReady'

        & $stamp -Ticket WI00020 -Mode staged -Verdicts '{"app":"Ready with fixes"}' -Findings $major -RepoPaths $paths -Root $root
        (Get-Manifest $root).reviewReady.repos.app.verdict | Should -Be 'Ready with fixes'
        Get-ChildItem -LiteralPath $repo -Recurse -Force -File | ForEach-Object { $_.IsReadOnly = $false }
    }
}

Describe 'Set-TicketFeedback' {
    It 'writes feedback from the pipeline and stamps fetchedAtUtc' {
        $root = New-ManifestRoot 'feedback'
        $json = '{ "prs": [ { "repo": "app", "id": 7, "status": "Active" } ], "items": [ { "kind": "thread", "repo": "app", "pr": 7, "ref": "101", "ask": "Rename the helper.", "triage": "fix-now" } ] }'
        $json | & $script:Feedback -Ticket WI00020 -Root $root
        $fb = (Get-Manifest $root).feedback
        $fb.items[0].triage | Should -Be 'fix-now'
        $fb.fetchedAtUtc | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $root 'plans/WI00020-feedback.md') | Should -BeFalse
    }

    It 'takes -Json through the script with nothing piped in' {
        $root = New-ManifestRoot 'feedback-param'
        $json = '{ "prs": [], "items": [ { "kind": "thread", "ref": "1", "ask": "Rename it.", "triage": "fix-now" } ] }'
        & $script:Feedback -Ticket WI00020 -Json $json -Root $root
        (Get-Manifest $root).feedback.items[0].ask | Should -Be 'Rename it.'
    }

    It 'takes piped JSON through the script' {
        $root = New-ManifestRoot 'feedback-pipe'
        $json = '{ "prs": [], "items": [ { "kind": "thread", "ref": "2", "ask": "Add a test.", "triage": "fix-now" } ] }'
        $json | & $script:Feedback -Ticket WI00020 -Root $root
        (Get-Manifest $root).feedback.items[0].ask | Should -Be 'Add a test.'
    }

    It 'refuses an item with an unknown triage bucket' {
        $root = New-ManifestRoot 'feedback-bad'
        $json = '{ "prs": [], "items": [ { "kind": "thread", "ref": "1", "ask": "x", "triage": "later" } ] }'
        { & $script:Feedback -Ticket WI00020 -Json $json -Root $root } | Should -Throw '*triage*'
    }

    It 'refuses feedback without an items array' {
        $root = New-ManifestRoot 'feedback-noitems'
        { & $script:Feedback -Ticket WI00020 -Json '{ "prs": [] }' -Root $root } | Should -Throw "*'items'*"
    }
}

AfterAll {
    Get-ChildItem -LiteralPath $TestDrive -Recurse -Force -File | ForEach-Object { $_.IsReadOnly = $false }
}
