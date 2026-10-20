#Requires -Version 7
#Requires -Modules Pester
<#
.SYNOPSIS
    The eval graders and the start gate are not lenient: a good plan passes both, and each
    known defect is rejected by at least one of them. Free (no model calls), so it runs in CI.

.DESCRIPTION
    For each start-* gate case in evals/, builds a good workspace from the gate fixture (with
    the case's ticket id, work type and repo), then one broken copy per defect. Case ticket ids
    must use profile.ticketPrefix (lib/TicketPrefix.ps1). A grader file is
    read from its frontmatter (type, pattern, flags, match, target.path); regex graders run
    with .NET regex, which agrees with the harness on these simple patterns.
#>

BeforeDiscovery {
    $evalRoot = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'evals'
    $script:Cases = @(Get-ChildItem -LiteralPath $evalRoot -Directory -Filter 'start-*' |
        Where-Object { Test-Path (Join-Path $_.FullName 'graders') } |
        Where-Object { -not (Test-Path (Join-Path $_.FullName 'expect.json')) -or
            ((Get-Content (Join-Path $_.FullName 'expect.json') -Raw | ConvertFrom-Json).outcome -eq 'gate') } |
        ForEach-Object { @{ Name = $_.Name; Dir = $_.FullName } })
    $script:Defects = @('no-plan-digest', 'tbd-step', 'untagged-steps', 'wrong-work-type', 'no-engineering-decisions')
}

BeforeAll {
    $script:Gate = Join-Path $PSScriptRoot 'Assert-TicketArtifacts.ps1'
    $script:Fixture = Join-Path $PSScriptRoot 'fixtures/plans'
    . (Join-Path $PSScriptRoot 'lib/TicketPrefix.ps1')
    $script:Prefix = Get-TicketPrefix

    function Read-Grader([string]$File) {
        $text = Get-Content -LiteralPath $File -Raw
        $front = [regex]::Match($text, '(?s)^---\r?\n(.*?)\r?\n---').Groups[1].Value
        $get = {
            param($key)
            $m = [regex]::Match($front, "(?m)^\s*${key}:\s*(.+?)\s*$")
            if (-not $m.Success) { return $null }
            $v = $m.Groups[1].Value
            if ($v -match "^'(.*)'$") { return $Matches[1] -replace "''", "'" }
            if ($v -match '^"(.*)"$') { return $Matches[1] }
            return $v
        }
        [pscustomobject]@{
            Name    = [IO.Path]::GetFileNameWithoutExtension($File)
            Type    = & $get 'type'
            Pattern = & $get 'pattern'
            Flags   = & $get 'flags'
            Match   = & $get 'match'
            Path    = & $get 'path'
        }
    }

    # True when the grader passes on the workspace at $Root.
    function Test-Grader($Grader, [string]$Root) {
        if ($Grader.Type -eq 'file_exists') {
            $leaf = Split-Path $Grader.Path -Leaf
            return [bool](Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $leaf -ErrorAction SilentlyContinue)
        }
        $file = Join-Path $Root $Grader.Path
        $text = if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file -Raw } else { $null }
        if ($null -eq $text) { return $false }
        $opts = [Text.RegularExpressions.RegexOptions]::None
        if ($Grader.Flags -match 'm') { $opts = $opts -bor [Text.RegularExpressions.RegexOptions]::Multiline }
        if ($Grader.Flags -match 'i') { $opts = $opts -bor [Text.RegularExpressions.RegexOptions]::IgnoreCase }
        $hit = [regex]::IsMatch($text, $Grader.Pattern, $opts)
        if ($Grader.Match -eq 'not_contains') { return -not $hit }
        return $hit
    }

    # Ticket id, work type and repo the case's graders expect, read from the graders themselves.
    function Get-CaseShape([string]$Dir) {
        $all = Get-ChildItem (Join-Path $Dir 'graders') -Filter *.md | ForEach-Object { Read-Grader $_.FullName }
        $manifest = ($all | Where-Object { $_.Path -match '[A-Za-z]+-?\d+-manifest\.json' } | Select-Object -First 1).Path
        $ticket = [regex]::Match($manifest, '[A-Za-z]+-?\d+(?=-manifest\.json)').Value
        # The last quoted word in '"workType"\s*:\s*"bug"' is the value.
        $lastQuoted = { param($p) @([regex]::Matches($p, '"(\w+)"'))[-1].Groups[1].Value }
        $type = & $lastQuoted ($all | Where-Object Name -eq 'manifest-worktype').Pattern
        $repo = & $lastQuoted ($all | Where-Object Name -eq 'manifest-repo').Pattern
        [pscustomobject]@{ Ticket = $ticket; Type = $type; Repo = $repo; Graders = $all }
    }

    function New-Workspace($Shape, [string]$Name, [string]$Defect) {
        $root = Join-Path $TestDrive $Name
        $plans = Join-Path $root 'plans'
        New-Item -ItemType Directory -Path $plans -Force | Out-Null

        $m = Get-Content (Join-Path $script:Fixture 'WI00001-manifest.json') -Raw | ConvertFrom-Json
        $m.ticket = $Shape.Ticket
        $m.workType = if ($Defect -eq 'wrong-work-type') { 'refactor' } else { $Shape.Type }
        if ($Shape.Type -eq 'spike') { $m.mode = 'investigate' }
        $m.affectedRepos = @(@{ repo = $Shape.Repo; local = $true })
        foreach ($p in 'completedAtUtc', 'verify', 'reviewReady') { $m.PSObject.Properties.Remove($p) }
        $m | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $plans "$($Shape.Ticket)-manifest.json")

        $plan = (Get-Content (Join-Path $script:Fixture 'WI00001-feature-plan.md') -Raw) -replace 'WI00001', $Shape.Ticket -replace 'feature', $Shape.Type
        # The start gate requires a bug plan's first step to be RED (bug-fix.md section 5).
        if ($Shape.Type -eq 'bug') { $plan = $plan -replace 'Fixture step one', 'RED: write the failing test' }
        switch ($Defect) {
            'no-plan-digest'           { $plan = $plan -replace '(?m)^## Plan Digest\r?\n', '' }
            'tbd-step'                 { $plan = $plan -replace 'Fixture step two', 'TBD' }
            'untagged-steps'           { $plan = $plan -replace '\*{0,2}\[(low|med|high)\]\*{0,2}\s*', '' }
            'no-engineering-decisions' { $plan = $plan -replace '(?s)## Engineering Decisions.*?(?=## Context)', '' }
        }
        $planType = if ($Defect -eq 'wrong-work-type') { 'refactor' } else { $Shape.Type }
        Set-Content (Join-Path $plans "$($Shape.Ticket)-$planType-plan.md") $plan -NoNewline
        return $root
    }

    function Test-Gate($Shape, [string]$Root) {
        & $script:Gate -Ticket $Shape.Ticket -Phase start -Root $Root *> $null
        return $LASTEXITCODE -eq 0
    }
}

