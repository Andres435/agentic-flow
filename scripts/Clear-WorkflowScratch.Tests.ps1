#Requires -Version 7
#Requires -Modules Pester
# Invoke-Pester ./scripts/Clear-WorkflowScratch.Tests.ps1 -Output Detailed

Set-StrictMode -Version Latest

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot 'Clear-WorkflowScratch.ps1'

    function New-Fake {
        param([string]$Name)
        $base = Join-Path $TestDrive $Name
        $root = Join-Path $base 'wf'
        $temp = Join-Path $base 'temp'
        foreach ($d in @('tmp', 'plans/evidence', 'evals/results')) {
            New-Item -ItemType Directory -Path (Join-Path $root $d) -Force | Out-Null
        }
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        return [pscustomobject]@{ Root = $root; Temp = $temp }
    }

    # A file (or a folder holding one file) whose newest write time is $Days days ago.
    function New-Aged {
        param([string]$Path, [double]$Days, [switch]$Folder)
        $when = (Get-Date).AddDays(-$Days)
        if ($Folder) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            $f = Join-Path $Path 'f.txt'
            [System.IO.File]::WriteAllText($f, 'x')
            (Get-Item -LiteralPath $f).LastWriteTime = $when
        }
        else {
            New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
            [System.IO.File]::WriteAllText($Path, 'x')
        }
        # -Force: a dotfile such as .last-sweep is hidden on Linux and Get-Item would not find it.
        (Get-Item -LiteralPath $Path -Force).LastWriteTime = $when
    }

    function New-Manifest {
        param($Fake, [string]$Ticket, [hashtable]$Fields)
        $json = $Fields | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText((Join-Path $Fake.Root "plans/$Ticket-manifest.json"), $json)
    }

    function Invoke-Sweep {
        param($Fake, [hashtable]$Extra = @{})
        $out = & $script:Script -Root $Fake.Root -TempRoot $Fake.Temp @Extra *>&1 | ForEach-Object { [string]$_ }
        return @($out)
    }

    function Get-UtcStamp([int]$DaysAgo) { (Get-Date).ToUniversalTime().AddDays(-$DaysAgo).ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
}

Describe 'Clear-WorkflowScratch tmp' {
    It 'removes an old unreferenced item and keeps a recent one' {
        $f = New-Fake 'tmp-age'
        New-Aged (Join-Path $f.Root 'tmp/old.trx') 20
        New-Aged (Join-Path $f.Root 'tmp/new.trx') 3
        New-Aged (Join-Path $f.Root 'tmp/oldfolder') 30 -Folder
        $out = Invoke-Sweep $f
        Test-Path -LiteralPath (Join-Path $f.Root 'tmp/old.trx') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $f.Root 'tmp/oldfolder') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $f.Root 'tmp/new.trx') | Should -BeTrue
        ($out -join "`n") | Should -Match 'tmp: removed 2 item\(s\), \d+(\.\d+)? MB'
    }

    It 'keeps an old file a manifest references, in every path spelling' -ForEach @(
        @{ ref = 'tmp/ref.trx' }
        @{ ref = './agentic-flow/tmp/ref.trx' }
        @{ ref = 'tmp\\ref.trx' }
        @{ ref = 'C:\\x\\agentic-flow\\tmp\\ref.trx' }
    ) {
        $f = New-Fake 'tmp-ref'
        New-Aged (Join-Path $f.Root 'tmp/ref.trx') 40
        New-Aged (Join-Path $f.Root 'tmp/other.trx') 40
        $json = '{"verify":{"repos":{"app":{"evidence":{"path":"' + $ref + '"}}}}}'
        [System.IO.File]::WriteAllText((Join-Path $f.Root 'plans/WI00001-manifest.json'), $json)
        Invoke-Sweep $f | Out-Null
        Test-Path -LiteralPath (Join-Path $f.Root 'tmp/ref.trx') | Should -BeTrue -Because $ref
        Test-Path -LiteralPath (Join-Path $f.Root 'tmp/other.trx') | Should -BeFalse
    }

    It 'keeps a folder that contains a referenced file' {
        $f = New-Fake 'tmp-ref-inside'
        New-Aged (Join-Path $f.Root 'tmp/keepdir') 40 -Folder
        [System.IO.File]::WriteAllText((Join-Path $f.Root 'plans/WI00001-manifest.json'), '{"p":"tmp/keepdir/f.txt"}')
        Invoke-Sweep $f | Out-Null
        Test-Path -LiteralPath (Join-Path $f.Root 'tmp/keepdir/f.txt') | Should -BeTrue
    }

    It 'never removes tmp/tickets itself or the marker, but ages tickets entries individually' {
        $f = New-Fake 'tmp-tickets'
        New-Aged (Join-Path $f.Root 'tmp/tickets/WI1-old.json') 30
        New-Aged (Join-Path $f.Root 'tmp/tickets/WI2-new.json') 0.2
        New-Aged (Join-Path $f.Root 'tmp/.last-sweep') 90
        Invoke-Sweep $f -Extra @{ Days = 1 } | Out-Null
        Test-Path -LiteralPath (Join-Path $f.Root 'tmp/tickets') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $f.Root 'tmp/tickets/WI1-old.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $f.Root 'tmp/tickets/WI2-new.json') | Should -BeTrue
    }
}

