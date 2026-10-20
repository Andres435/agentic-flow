#Requires -Modules Pester
<#
.SYNOPSIS
    Every Assert-AgenticFlow section fails on a known violation, and passes on a clean copy.

.DESCRIPTION
    The per-check tests in Assert-AgenticFlow.Tests.ps1 run the gate on tiny fixtures where
    most sections fail anyway. This file proves the other direction on the real repo: a copy
    of the working tree passes, and the same copy with one violation per section injected
    fails with each section's prefix. A section that silently stopped checking would pass
    the clean run and still pass here -- which is what this catches.

    The copies live under this repo's gitignored tmp/, not TestDrive: the gate runs child
    .ps1 scripts from the copy, and an application allowlist may only let .ps1 files run
    inside the repos. Sections with their own tests are not repeated here: worktype-templates
    and doc-claims (Assert-AgenticFlow.Tests.ps1), workflow-epoch (Assert-WorkflowEpoch.Tests.ps1),
    doc-sync (Assert-DocSync.Tests.ps1). template-vanilla is not injected: its trigger words
    are the product strings this file must not carry.

    Run: Invoke-Pester ./scripts/ticket/Assert-AgenticFlow.Violations.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:Work = Join-Path $script:RepoRoot ("tmp/flow-fixtures/" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $script:EnvNames = @('GITHUB_ACTIONS', 'GITHUB_BASE_REF', 'DOCSYNC_BASE')
    $script:SavedEnv = @{}
    foreach ($n in $script:EnvNames) {
        $script:SavedEnv[$n] = [Environment]::GetEnvironmentVariable($n)
        [Environment]::SetEnvironmentVariable($n, $null)  # doc-sync must skip in a copy with no origin
    }

    # A copy of what git would see: tracked plus new untracked files, no ignored ones
    # (so no user-local plans/<ticket>* and no tmp/).
    function New-RepoCopy([string]$Name) {
        $dest = Join-Path $script:Work $Name
        $files = @(& git -C $script:RepoRoot ls-files --cached --others --exclude-standard)
        foreach ($rel in $files) {
            $src = Join-Path $script:RepoRoot $rel
            if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }  # deleted, not yet staged
            $to = Join-Path $dest $rel
            New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $src -Destination $to
        }
        & git -C $dest init -q -b main
        & git -C $dest -c core.autocrlf=false -c core.safecrlf=false add -A 2>$null
        & git -C $dest -c user.email=t@example.com -c user.name=t commit -q -m copy
        return $dest
    }
    function Add-Text([string]$Root, [string]$Rel, [string]$Text) {
        $p = Join-Path $Root $Rel
        New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force | Out-Null
        Add-Content -LiteralPath $p -Value $Text -Encoding UTF8
    }
    function Edit-Text([string]$Root, [string]$Rel, [string]$Old, [string]$New) {
        $p = Join-Path $Root $Rel
        $t = Get-Content -LiteralPath $p -Raw -Encoding UTF8
        if (-not $t.Contains($Old) -and $Old.Contains("`n")) { $Old = $Old.Replace("`n", "`r`n") }
        if (-not $t.Contains($Old)) { throw "fixture setup: '$Old' not found in $Rel" }
        Set-Content -LiteralPath $p -Value $t.Replace($Old, $New) -Encoding UTF8 -NoNewline
    }
    function Invoke-Gate([string]$Root) {
        $gate = Join-Path $Root 'scripts/ticket/Assert-AgenticFlow.ps1'
        $out = & pwsh -NoProfile -File $gate -Root $Root 2>&1 | Out-String
        return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
    }

    $clean = New-RepoCopy 'clean'
    # Like the main clone while a Claude Code session runs: a git-excluded worktree nested at
    # .claude/worktrees/<name>/ whose docs hold links that do not resolve from there.
    Add-Content -LiteralPath (Join-Path $clean '.git/info/exclude') -Value '.claude/worktrees/'
    Add-Text $clean '.claude/worktrees/x/.git' 'gitdir: ../../../.git/worktrees/x'
    Add-Text $clean '.claude/worktrees/x/_shared/glossary.md' '[gone](does-not-exist.md)'
    Add-Text $clean '.claude/worktrees/x/skills/doctor/SKILL.md' 'See source/worktrees/TICKET-12345 for the tree.'
    $script:Clean = Invoke-Gate $clean

    $bad = New-RepoCopy 'violations'
    Add-Text $bad '_shared/harness-verbs.md' (@(1..200 | ForEach-Object { "padding line $_" }) -join "`n")   # doc-budget
    Add-Text $bad '_shared/glossary.md' '[gone](does-not-exist.md)'                                       # doc-links
    Add-Text $bad 'commands/stray.md' 'Just prose, no pointer to a skill.'                                 # command-shim
    Edit-Text $bad 'profile.json' '"defaultMode": "branch"' '"defaultMode": "sometimes"'                   # profile
    Edit-Text $bad 'profile.json' '"services": []' '"services": [{"name":"a","command":"x","port":3000,"dependsOn":["ghost"]},{"name":"a","command":"y","port":3000,"cwd":"nowhere"}]'   # profile (stacks)
    Edit-Text $bad 'profile.json' "    `"doctor`",`n" ''                                                    # slash-menu
    Add-Text $bad 'plans/TICKET-99999-impl-prompt.md' 'retired'                                               # retired-artifact
    Add-Text $bad 'plans/TICKET-99998-manifest.json' '{}'                                                       # user-plans
    & git -C $bad add -f plans/TICKET-99998-manifest.json
    Add-Text $bad 'skills/doctor/SKILL.md' 'See source/worktrees/TICKET-12345 for the tree.'                   # hardcoded-path
    Add-Text $bad 'skills/doctor/SKILL.md' 'Run this on haiku.'                                           # ide-neutral
    Add-Text $bad 'plans/ticket-ledger.md' "| Ticket | Type | Closed |`n|---|---|---|"                      # ledger-columns
    Edit-Text $bad 'hooks.json' './adapters/cursor/hooks/session-context.js' './adapters/cursor/hooks/gone.js'  # hooks
    Edit-Text $bad '.cursor-plugin/plugin.json' '"./hooks.json"' '"./hooks-gone.json"'                     # plugin
    Edit-Text $bad '.claude-plugin/plugin.json' "    `"./skills/doctor`",`n" ''                            # plugin-surface
    Edit-Text $bad 'adapters/gpt/model-usage.md' '| `frontier` |' '| `later` |'                            # model-routing
    Add-Text $bad 'skills/orphan/notes.md' 'A folder with no SKILL.md.'                                    # skill-layout
    Add-Text $bad 'agents/notes.md' 'Notes, not an agent.'                                                 # agents-surface
    Add-Text $bad 'docs-new/unindexed.md' 'No INDEX row.'                                                  # index-coverage
    $script:Bad = Invoke-Gate $bad
}

