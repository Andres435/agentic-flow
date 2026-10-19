#Requires -Version 7
<#
.SYNOPSIS
    Fail-closed gate for all agentic-flow requirements.

.DESCRIPTION
    Encodes the current workflow contracts from README.md, _shared/ticket-artifacts.md,
    and _shared/severity-and-output.md as mechanical checks. Run before merging any PR
    that touches workflow docs, scripts, or CI config.

    Wave 2's /doctor calls this same script so local and CI cannot drift.

    Exit code 0 = all checks pass, 1 = at least one violation.

.PARAMETER Root
    Workspace root. Defaults to two levels up from $PSScriptRoot (scripts/ticket/).

.PARAMETER WarnOnly
    Print violations but exit 0.

.EXAMPLE
    .\scripts\ticket\Assert-AgenticFlow.ps1

.EXAMPLE
    .\scripts\ticket\Assert-AgenticFlow.ps1 -WarnOnly
#>

[CmdletBinding()]
param(
    [string]$Root = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [switch]$WarnOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$violations = [System.Collections.Generic.List[string]]::new()
function Fail { param([string]$Msg) $violations.Add($Msg) }

. (Join-Path $PSScriptRoot 'lib/TicketPrefix.ps1')
$ticketPrefix = Get-TicketPrefix -Root $Root

# Child scripts call `exit`, so they must run in a subprocess. The workflow
# requires PowerShell 7: invoking Windows PowerShell 5.1 here can misdecode
# BOM-less UTF-8 scripts and turn punctuation inside strings into parse errors.
function Get-PowerShell7Path {
    $cmd = Get-Command 'pwsh' -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    throw "PowerShell 7 (pwsh) is required. See MACHINE-SETUP.md."
}

# ---- 1. Doc budgets --------------------------------------------------------
# Delegate to Assert-DocBudget.ps1 so the budget table is single-source.
$budgetScript = Join-Path (Join-Path $Root 'scripts') 'Assert-DocBudget.ps1'
if (Test-Path -LiteralPath $budgetScript) {
    $out = & (Get-PowerShell7Path) -NonInteractive -NoProfile -File $budgetScript -Root $Root 2>&1
    if ($LASTEXITCODE -ne 0) {
        foreach ($line in $out) {
            if ($line -match 'over by') { Fail "doc-budget: $line" }
        }
        if (-not ($violations | Where-Object { $_ -like 'doc-budget:*' })) {
            Fail "doc-budget: Assert-DocBudget.ps1 exited $LASTEXITCODE -- $($out -join '; ')"
        }
    }
} else {
    Fail "doc-budget: Assert-DocBudget.ps1 not found at $budgetScript"
}

# ---- 1b. Doc links ---------------------------------------------------------
# Delegate to Assert-DocLinks.ps1 so the link rules stay single-source. Hard
# failures are broken targets and stale path labels; tier warnings are advisory
# there and stay advisory here.
$linkScript = Join-Path (Join-Path $Root 'scripts') 'Assert-DocLinks.ps1'
if (Test-Path -LiteralPath $linkScript) {
    $out = & (Get-PowerShell7Path) -NonInteractive -NoProfile -File $linkScript -Root $Root 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Only detail lines under a [FAIL] header are violations. [WARN] (tier
        # inversions) is advisory there and must stay advisory here.
        $inFail = $false
        foreach ($line in $out) {
            $t = $line.ToString()
            if ($t -match '^\[FAIL\]')          { $inFail = $true;  continue }
            if ($t -match '^\[(WARN|PASS)\]')   { $inFail = $false; continue }
            if ($inFail -and $t.Trim())         { Fail "doc-links: $($t.Trim())" }
        }
        if (-not ($violations | Where-Object { $_ -like 'doc-links:*' })) {
            Fail "doc-links: Assert-DocLinks.ps1 exited $LASTEXITCODE -- $($out -join '; ')"
        }
    }
} else {
    Fail "doc-links: Assert-DocLinks.ps1 not found at $linkScript"
}

# ---- 2. Command shims must reference skills/, adapters/, or scripts/ ------
# A command is a thin shim: its body lives in skills/, adapters/, or scripts/.
# Fail only when none of those patterns appear (guards against full skill bodies
# accidentally committed as commands).
$commandsDir = Join-Path $Root 'commands'
if (Test-Path -LiteralPath $commandsDir) {
    Get-ChildItem -LiteralPath $commandsDir -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' } | ForEach-Object {
        $content = Get-Content -LiteralPath $_.FullName -Raw
        if ($content -notmatch 'skills/' -and $content -notmatch 'playbooks/' -and $content -notmatch 'adapters/' -and $content -notmatch 'scripts[/\\]') {
            Fail "command-shim: commands/$($_.Name) does not reference skills/, playbooks/, adapters/, or scripts/ -- commands must be thin shims"
        }
    }
}