Describe 'Clear-WorkflowScratch evidence' {
    It 'removes a ticket closed 20 days ago, keeps 3 days, open, and reopened-after-close' {
        $f = New-Fake 'evidence'
        foreach ($t in 'WI00001', 'WI00002', 'WI00003', 'WI00004') { New-Aged (Join-Path $f.Root "plans/evidence/$t") 1 -Folder }
        New-Manifest $f 'WI00001' @{ completedAtUtc = (Get-UtcStamp 20) }
        New-Manifest $f 'WI00002' @{ completedAtUtc = (Get-UtcStamp 3) }
        New-Manifest $f 'WI00003' @{ workType = 'bug' }
        New-Manifest $f 'WI00004' @{ completedAtUtc = (Get-UtcStamp 30); reopenedAtUtc = (Get-UtcStamp 2) }
        $out = Invoke-Sweep $f
        Test-Path -LiteralPath (Join-Path $f.Root 'plans/evidence/WI00001') | Should -BeFalse
        foreach ($t in 'WI00002', 'WI00003', 'WI00004') {
            Test-Path -LiteralPath (Join-Path $f.Root "plans/evidence/$t") | Should -BeTrue -Because $t
        }
        ($out -join "`n") | Should -Match 'evidence: removed 1 ticket folder\(s\)'
    }

    It 'uses the reclose time when the ticket was reclosed' {
        $f = New-Fake 'evidence-reclosed'
        New-Aged (Join-Path $f.Root 'plans/evidence/WI00005') 1 -Folder
        New-Manifest $f 'WI00005' @{ completedAtUtc = (Get-UtcStamp 40); reopenedAtUtc = (Get-UtcStamp 10); reclosedAtUtc = (Get-UtcStamp 2) }
        Invoke-Sweep $f | Out-Null
        Test-Path -LiteralPath (Join-Path $f.Root 'plans/evidence/WI00005') | Should -BeTrue
    }

    It 'sweeps an app overlay evidence by the manifest of that app' {
        $f = New-Fake 'evidence-app'
        $appPlans = Join-Path $f.Root 'apps/demo/plans'
        New-Item -ItemType Directory -Path $appPlans -Force | Out-Null
        foreach ($t in 'WI00008', 'WI00009') { New-Aged (Join-Path $appPlans "evidence/$t") 1 -Folder }
        [System.IO.File]::WriteAllText((Join-Path $appPlans 'WI00008-manifest.json'), (@{ completedAtUtc = (Get-UtcStamp 20) } | ConvertTo-Json))
        [System.IO.File]::WriteAllText((Join-Path $appPlans 'WI00009-manifest.json'), (@{ completedAtUtc = (Get-UtcStamp 2) } | ConvertTo-Json))
        $out = Invoke-Sweep $f
        Test-Path -LiteralPath (Join-Path $appPlans 'evidence/WI00008') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $appPlans 'evidence/WI00009') | Should -BeTrue
        ($out -join "`n") | Should -Match 'evidence: removed 1 ticket folder\(s\)'
    }

    It 'goes by folder age when there is no manifest' {
        $f = New-Fake 'evidence-nomanifest'
        New-Aged (Join-Path $f.Root 'plans/evidence/WI00006') 30 -Folder
        New-Aged (Join-Path $f.Root 'plans/evidence/WI00007') 2 -Folder
        Invoke-Sweep $f | Out-Null
        Test-Path -LiteralPath (Join-Path $f.Root 'plans/evidence/WI00006') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $f.Root 'plans/evidence/WI00007') | Should -BeTrue
    }
}

Describe 'Clear-WorkflowScratch eval temp and results' {
    It 'removes old claude-eval-XXXXXX folders and keeps recent ones and other names' {
        $f = New-Fake 'evaltemp'
        New-Aged (Join-Path $f.Temp 'claude-eval-aB3xY9') 20 -Folder
        New-Aged (Join-Path $f.Temp 'claude-eval-Zz1234') 1 -Folder
        New-Aged (Join-Path $f.Temp 'claude-eval-toolongname') 30 -Folder
        New-Aged (Join-Path $f.Temp 'other-folder') 30 -Folder
        $out = Invoke-Sweep $f
        Test-Path -LiteralPath (Join-Path $f.Temp 'claude-eval-aB3xY9') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $f.Temp 'claude-eval-Zz1234') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $f.Temp 'claude-eval-toolongname') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $f.Temp 'other-folder') | Should -BeTrue
        ($out -join "`n") | Should -Match 'eval temp: removed 1 folder\(s\)'
    }

    It 'keeps the newest -KeepEvalRuns result folders by name' {
        $f = New-Fake 'evalres'
        $names = '2026-10-01T10-00-00-000Z', '2026-10-02T10-00-00-000Z', '2026-10-03T10-00-00-000Z', '2026-10-04T10-00-00-000Z'
        foreach ($n in $names) { New-Aged (Join-Path $f.Root "evals/results/$n") 1 -Folder }
        $out = Invoke-Sweep $f -Extra @{ KeepEvalRuns = 2 }
        $left = @(Get-ChildItem -LiteralPath (Join-Path $f.Root 'evals/results') -Directory | ForEach-Object Name | Sort-Object)
        $left | Should -Be @($names[2], $names[3])
        ($out -join "`n") | Should -Match 'eval results: removed 2 run\(s\)'
    }

    It 'guards correctly when TempRoot is an 8.3 short path' {
        $f = New-Fake 'short-temp'
        New-Aged (Join-Path $f.Temp 'claude-eval-Short1') 20 -Folder
        $short = $null
        try { $short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($f.Temp).ShortPath } catch { $short = $null }
        if (-not $short) { $short = $f.Temp }
        $out = & $script:Script -Root $f.Root -TempRoot $short *>&1 | ForEach-Object { [string]$_ }
        Test-Path -LiteralPath (Join-Path $f.Temp 'claude-eval-Short1') | Should -BeFalse
        ($out -join "`n") | Should -Not -Match 'outside'
    }
}