Describe 'Eval case <Name>' -ForEach $script:Cases {
    BeforeAll {
        $script:Shape = Get-CaseShape $Dir
    }

    # The sample cases use the template's prefix; a project that changes profile.ticketPrefix renames them.
    It 'reads its ticket, work type and repo from its graders' {
        $script:Shape.Ticket | Should -Match ('^' + [regex]::Escape($script:Prefix) + '\d+$') -Because 'case ticket ids use profile.ticketPrefix'
        $script:Shape.Type | Should -BeIn 'bug', 'feature', 'spike', 'refactor'
        $script:Shape.Repo | Should -Not -BeNullOrEmpty
    }

    It 'a good workspace passes every grader and the start gate' {
        $root = New-Workspace $script:Shape "$Name-good" ''
        foreach ($g in $script:Shape.Graders) {
            Test-Grader $g $root | Should -BeTrue -Because "grader $($g.Name) should accept a good plan"
        }
        Test-Gate $script:Shape $root | Should -BeTrue
    }

    It 'rejects the <_> defect by a grader or the gate' -ForEach $script:Defects {
        $root = New-Workspace $script:Shape "$Name-$_" $_
        $failedGraders = @($script:Shape.Graders | Where-Object { -not (Test-Grader $_ $root) })
        $gatePass = Test-Gate $script:Shape $root
        ($failedGraders.Count -gt 0 -or -not $gatePass) | Should -BeTrue -Because "defect '$_' must not pass both graders and gate"
    }
}

# The harness compiles grader patterns as JavaScript RegExp, which rejects .NET inline flags such
# as (?m) or (?i): such a grader throws in a paid run instead of grading. Compile every pattern
# here with node, for free, with its declared flags.
Describe 'Eval grader patterns compile as JavaScript' {
    It 'every regex grader in evals/ compiles with its flags' {
        $evalRoot = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'evals'
        $patterns = [System.Collections.Generic.List[object]]::new()
        foreach ($file in Get-ChildItem -LiteralPath $evalRoot -Recurse -File -Include '*.md', 'case.yaml' |
                Where-Object { $_.FullName -notmatch '[\/]workspace[\/]' -and $_.Name -ne 'README.md' }) {
            $lines = @(Get-Content -LiteralPath $file.FullName)
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $m = [regex]::Match($lines[$i], "^\s*pattern:\s*'(.*)'\s*$")
                if (-not $m.Success) { continue }
                $flags = ''
                for ($j = $i + 1; $j -lt [Math]::Min($i + 6, $lines.Count); $j++) {
                    if ($lines[$j] -match '^\s*-\s' -or $lines[$j] -match '^---') { break }
                    $f = [regex]::Match($lines[$j], '^\s*flags:\s*(\S+)')
                    if ($f.Success) { $flags = $f.Groups[1].Value; break }
                }
                $patterns.Add([pscustomobject]@{ where = "$($file.Name):$($i + 1)"; pattern = ($m.Groups[1].Value -replace "''", "'"); flags = $flags })
            }
        }
        $patterns.Count | Should -BeGreaterThan 0
        $js = 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const bad=[];for(const p of JSON.parse(s)){try{new RegExp(p.pattern,p.flags)}catch(e){bad.push(p.where+": "+e.message)}}console.log(bad.join("\n"));process.exit(bad.length?1:0)})'
        $out = ($patterns | ConvertTo-Json -Depth 3 -AsArray) | node -e $js 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $out
    }
}