# ---- 3. profile.json schema ------------------------------------------------
$profilePath = Join-Path $Root 'profile.json'
if (-not (Test-Path -LiteralPath $profilePath)) {
    Fail "profile: profile.json not found at repo root"
} else {
    try {
        $prof = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
        $keys = $prof.PSObject.Properties.Name
        foreach ($k in @('id', 'ticketPrefix', 'ticketSystem', 'defaultMode', 'repos')) {
            if ($keys -notcontains $k) { Fail "profile: missing required key '$k'" }
        }
        if (($keys -contains 'defaultMode') -and $prof.defaultMode -notin @('branch', 'worktree')) {
            Fail "profile: defaultMode '$($prof.defaultMode)' must be 'branch' or 'worktree'"
        }
        if (($keys -contains 'repos') -and -not @($prof.repos).Count) {
            Fail "profile: repos array is empty"
        }
        if ($keys -notcontains 'stacks' -or $null -eq $prof.stacks) {
            Fail "profile: stacks is missing"
        } else {
            # Shape via profile.schema.json (same Test-Json mechanism as manifest.schema.json),
            # then the cross-field checks the schema cannot express.
            . (Join-Path $PSScriptRoot '../lib/StackServices.ps1')
            $stacksSchema = Join-Path $PSScriptRoot 'profile.schema.json'
            $stacksJson = $prof.stacks | ConvertTo-Json -Depth 8
            $shapeError = $null
            $shapeOk = $false
            try {
                $shapeOk = Test-Json -Json $stacksJson -SchemaFile $stacksSchema -ErrorAction Stop
            } catch {
                $shapeError = $_.Exception.Message
            }
            if (-not $shapeOk) {
                if (-not $shapeError) { $shapeError = 'does not match profile.schema.json' }
                Fail "profile: stacks schema -- $shapeError"
            }
            $findings = Get-StackProfileFindings -Stack $prof.stacks -Root $Root -SecretPatternsPath (Join-Path $PSScriptRoot 'secret-patterns.json')
            foreach ($msg in $findings.Violations) { Fail $msg }
            foreach ($msg in $findings.Warnings) { Write-Host "[WARN] $msg" }
        }
    } catch {
        Fail "profile: profile.json is not valid JSON -- $($_.Exception.Message)"
    }
}

# ---- 4. Retired artifacts banned -------------------------------------------
$plansDir = Join-Path $Root 'plans'
if (Test-Path -LiteralPath $plansDir) {
    foreach ($pat in @("$ticketPrefix*-impl-prompt.md", "$ticketPrefix*-workitem.json", 'scorecard-trend.md')) {
        @(Get-ChildItem -LiteralPath $plansDir -Filter $pat -ErrorAction SilentlyContinue) | ForEach-Object {
            Fail "retired-artifact: plans/$($_.Name) was superseded -- delete it (see _shared/ticket-artifacts.md)"
        }
    }
}