Describe 'Clear-WorkflowScratch safety and output' {
    It '-WhatIf removes nothing, reports, and writes no marker' {
        $f = New-Fake 'whatif'
        New-Aged (Join-Path $f.Root 'tmp/old.trx') 20
        New-Aged (Join-Path $f.Temp 'claude-eval-What12') 20 -Folder
        $out = Invoke-Sweep $f -Extra @{ WhatIf = $true }
        Test-Path -LiteralPath (Join-Path $f.Root 'tmp/old.trx') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $f.Temp 'claude-eval-What12') | Should -BeTrue
        ($out -join "`n") | Should -Match 'would remove'
        Test-Path -LiteralPath (Join-Path $f.Root 'tmp/.last-sweep') | Should -BeFalse
    }

    It 'skips a folder that contains a junction and reports it' {
        $f = New-Fake 'junction'
        $dir = Join-Path $f.Root 'tmp/withjunction'
        New-Aged $dir 30 -Folder
        $target = Join-Path $f.Root 'junction-target'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $target 'keep.txt'), 'keep')
        $made = $false
        $link = Join-Path $dir 'link'
        # A junction on Windows, a symlink elsewhere; either must carry the ReparsePoint attribute.
        $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
        try {
            New-Item -ItemType $linkType -Path $link -Target $target -ErrorAction Stop | Out-Null
            $made = [bool]((Get-Item -LiteralPath $link -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
        } catch { $made = $false }
        if (-not $made) { Set-ItResult -Skipped -Because 'a link could not be created on this platform'; return }
        (Get-Item -LiteralPath $dir).LastWriteTime = (Get-Date).AddDays(-30)
        $out = Invoke-Sweep $f
        Test-Path -LiteralPath (Join-Path $dir 'f.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $target 'keep.txt') | Should -BeTrue
        ($out -join "`n") | Should -Match 'skipped: tmp/withjunction contains a junction or symlink'
    }

    It '-Quiet prints nothing when there is nothing to do, and the removal line otherwise' {
        $f = New-Fake 'quiet'
        New-Aged (Join-Path $f.Root 'tmp/new.trx') 1
        @(Invoke-Sweep $f -Extra @{ Quiet = $true }).Count | Should -Be 0
        New-Aged (Join-Path $f.Root 'tmp/old.trx') 30
        $out = Invoke-Sweep $f -Extra @{ Quiet = $true }
        ($out -join "`n") | Should -Match 'tmp: removed 1 item'
        ($out -join "`n") | Should -Not -Match 'evidence:'
    }

    It 'writes the UTC date marker on a real run' {
        $f = New-Fake 'marker'
        Invoke-Sweep $f | Out-Null
        [System.IO.File]::ReadAllText((Join-Path $f.Root 'tmp/.last-sweep')).Trim() | Should -Be ([DateTime]::UtcNow.ToString('yyyy-MM-dd'))
    }

    # FileShare.None is enforced only on Windows; on Linux the lock is advisory and the file is deletable.
    It 'does not throw on a locked file, and leaves it in place' -Skip:(-not $IsWindows) {
        $f = New-Fake 'locked'
        $dir = Join-Path $f.Root 'tmp/lockeddir'
        New-Aged $dir 30 -Folder
        $file = Join-Path $dir 'f.txt'
        $fs = [System.IO.File]::Open($file, 'Open', 'ReadWrite', 'None')
        try {
            { Invoke-Sweep $f | Out-Null } | Should -Not -Throw
            Test-Path -LiteralPath $file | Should -BeTrue
        }
        finally { $fs.Dispose() }
    }

    It 'tolerates a root with none of the folders' {
        $base = Join-Path $TestDrive 'bare'
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        { & $script:Script -Root $base -TempRoot (Join-Path $base 'none') -Quiet | Out-Null } | Should -Not -Throw
    }
}