AfterAll {
    foreach ($n in $script:EnvNames) { [Environment]::SetEnvironmentVariable($n, $script:SavedEnv[$n]) }
    if (Test-Path -LiteralPath $script:Work) {
        Get-ChildItem -LiteralPath $script:Work -Recurse -Force -File | ForEach-Object { $_.IsReadOnly = $false }
        Remove-Item -LiteralPath $script:Work -Recurse -Force
    }
}

Describe 'Assert-AgenticFlow on a copy of this repo' {
    It 'passes the clean copy' {
        $script:Clean.Out | Should -Match '\[PASS\] Agentic flow'
        $script:Clean.Code | Should -Be 0
    }

    It 'does not scan a session worktree nested at .claude/worktrees/' {
        $script:Clean.Out | Should -Not -Match '\.claude[/\\]worktrees'
    }

    It 'fails the copy with violations' {
        $script:Bad.Code | Should -Be 1
    }

    It 'reports <Prefix> for its injected violation' -ForEach @(
        @{ Prefix = 'doc-budget';       Detail = 'harness-verbs' }
        @{ Prefix = 'doc-links';        Detail = 'does-not-exist\.md' }
        @{ Prefix = 'command-shim';     Detail = 'commands/stray\.md' }
        @{ Prefix = 'profile';          Detail = "defaultMode 'sometimes'" }
        @{ Prefix = 'profile';          Detail = 'stacks\.services\[a\] name is not unique' }
        @{ Prefix = 'profile';          Detail = 'port 3000 is used by a' }
        @{ Prefix = 'profile';          Detail = "dependsOn unknown service 'ghost'" }
        @{ Prefix = 'profile';          Detail = "cwd 'nowhere' does not exist" }
        @{ Prefix = 'slash-menu';       Detail = "missing 'doctor'" }
        @{ Prefix = 'retired-artifact'; Detail = 'TICKET-99999-impl-prompt\.md' }
        @{ Prefix = 'user-plans';       Detail = 'TICKET-99998-manifest\.json' }
        @{ Prefix = 'hardcoded-path';   Detail = 'skills.doctor.SKILL\.md' }
        @{ Prefix = 'ide-neutral';      Detail = "names a model \('haiku'\)" }
        @{ Prefix = 'ledger-columns';   Detail = 'CtxS%' }
        @{ Prefix = 'hooks';            Detail = 'gone\.js' }
        @{ Prefix = 'plugin';           Detail = 'hooks-gone\.json' }
        @{ Prefix = 'plugin-surface';   Detail = 'skills/doctor' }
        @{ Prefix = 'model-routing';    Detail = "no 'frontier' tier row" }
        @{ Prefix = 'skill-layout';     Detail = 'skills/orphan' }
        @{ Prefix = 'agents-surface';   Detail = 'agents/notes\.md' }
        @{ Prefix = 'index-coverage';   Detail = 'docs-new/unindexed\.md' }
    ) {
        $script:Bad.Out | Should -Match ("(?m)^\s*" + [regex]::Escape($Prefix) + ':.*' + $Detail)
    }
}