# ---- 4b. User plans stay out of git ----------------------------------------
# Ticket manifests, plans, feedback and the ledger are user-local. Only these
# plans/ paths may be tracked or staged; editing them is the one allowed change.
# The commit hook and hooks/git-hooks/pre-commit enforce the same list.
$plansAllow = '^plans/(README\.md|closeout-index\.md|workflow-template-plan\.md|examples/.+)$'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $inRepo = (& git -C $Root rev-parse --is-inside-work-tree 2>$null) -eq 'true'
    if ($inRepo) {
        $plansTracked = @(& git -C $Root ls-files -- plans 2>$null)
        $plansStaged  = @(& git -C $Root diff --cached --name-only --diff-filter=ACR -- plans 2>$null)
        foreach ($p in @($plansTracked + $plansStaged | Sort-Object -Unique)) {
            if ($p -and $p -notmatch $plansAllow) {
                Fail "user-plans: $p is user-local and must not be in git -- run git rm --cached `"$p`" (see _shared/ticket-artifacts.md)"
            }
        }
    }
} finally {
    $ErrorActionPreference = $prevEap
}

# ---- 4c. No secrets in tracked files ----------------------------------------
# The token patterns from scripts/ticket/secret-patterns.json, the same set the commit
# hooks use (hooks/core/secret-scan.js). A line containing secret-scan:allow is exempt.
# Findings name the file, line and pattern, never the matched text.
$secretFile = Join-Path (Join-Path (Join-Path $Root 'scripts') 'ticket') 'secret-patterns.json'
if (-not (Test-Path -LiteralPath $secretFile)) {
    Fail "secrets: scripts/ticket/secret-patterns.json is missing"
} else {
    $tokenPatterns = @((Get-Content -LiteralPath $secretFile -Raw | ConvertFrom-Json).patterns |
        Where-Object { $_.kind -eq 'token' } | ForEach-Object {
            $opts = if ($_.PSObject.Properties.Name -contains 'ignoreCase' -and $_.ignoreCase) { 'IgnoreCase' } else { 'None' }
            [pscustomobject]@{ Name = $_.name; Regex = [regex]::new($_.pattern, $opts) }
        })
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $tracked = @(& git -C $Root ls-files 2>$null)
    } finally {
        $ErrorActionPreference = $prevEap
    }
    foreach ($rel in $tracked) {
        $full = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        if ((Get-Item -LiteralPath $full -Force).Length -gt 1MB) { continue }  # -Force: dotfiles are hidden on Linux
        $text = [IO.File]::ReadAllText($full)
        if ($text.IndexOf([char]0) -ge 0) { continue }  # binary
        $lineNo = 0
        foreach ($line in ($text -split "`r?`n")) {
            $lineNo++
            if ($line.Contains('secret-scan:allow')) { continue }
            foreach ($p in $tokenPatterns) {
                if ($p.Regex.IsMatch($line)) { Fail "secrets: ${rel}:$lineNo matches $($p.Name) -- remove it, or mark a false positive with secret-scan:allow" }
            }
        }
    }
}

# ---- 5. No hardcoded worktree paths in skills/** and commands/*.md --
# Match only when a real ticket number (digits) appears — <prefix><n> is a documentation
# placeholder and is intentionally allowed in skill descriptions.
$pathPat = 'source[/\\\\]worktrees[/\\\\]' + [regex]::Escape($ticketPrefix) + '\d+'
foreach ($dir in @((Join-Path $Root 'skills'), (Join-Path $Root 'commands'))) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.md' | ForEach-Object {
        $rel = $_.FullName.Substring($Root.Length + 1)
        $content = Get-Content -LiteralPath $_.FullName -Raw
        if ($content -match $pathPat) {
            Fail "hardcoded-path: $rel contains literal 'source/worktrees/$ticketPrefix<n>' -- use Resolve-TicketRoot"
        }
    }
}

# ---- 6. Ledger column contract ---------------------------------------------
# The ledger is user-local, so a fresh clone and CI have none. Check the local one
# when it exists; Update-TicketLedger.Tests.ps1 owns the header it writes.
$ledgerPath = Join-Path (Join-Path $Root 'plans') 'ticket-ledger.md'
if (Test-Path -LiteralPath $ledgerPath) {
    $hdr = Get-Content -LiteralPath $ledgerPath | Where-Object { $_ -match 'Ticket.*Type.*Closed' } | Select-Object -First 1
    if (-not $hdr) { $hdr = '' }
    $required = @('Ticket', 'Type', 'Closed', 'Mode', 'Hours', 'Pts', 'E', 'C', '$tok', 'CtxS%', 'CtxR%', 'Ctx%', 'PR')
    $missing = @($required | Where-Object { $hdr -notmatch [regex]::Escape($_) })
    if ($missing.Count) {
        Fail "ledger-columns: plans/ticket-ledger.md header missing column(s): $($missing -join ', ')"
    }
}

# ---- 6b. Workflow epoch -----------------------------------------------------
# Fails only on a malformed local ledger row. The epoch id, a new epoch, and a due
# re-rate are [INFO] lines: a contract change is information, never a failure.
$epochScript = Join-Path $PSScriptRoot 'Assert-WorkflowEpoch.ps1'
if (Test-Path -LiteralPath $epochScript) {
    $out = & (Get-PowerShell7Path) -NonInteractive -NoProfile -File $epochScript -Root $Root 2>&1
    foreach ($line in $out) {
        $t = $line.ToString().Trim()
        if ($t -match '^\[INFO\]') { Write-Host $t -ForegroundColor DarkGray }
    }
    if ($LASTEXITCODE -ne 0) {
        foreach ($line in $out) {
            $t = $line.ToString().Trim()
            if ($t -match '^\[FAIL\]') { Fail "workflow-epoch: $t" }
        }
        if (-not ($violations | Where-Object { $_ -like 'workflow-epoch:*' })) {
            Fail "workflow-epoch: Assert-WorkflowEpoch.ps1 exited $LASTEXITCODE -- $($out -join '; ')"
        }
    }
} else {
    Fail "workflow-epoch: Assert-WorkflowEpoch.ps1 not found at $epochScript"
}

# ---- 7. INDEX.md links every tracked doc -------------------------------------
# AGENTS.md tells every chat to grep INDEX.md first, so a doc with no row is a doc no
# chat finds. Each tracked .md/.mdc must appear as a link target `](path` somewhere in
# INDEX.md (grouped rows are fine). Exempt: per-ticket and example plans, fixtures,
# scratch, user config, folder READMEs, INDEX itself, and the CLAUDE.md overlays.
$indexPath = Join-Path $Root 'INDEX.md'
if (Test-Path -LiteralPath $indexPath) {
    $idx = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8
    $ticketPrefixForPlans = 'TICKET-'
    if ((Test-Path -LiteralPath $profilePath)) {
        try {
            $pp = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
            if ($pp.PSObject.Properties.Name -contains 'ticketPrefix' -and $pp.ticketPrefix) { $ticketPrefixForPlans = [string]$pp.ticketPrefix }
        } catch { }
    }
    $indexExempt = @("plans/$ticketPrefixForPlans*", 'plans/examples/*', 'apps/*/plans/*', '*/fixtures/*', 'tmp/*', 'user/*', 'INDEX.md',
        'CLAUDE.md', '*/CLAUDE.md', 'adapters/*/workspace-*', '*/README.md', '*/README.markdown', '*/_README.md')
    $tracked = @()
    Push-Location -LiteralPath $Root
    # --others --exclude-standard: a new doc is checked before its first commit, not after.
    # Minus --deleted: a doc removed from the tree needs no row even before the removal is staged.
    try {
        $deleted = @(& git ls-files --deleted -- '*.md' '*.mdc' '*.markdown' 2>$null)
        $tracked = @(& git ls-files --cached --others --exclude-standard -- '*.md' '*.mdc' '*.markdown' 2>$null |
            Where-Object { $deleted -notcontains $_ })
    } finally { Pop-Location }
    if (-not $tracked.Count) { Fail "index-coverage: git ls-files returned no docs (run from a git checkout)" }
    $unindexed = @(foreach ($doc in $tracked) {
        $doc = $doc -replace '\\', '/'
        if (@($indexExempt | Where-Object { $doc -like $_ }).Count) { continue }
        if ($idx -notmatch ('\]\(' + [regex]::Escape($doc) + '[)#]')) { $doc }
    })
    foreach ($doc in $unindexed) {
        Fail "index-coverage: INDEX.md has no row linking $doc"
    }
} else {
    Fail "index-coverage: INDEX.md not found"
}

# ---- 10. Command/skill surface = Claude plugin + catalogs ------------------
# Cursor reads commands/*.md from disk. Claude Code only loads paths listed in
# .claude-plugin/plugin.json. Catalogs (INDEX.md, commands/_README.md) are how
# humans find the same names. Adding a command or SKILL.md without those three
# updates is the failure this check exists to catch.
function ConvertTo-PluginRel {
    param([string]$Path)
    return (($Path -replace '\\', '/').TrimEnd('/'))
}

$pluginManifest = Join-Path $Root '.claude-plugin/plugin.json'
if (-not (Test-Path -LiteralPath $pluginManifest)) {
    Fail "plugin-surface: .claude-plugin/plugin.json not found"
} else {
    try {
        $plugin = Get-Content -LiteralPath $pluginManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Fail "plugin-surface: .claude-plugin/plugin.json is not valid JSON -- $($_.Exception.Message)"
        $plugin = $null
    }

    if ($plugin) {
        $pluginCmds = @(
            @($plugin.commands) | ForEach-Object { ConvertTo-PluginRel $_ }
        )
        $diskCmds = @()
        if (Test-Path -LiteralPath $commandsDir) {
            $diskCmds = @(
                Get-ChildItem -LiteralPath $commandsDir -Filter '*.md' |
                    Where-Object { $_.Name -notlike '_*' -and $_.Name -ne 'README.md' } |
                    ForEach-Object { ConvertTo-PluginRel ("./commands/$($_.Name)") }
            )
        }
        foreach ($c in $diskCmds) {
            if ($pluginCmds -notcontains $c) {
                Fail "plugin-surface: $c is a command file but missing from .claude-plugin/plugin.json commands[] -- Claude Code will not register /<plugin>:$($c.Substring('./commands/'.Length).Replace('.md',''))"
            }
        }
        foreach ($c in $pluginCmds) {
            if ($diskCmds -notcontains $c) {
                Fail "plugin-surface: $c is in plugin.json commands[] but the file is missing"
            }
        }

        $pluginSkills = @(
            @($plugin.skills) | ForEach-Object { ConvertTo-PluginRel $_ }
        )
        $diskSkills = @()
        $skillsRoot = Join-Path $Root 'skills'
        if (Test-Path -LiteralPath $skillsRoot) {
            $diskSkills = @(
                Get-ChildItem -LiteralPath $skillsRoot -Recurse -Filter 'SKILL.md' |
                    ForEach-Object {
                        $dir = $_.DirectoryName.Substring($Root.Length).TrimStart('\', '/')
                        ConvertTo-PluginRel ("./$dir")
                    }
            )
        }
        foreach ($s in $diskSkills) {
            if ($pluginSkills -notcontains $s) {
                Fail "plugin-surface: $s has SKILL.md but is missing from .claude-plugin/plugin.json skills[] -- Claude Code will not load it"
            }
        }
        foreach ($s in $pluginSkills) {
            if ($diskSkills -notcontains $s) {
                Fail "plugin-surface: $s is in plugin.json skills[] but has no SKILL.md"
            }
        }

        $readmePath = Join-Path $commandsDir '_README.md'
        $readmeText = if (Test-Path -LiteralPath $readmePath) {
            Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8
        } else {
            Fail "plugin-surface: commands/_README.md not found"
            ''
        }
        foreach ($c in $diskCmds) {
            $stem = [IO.Path]::GetFileNameWithoutExtension($c)
            $slash = "/$stem"
            if ($readmeText -and ($readmeText -notmatch [regex]::Escape($slash)) -and ($readmeText -notmatch [regex]::Escape("$stem.md"))) {
                Fail "plugin-surface: commands/_README.md does not mention $slash or $stem.md"
            }
        }
    }
}

# ---- 8. Hook and plugin manifests --------------------------------------------
# Cursor's hooks.json (repo root) and Claude's adapters/claude/hooks/hooks.json must be
# valid JSON, wire the required hooks, and point only at scripts that exist. Each IDE's
# plugin manifest must be valid JSON and its ./relative paths must exist.
# Claude runs the commit guard and the push gate through one process (git-guard.js).
$hookManifests = @(
    @{ Rel = 'hooks.json'; Events = @('sessionStart', 'beforeReadFile', 'beforeShellExecution'); Needs = @('closeout', 'git-push-agentic-flow', 'git-commit-ticket') },
    @{ Rel = 'adapters/claude/hooks/hooks.json'; Events = @('SessionStart', 'PreToolUse', 'UserPromptSubmit'); Needs = @('closeout', 'git-guard') }
)
foreach ($hm in $hookManifests) {
    $hmPath = Join-Path $Root $hm.Rel
    if (-not (Test-Path -LiteralPath $hmPath)) { Fail "hooks: $($hm.Rel) not found"; continue }
    $hmText = Get-Content -LiteralPath $hmPath -Raw
    try { $null = $hmText | ConvertFrom-Json } catch { Fail "hooks: $($hm.Rel) is not valid JSON -- $($_.Exception.Message)"; continue }
    foreach ($ev in $hm.Events) {
        if ($hmText -notmatch [regex]::Escape('"' + $ev + '"')) { Fail "hooks: $($hm.Rel) does not define $ev" }
    }
    foreach ($need in $hm.Needs) {
        if ($hmText -notmatch $need) { Fail "hooks: $($hm.Rel) does not wire $need" }
    }
    foreach ($m in [regex]::Matches($hmText, '(?:\./|\$\{CLAUDE_PLUGIN_ROOT\}/)([\w./-]+\.js)')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $m.Groups[1].Value))) {
            Fail "hooks: $($hm.Rel) points at missing $($m.Groups[1].Value)"
        }
    }
}
foreach ($pm in @('.claude-plugin/plugin.json', '.cursor-plugin/plugin.json', '.codex-plugin/plugin.json')) {
    $pmPath = Join-Path $Root $pm
    if (-not (Test-Path -LiteralPath $pmPath)) { continue }
    $pmText = Get-Content -LiteralPath $pmPath -Raw
    try { $null = $pmText | ConvertFrom-Json } catch { Fail "plugin: $pm is not valid JSON -- $($_.Exception.Message)"; continue }
    foreach ($m in [regex]::Matches($pmText, '"(\./[^"]+)"')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $m.Groups[1].Value))) {
            Fail "plugin: $pm points at missing $($m.Groups[1].Value)"
        }
    }
}

# ---- 9. Template-only: workflow skills must not mention TMO specifics ------
$isTemplate = $false
if (Test-Path -LiteralPath $profilePath) {
    try {
        $p = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
        $isTemplate = ($p.PSObject.Properties.Name -contains 'id') -and $p.id -ne 'tmo'
    } catch { }
}

if ($isTemplate) {
    $tmoTerms = @('TmoPro', 'IIS Express', 'Custom.StoryPointsActual')
    foreach ($relDir in @('skills', '_shared')) {
        $wfDir = Join-Path $Root $relDir
        if (-not (Test-Path -LiteralPath $wfDir)) { continue }
        Get-ChildItem -LiteralPath $wfDir -Recurse -Filter '*.md' | ForEach-Object {
            $rel = $_.FullName.Substring($Root.Length + 1)
            $content = Get-Content -LiteralPath $_.FullName -Raw
            foreach ($term in $tmoTerms) {
                if ($content -match [regex]::Escape($term)) {
                    Fail "template-vanilla: $rel mentions '$term' -- TMO content must stay in the tmo profile"
                }
            }
        }
    }
}

# ---- 11. IDE-neutral core ---------------------------------------------------
# The core (skills/, _shared/, agents/, commands/, rules/, environments/, hooks/core/,
# AGENTS.md, USER-MANUAL.md) names tiers and verbs, never an IDE's models or tools.
# Each adapters/<ide>/ maps them: model-usage.md maps tiers to models, and the verbs in
# _shared/harness-verbs.md map to that IDE's tools. A vendor or IDE change then touches
# its adapter, not every skill.
$modelRoutingPath = Join-Path $Root '_shared/model-routing.md'
if (-not (Test-Path -LiteralPath $modelRoutingPath)) {
    Fail "model-routing: _shared/model-routing.md not found"
}

$routingAdapters = @(Get-ChildItem -LiteralPath (Join-Path $Root 'adapters') -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'model-usage.md' } | Where-Object { Test-Path -LiteralPath $_ })
if (-not $routingAdapters.Count) { Fail "model-routing: no adapters/<ide>/model-usage.md found" }
$routingTiers = @('fast', 'standard', 'deep', 'frontier')
foreach ($adapterPath in $routingAdapters) {
    $adapterRel = ($adapterPath.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/')
    $adapterContent = Get-Content -LiteralPath $adapterPath -Raw -Encoding UTF8
    foreach ($tier in $routingTiers) {
        $rowPattern = '(?m)^\|\s*`?' + $tier + '`?\s*\|'
        if ($adapterContent -notmatch $rowPattern) {
            Fail "model-routing: $adapterRel has no '$tier' tier row"
        }
    }
}

# Bans over the core. INDEX.md is exempt (its keywords exist to be searched), and
# harness-verbs.md is exempt from the tool ban (it is the vocabulary). Model names match in
# any case ("opus" is as much a leak as "Opus"); only Composer stays case-sensitive, because
# "composer" is ordinary English a project rule may use.
$modelNamePattern = '(?i:\b(Grok|Sonnet|Opus|Haiku|Fable)\b|grok-|gpt-\d)|\bComposer\b|composer-\d'
$toolNamePattern  = '\b(AskQuestion|SwitchMode|target_mode_id|AskUserQuestion|ExitPlanMode|EnterPlanMode|generalPurpose|CURSOR_PROJECT_DIR|CLAUDE_PROJECT_DIR|spawn_agent)\b|\bTask tool\b|Custom Mode|context-window indicator|native Build'
$coreFiles = [System.Collections.Generic.List[string]]::new()
foreach ($dir in @('skills', 'agents', 'commands', '_shared', 'rules', 'environments', 'hooks/core')) {
    $dirPath = Join-Path $Root $dir
    if (-not (Test-Path -LiteralPath $dirPath)) { continue }
    Get-ChildItem -LiteralPath $dirPath -Recurse -File |
        Where-Object { $_.Extension -in @('.md', '.mdc', '.markdown', '.js') } |
        ForEach-Object { $coreFiles.Add($_.FullName) }
}
foreach ($top in @('AGENTS.md', 'USER-MANUAL.md')) {
    $p = Join-Path $Root $top
    if (Test-Path -LiteralPath $p) { $coreFiles.Add($p) }
}

foreach ($coreFile in $coreFiles) {
    $coreRel = ($coreFile.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/')
    $coreLines = @(Get-Content -LiteralPath $coreFile -Encoding UTF8)
    for ($li = 0; $li -lt $coreLines.Count; $li++) {
        foreach ($m in [regex]::Matches($coreLines[$li], $modelNamePattern)) {
            Fail "ide-neutral: ${coreRel}:$($li + 1) names a model ('$($m.Value)') -- use a tier word; models live in adapters/<ide>/model-usage.md"
        }
        if ($coreRel -eq '_shared/harness-verbs.md') { continue }
        foreach ($m in [regex]::Matches($coreLines[$li], $toolNamePattern)) {
            Fail "ide-neutral: ${coreRel}:$($li + 1) names an IDE tool ('$($m.Value)') -- use a verb from _shared/harness-verbs.md; the adapter maps it"
        }
    }
}

# ---- 12. Skill layout ------------------------------------------------------
# One folder per skill: skills/<name>/SKILL.md, with playbooks/ and references/
# only as immediate children. A command file with the same name is a second
# slash entry, so that clash fails too.
$skillsLayoutRoot = Join-Path $Root 'skills'
$rootPlaybooks = Join-Path $Root 'playbooks'
if (Test-Path -LiteralPath $rootPlaybooks) {
    Fail "skill-layout: repo-root playbooks/ exists -- playbooks belong inside a skill folder"
}
$badgeColors = @('default', 'green', 'cyan', 'blue', 'purple', 'magenta', 'orange', 'yellow', 'red', 'brand')
$skillNames = @()
if (Test-Path -LiteralPath $skillsLayoutRoot) {
    $skillsLayoutFull = [IO.Path]::GetFullPath($skillsLayoutRoot).TrimEnd('\', '/')
    Get-ChildItem -LiteralPath $skillsLayoutRoot -Directory | ForEach-Object {
        $skillNames += $_.Name
        $skillMd = Join-Path $_.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillMd)) {
            Fail "skill-layout: skills/$($_.Name) has no SKILL.md -- category folders and skills nested two deep are not discovered"
            return  # nothing below can be read without it; keep checking the other skills
        }
        $playbookAtRoot = Join-Path $_.FullName 'PLAYBOOK.md'
        if (Test-Path -LiteralPath $playbookAtRoot) {
            Fail "skill-layout: skills/$($_.Name)/PLAYBOOK.md must live under playbooks/"
        }
        $badgeText = Get-Content -LiteralPath $skillMd -Raw -Encoding UTF8
        $iconMatch = [regex]::Match($badgeText, '(?m)^icon:\s*(\S+)\s*$')
        $colorMatch = [regex]::Match($badgeText, '(?m)^color:\s*(\S+)\s*$')
        if (-not $iconMatch.Success) {
            Fail "skill-layout: skills/$($_.Name)/SKILL.md needs an icon so the slash badge is not the default lightning mark"
        }
        if (-not $colorMatch.Success -or ($badgeColors -notcontains $colorMatch.Groups[1].Value)) {
            Fail "skill-layout: skills/$($_.Name)/SKILL.md color must be one of $($badgeColors -join ', ')"
        }
    }
    Get-ChildItem -LiteralPath $skillsLayoutRoot -Recurse -Filter 'SKILL.md' -File | ForEach-Object {
        $parentFull = [IO.Path]::GetFullPath($_.DirectoryName).TrimEnd('\', '/')
        $expectedParent = $skillsLayoutFull
        if ($parentFull -ne (Join-Path $expectedParent $_.Directory.Name)) {
            $rel = ($_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/')
            Fail "skill-layout: $rel is not skills/<name>/SKILL.md"
        }
    }
    Get-ChildItem -LiteralPath $skillsLayoutRoot -Recurse -Directory | Where-Object {
        $_.Name -in @('playbooks', 'references')
    } | ForEach-Object {
        $parent = $_.Parent
        $parentIsSkill = ($null -ne $parent) -and (Test-Path -LiteralPath (Join-Path $parent.FullName 'SKILL.md'))
        $parentIsTop = ($null -ne $parent) -and ($parent.Parent -ne $null) -and (
            [IO.Path]::GetFullPath($parent.Parent.FullName).TrimEnd('\', '/') -eq $skillsLayoutFull
        )
        if (-not ($parentIsSkill -and $parentIsTop)) {
            $rel = ($_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/')
            Fail "skill-layout: $rel must be an immediate child of skills/<name>/"
        }
    }
}
if (Test-Path -LiteralPath $commandsDir) {
    Get-ChildItem -LiteralPath $commandsDir -Filter '*.md' -File |
        Where-Object { $_.Name -notlike '_*' -and $_.Name -ne 'README.md' } |
        ForEach-Object {
            $cmdText = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
            $cmdName = $_.BaseName
            $nameMatch = [regex]::Match($cmdText, '(?m)^name:\s*(\S+)')
            if ($nameMatch.Success) { $cmdName = $nameMatch.Groups[1].Value }
            if ($skillNames -contains $cmdName) {
                Fail "skill-layout: commands/$($_.Name) name '$cmdName' matches a skill -- one slash entry, keep the skill"
            }
            $cmdIcon = [regex]::Match($cmdText, '(?m)^icon:\s*(\S+)\s*$')
            $cmdColor = [regex]::Match($cmdText, '(?m)^color:\s*(\S+)\s*$')
            if (-not $cmdIcon.Success) {
                Fail "skill-layout: commands/$($_.Name) needs an icon so the slash badge is not the default gear"
            }
            if (-not $cmdColor.Success -or ($badgeColors -notcontains $cmdColor.Groups[1].Value)) {
                Fail "skill-layout: commands/$($_.Name) color must be one of $($badgeColors -join ', ')"
            }
        }
}
$cursorManifest = Join-Path $Root '.cursor-plugin/plugin.json'
if (-not (Test-Path -LiteralPath $cursorManifest)) {
    Fail "skill-layout: .cursor-plugin/plugin.json not found"
} else {
    try {
        $cursorPlugin = Get-Content -LiteralPath $cursorManifest -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace([string]$cursorPlugin.name)) {
            Fail "skill-layout: .cursor-plugin/plugin.json name is empty"
        }
        if ([string]$cursorPlugin.hooks -ne './hooks.json') {
            Fail "skill-layout: .cursor-plugin/plugin.json hooks must be ./hooks.json"
        }
        if ([string]$cursorPlugin.commands -ne './.cursor-plugin/slash-icons-disabled/commands' -or [string]$cursorPlugin.skills -ne './.cursor-plugin/slash-icons-disabled/skills') {
            Fail "skill-layout: .cursor-plugin/plugin.json commands and skills must point at slash-icons-disabled. Plugin discovery ignores per-file icon frontmatter; user-level links own the slash picker. The Claude manifest owns the enumerated list."
        }
    } catch {
        Fail "skill-layout: .cursor-plugin/plugin.json is not valid JSON -- $($_.Exception.Message)"
    }
}
$codexManifest = Join-Path $Root '.codex-plugin/plugin.json'
if (-not (Test-Path -LiteralPath $codexManifest)) {
    Fail "skill-layout: .codex-plugin/plugin.json not found"
} else {
    try {
        $codexPlugin = Get-Content -LiteralPath $codexManifest -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$codexPlugin.skills -ne './skills/') {
            Fail "skill-layout: .codex-plugin/plugin.json skills must be ./skills/ so one-level skills are discovered"
        }
    } catch {
        Fail "skill-layout: .codex-plugin/plugin.json is not valid JSON -- $($_.Exception.Message)"
    }
}

# ---- 12b. Doc claims hold; slash menu is the path only ------------------------
# Each claim in scripts/ticket/doc-claims.psd1 is a workflow fact the docs state. A doc that
# contradicts it (Forbid), a doc that stops stating it (Require), or code that no longer
# makes it true (Anchor) fails here. Link and budget checks cannot see any of these: a new
# close gate can ship while docs still say it is optional.
$claimsPath = Join-Path $Root 'scripts/ticket/doc-claims.psd1'
if (-not (Test-Path -LiteralPath $claimsPath)) {
    Fail "doc-claims: scripts/ticket/doc-claims.psd1 not found"
} else {
    try {
        $claimRegistry = Import-PowerShellDataFile -LiteralPath $claimsPath
    } catch {
        $claimRegistry = $null
        Fail "doc-claims: doc-claims.psd1 does not parse -- $($_.Exception.Message)"
    }
    if ($claimRegistry) {
        # The file universe: tracked plus new untracked files, as git sees them, so a
        # violation is caught before its first commit. Ticket files and scratch are out.
        $claimTicketGlob = 'plans/' + $ticketPrefix + '*'
        $claimFiles = @()
        Push-Location -LiteralPath $Root
        try {
            $claimFiles = @(& git ls-files --cached --others --exclude-standard 2>$null | ForEach-Object { $_ -replace '\\', '/' })
        } finally { Pop-Location }
        if (-not $claimFiles.Count) {
            $claimFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
                ForEach-Object { $_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/' })
        }
        $claimFiles = @($claimFiles | Where-Object {
            $_ -notlike $claimTicketGlob -and $_ -notlike 'tmp/*' -and $_ -notlike '*/fixtures/*' -and
            (Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf)
        })
        $docGlobs = @('*.md', '*.mdc', '*.markdown')
        function Test-AnyGlob([string]$Path, $Globs) {
            foreach ($g in @($Globs)) { if ($Path -like $g) { return $true } }
            return $false
        }
        function Read-ClaimFile([string]$Rel) {
            $p = Join-Path $Root ($Rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $null }
            return (Get-Content -LiteralPath $p -Raw -Encoding UTF8)
        }

        foreach ($claim in @($claimRegistry.Claims)) {
            $id = $claim.Id
            if ($claim.ContainsKey('Anchor')) {
                $anchorText = Read-ClaimFile $claim.Anchor.File
                if ($null -eq $anchorText -or $anchorText -notmatch $claim.Anchor.Pattern) {
                    Fail "doc-claims: $id -- anchor gone: $($claim.Anchor.File) no longer matches /$($claim.Anchor.Pattern)/. The code changed: update or retire this claim in doc-claims.psd1, with the docs it covers."
                }
            }
            $requires = if ($claim.ContainsKey('Require')) { @($claim.Require) } else { @() }
            foreach ($req in $requires) {
                $reqText = Read-ClaimFile $req.File
                if ($null -eq $reqText) {
                    Fail "doc-claims: $id -- $($req.File) is missing"
                } elseif ($reqText -notmatch $req.Pattern) {
                    Fail "doc-claims: $id -- $($req.File) must match /$($req.Pattern)/ ($($claim.Why))"
                }
            }
            $forbids = if ($claim.ContainsKey('Forbid')) { @($claim.Forbid) } else { @() }
            foreach ($forbid in $forbids) {
                $in = if ($forbid.ContainsKey('In')) { $forbid.In } else { $docGlobs }
                $except = if ($forbid.ContainsKey('Except')) { $forbid.Except } else { @() }
                foreach ($rel in $claimFiles) {
                    if (-not (Test-AnyGlob $rel $in) -or (Test-AnyGlob $rel $except)) { continue }
                    if ($rel -eq 'scripts/ticket/doc-claims.psd1') { continue }
                    $lines = @(Get-Content -LiteralPath (Join-Path $Root $rel) -Encoding UTF8)
                    for ($li = 0; $li -lt $lines.Count; $li++) {
                        if ($lines[$li] -match $forbid.Pattern) {
                            Fail "doc-claims: $id -- ${rel}:$($li + 1) contradicts the claim ('$($Matches[0])'). $($claim.Why)"
                        }
                    }
                }
            }
        }
    }
}

$requiredSlash = @(
    'engineering-mode', 'start-ticket', 'review-changes', 'complete-task', 'prep-pr',
    'implement', 'start-stack', 'swap-stack', 'stop-stack', 'address-pr-comments',
    'peer-review', 'start-new-project', 'adopt-project', 'research-x', 'doctor', 'onboard'
)
$planShapes = @('bug-fix', 'feature-plan', 'tech-spike', 'document-spike')
$slashListed = @()
$slashProfilePath = Join-Path $Root 'profile.json'
if (Test-Path -LiteralPath $slashProfilePath) {
    try {
        $slashProfile = Get-Content -LiteralPath $slashProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($slashProfile.PSObject.Properties.Name -contains 'slashCommands') {
            $slashListed = @($slashProfile.slashCommands)
        }
    } catch {
        Fail "slash-menu: profile.json is not valid JSON -- $($_.Exception.Message)"
    }
}
foreach ($name in $requiredSlash) {
    if ($slashListed -notcontains $name) {
        Fail "slash-menu: profile.json slashCommands is missing '$name'"
    }
    $skillDir = Join-Path (Join-Path $Root 'skills') $name
    if (-not (Test-Path -LiteralPath $skillDir)) {
        Fail "slash-menu: skills/$name is listed but the folder is missing"
    }
}
foreach ($name in $planShapes) {
    if ($slashListed -contains $name) {
        Fail "slash-menu: '$name' is a plan shape. /start-ticket reads it; it is not a slash command"
    }
}
foreach ($name in $slashListed) {
    if ($requiredSlash -notcontains $name) {
        Fail "slash-menu: '$name' is not a path command. Keep it on disk; do not put it in slashCommands"
    }
}

# ---- 12c. Every work type has a plan template ---------------------------------
# The router accepts a fixed set of workTypes; each must map to a start-ticket template
# that exists, or the plan step has nothing to follow and the agent improvises.
$routerPath = Join-Path $Root 'skills/ticket-router/SKILL.md'
if (Test-Path -LiteralPath $routerPath) {
    $routerText = Get-Content -LiteralPath $routerPath -Raw -Encoding UTF8
    $typesMatch = [regex]::Match($routerText, '`workType`:\s*((?:`[a-z]+`\s*\|?\s*)+)')
    $workTypes = @([regex]::Matches($typesMatch.Groups[1].Value, '`([a-z]+)`') | ForEach-Object { $_.Groups[1].Value })
    $mapMatch = [regex]::Match($routerText, '(?s)work-type template:(.+?)(?:\r?\n\s*\r?\n|$)')
    if (-not $workTypes.Count -or -not $mapMatch.Success) {
        Fail "worktype-templates: ticket-router/SKILL.md must list ``workType``: values and a 'work-type template:' map"
    } else {
        $templateFor = @{}
        foreach ($segment in ($mapMatch.Groups[1].Value -split ';')) {
            $pathMatch = [regex]::Match($segment, '`(skills/[^`]+\.md)`')
            if (-not $pathMatch.Success) { continue }
            $left = ($segment -split '→')[0]
            foreach ($t in $workTypes) {
                if ($left -match "\b$t\b") { $templateFor[$t] = $pathMatch.Groups[1].Value }
            }
        }
        foreach ($t in $workTypes) {
            if (-not $templateFor.ContainsKey($t)) {
                Fail "worktype-templates: workType '$t' has no plan template in ticket-router/SKILL.md"
            } elseif (-not (Test-Path -LiteralPath (Join-Path $Root $templateFor[$t]))) {
                Fail "worktype-templates: workType '$t' maps to missing $($templateFor[$t])"
            }
        }
    }
} else {
    Fail "worktype-templates: skills/ticket-router/SKILL.md not found"
}

# ---- 13. Agents surface ----------------------------------------------------
# Claude Code (and Cursor) register every agents/*.md as an agent, by filename,
# whether or not it is one -- a README there shows up as a spurious agent.
# Every agents/*.md must be a real agent definition; the folder guide lives in
# agents/README.markdown, which discovery does not pick up.
$agentsDir = Join-Path $Root 'agents'
if (Test-Path -LiteralPath $agentsDir) {
    Get-ChildItem -LiteralPath $agentsDir -Filter '*.md' -File | ForEach-Object {
        $agentText = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
        $front = [regex]::Match($agentText, '\A---\r?\n(.*?)\r?\n---', 'Singleline')
        if (-not $front.Success -or $front.Groups[1].Value -notmatch '(?m)^name:\s*\S' -or $front.Groups[1].Value -notmatch '(?m)^description:\s*\S') {
            Fail "agents-surface: agents/$($_.Name) has no 'name:'/'description:' frontmatter -- every agents/*.md registers as an agent; move docs to agents/README.markdown"
        }
    }
    # The reviewer runs as review-diff / peer-review-pr, whose contract is read-only
    # (_shared/subagent-functions.md). Prose alone let it inherit every tool.
    $reviewerPath = Join-Path $agentsDir 'code-reviewer.md'
    if (Test-Path -LiteralPath $reviewerPath) {
        $reviewerFront = [regex]::Match((Get-Content -LiteralPath $reviewerPath -Raw -Encoding UTF8), '\A---\r?\n(.*?)\r?\n---', 'Singleline').Groups[1].Value
        $denied = [regex]::Match($reviewerFront, '(?m)^disallowedTools:\s*(.+)$').Groups[1].Value
        foreach ($tool in @('Edit', 'Write', 'NotebookEdit')) {
            if ($denied -notmatch "(^|[,\s\[])$tool([,\s\]]|$)") {
                Fail "agents-surface: agents/code-reviewer.md must list '$tool' in disallowedTools -- review-diff and peer-review-pr are read-only"
            }
        }
    }
}

# ---- 13b. Generated command table and chat counts ----------------------------
$generatedDocs = Join-Path $PSScriptRoot 'Sync-GeneratedDocs.ps1'
if (Test-Path -LiteralPath $generatedDocs) {
    $genOut = & (Get-PowerShell7Path) -NonInteractive -NoProfile -File $generatedDocs -Check -Root $Root 2>&1
    foreach ($line in @($genOut)) {
        $t = $line.ToString().Trim()
        if ($t -match '^\[FAIL\] (.*)$') { Fail $Matches[1] }
    }
    if ($LASTEXITCODE -ne 0 -and -not ($violations | Where-Object { $_ -like 'generated-docs:*' })) {
        Fail "generated-docs: Sync-GeneratedDocs.ps1 exited $LASTEXITCODE"
    }
} else {
    Fail 'generated-docs: Sync-GeneratedDocs.ps1 not found'
}

# ---- 14. Docs move with the code they describe ------------------------------
# A gate, hook, or lifecycle skill change needs a doc change in the same branch, or a
# Docs-Unaffected trailer saying why not (doc-claims.psd1 CoChange). [INFO] lines are
# printed; a skip outside CI (no git, no base) is never a failure.
$docSyncScript = Join-Path $PSScriptRoot 'Assert-DocSync.ps1'
if (Test-Path -LiteralPath $docSyncScript) {
    $out = & (Get-PowerShell7Path) -NonInteractive -NoProfile -File $docSyncScript -Root $Root 2>&1
    foreach ($line in $out) {
        $t = $line.ToString().Trim()
        if ($t -match '^\[INFO\]') { Write-Host $t -ForegroundColor DarkGray }
    }
    if ($LASTEXITCODE -ne 0) {
        foreach ($line in $out) {
            $t = $line.ToString().Trim()
            if ($t -match '^\[FAIL\] (.*)$') { Fail $Matches[1] }
        }
        if (-not ($violations | Where-Object { $_ -like 'doc-sync:*' })) {
            Fail "doc-sync: Assert-DocSync.ps1 exited $LASTEXITCODE -- $($out -join '; ')"
        }
    }
} else {
    Fail "doc-sync: Assert-DocSync.ps1 not found at $docSyncScript"
}

# ---- Report ----------------------------------------------------------------
if ($violations.Count -eq 0) {
    Write-Host "[PASS] Agentic flow: all checks passed." -ForegroundColor Green
    exit 0
}

$label = if ($WarnOnly) { "[WARN]" } else { "[FAIL]" }
$color = if ($WarnOnly) { "Yellow" } else { "Red" }
Write-Host "$label Agentic flow: $($violations.Count) violation(s):" -ForegroundColor $color
foreach ($v in $violations) {
    Write-Host "  $v" -ForegroundColor $color
}
if ($WarnOnly) { exit 0 }
exit 1
