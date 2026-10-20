#Requires -Version 7
<#
.SYNOPSIS
    Verify that a ticket phase actually produced its required artifacts.

.DESCRIPTION
    Mechanical gate for the contract in _shared/ticket-artifacts.md. Replaces
    "the agent should remember to write these files" with a check that fails loudly.

    start-ticket   runs -Phase start     as its last action before the final message.
                   Also checks plan CONTENT, not just existence: a '## Plan Digest'
                   heading (ticket-plan-output.md), an 'Engineering Decisions'
                   heading (engineering-decisions.md -- 'None -- <why>' is valid),
                   and no unresolved placeholder ('TBD', 'resolve during implement').
                   The placeholder check is the point: an open decision is meant to
                   reach the user as a question, not ride into implementation.
                   Also requires a 'Work Plan' heading with numbered steps each
                   tagged [low]|[med]|[high]; any [high] step requires Engineering
                   Decisions to record an architect result (or an explicit
                   'architect skipped: <reason>').
    implement      runs -Phase implement as its first action. Does not re-check plan
                   content: a plan approved before those requirements existed must not
                   retroactively fail here. This is also the LOAD-TIME gate for
                   /complete-task -- see the note on -Phase close below.
    complete-task  runs -Phase close     after the ledger row, NOT at chat start.
                   The close timestamp and the ledger row are written during the
                   command, so running this at load is a guaranteed FAIL.
                   Close accepts blank context percents and fails one outside 0-100.
                   A non-spike close also requires manifest.verify.repos.<repo>
                   (Set-VerifyReceipt.ps1) with boolean pass true for each local
                   affected repo; when the receipt recorded its work and the repo path
                   exists, that work must still be there (same rule as the review
                   stamp below), so tests taken before a later fix fail. Each of
                   those repos also needs a reviewReady
                   entry (Set-ReviewReady.ps1) with verdict Ready, Ready with fixes, or
                   No change. When the repo path exists, the reviewed work must still be
                   there: the staged diff, or the first-parent commits since the stamp's
                   headSha (a later merge of the base branch is ignored; any other new
                   commit fails). A spike skips both.
                   stackSmoke stays optional unless an affected repo has profile layer
                   frontend. Then close fails unless the effective status is passed
                   (current work, user confirmed). A spike skips that check.

    Session timestamps live in the manifest. The retired WI<n>-session.json is still
    accepted as a fallback so tickets started before that change can close.

    Exit code 0 = pass, 1 = fail.

.PARAMETER Ticket
    Work item, with or without the ticket prefix (TICKET-42 or 42).

.PARAMETER Phase
    start | implement | prepush | close

    prepush runs the work checks of close (verify receipts, review stamps with no open
    Blocker/Major, frontend Drive) and nothing that is written at close (timestamps,
    ledger, context). prep-pr runs it before any commit, and the push gate runs it before
    a <ticket> product branch is pushed, so unreviewed or untested work never leaves the machine.

.PARAMETER Json
    Emit { phase, ticket, mode, pass, missing[], found[] } instead of human-readable lines.

.EXAMPLE
    .\Assert-TicketArtifacts.ps1 -Ticket TICKET-42 -Phase start

.EXAMPLE
    .\Assert-TicketArtifacts.ps1 -Ticket 22132 -Phase implement -Json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Ticket,

    [Parameter(Mandatory)]
    [ValidateSet('start', 'implement', 'prepush', 'close')]
    [string]$Phase,

    # Override the repo root (for testing against fixtures).
    [string]$Root,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/ManifestFields.ps1')
$script:ResolvedRepoPathsCache = $null
$script:ResolveError = $null
$script:LocalFalseRepos = @{}

# Read ticket prefix from profile.json. This script does not dot-source _ServiceLauncherLib.ps1.
$_prefix = Get-TicketPrefix   # lib/TicketPrefix.ps1, via ManifestFields.ps1

$digits = $Ticket -replace '[^\d]', ''
if (-not $digits) { throw "Could not read a work item number from '$Ticket'." }
# Honor an explicit prefix on the argument (CI fixtures are WI00001 even when
# profile.ticketPrefix is TICKET-). Bare digits use the profile prefix.
if ($Ticket -match '^(?<pre>[A-Za-z]+-?)\d') {
    $Key = $Matches['pre'] + $digits
} else {
    $Key = $_prefix + $digits
}
$RepoRoot = if ($Root) { $Root } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
$PlansDir = Join-Path $RepoRoot 'plans'
if (-not $Root -and (Get-Command Resolve-AgenticApp -ErrorAction SilentlyContinue)) {
    $app = Resolve-AgenticApp -HostRoot $RepoRoot
    if ($app.Id) { $PlansDir = $app.PlansDir }
}
$ScratchDir = Join-Path (Join-Path $RepoRoot 'tmp') 'tickets'

$missing = [System.Collections.Generic.List[string]]::new()
$found = [System.Collections.Generic.List[string]]::new()

function Test-Artifact {
    param([string]$Name, [string]$Why)

    $path = Join-Path $PlansDir $Name
    if (Test-Path -LiteralPath $path) {
        $found.Add($Name)
        return $true
    }
    $missing.Add("$Name -- $Why")
    return $false
}

# The plan file is named from the manifest workType, and the mode decides which
# artifacts apply at all, so resolve the manifest first.
$manifest = $null
$workType = $null
$mode = $null
$manifestPath = Join-Path $PlansDir "$Key-manifest.json"
if (Test-Path -LiteralPath $manifestPath) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $names = $manifest.PSObject.Properties.Name
        if ($names -contains 'workType') { $workType = $manifest.workType }
        if ($names -contains 'mode') { $mode = $manifest.mode }
    }
    catch {
        $missing.Add("$Key-manifest.json -- present but not valid JSON: $($_.Exception.Message)")
    }
}

function Get-ManifestField {
    param([string]$Name)
    if (-not $manifest) { return $null }
    if (-not ($manifest.PSObject.Properties.Name -contains $Name)) { return $null }
    return $manifest.$Name
}

function Get-HeadingBody {
    param([string]$Content, [string]$HeadingRegex)
    $lines = $Content -split "\r?\n"
    $idx = -1
    $level = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $HeadingRegex) {
            $idx = $i
            $level = $Matches[1].Length
            break
        }
    }
    if ($idx -lt 0) { return '' }
    $end = $lines.Count
    for ($i = $idx + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*(#{1,6})\s') {
            if ($Matches[1].Length -le $level) { $end = $i; break }
        }
    }
    if ($end -le $idx + 1) { return '' }
    return ($lines[($idx + 1)..($end - 1)] -join "`n")
}

function Test-PriorLessonCites {
    param([string]$PlanName, [string]$Content)
    $raw = Get-ManifestField 'priorFindings'
    if (-not $raw) { return $true }
    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($f in @($raw)) {
        if (-not $f) { continue }
        $id = $null
        if ($f -is [string]) { $id = $f.Trim() }
        elseif (($f.PSObject.Properties.Name -contains 'ticket') -and $f.ticket) { $id = ([string]$f.ticket).Trim() }
        if ($id) { [void]$ids.Add($id) }
    }
    if ($ids.Count -eq 0) { return $true }
    $body = Get-HeadingBody -Content $Content -HeadingRegex '(?i)^\s*(#{1,4})\s*(\d+[a-z]?\.?\s*)?Engineering Decisions\s*$'
    $absent = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $ids) {
        if ($body -notmatch [regex]::Escape($id)) { [void]$absent.Add($id) }
    }
    if ($absent.Count -eq 0) { return $true }
    $missing.Add("$PlanName -- Engineering Decisions does not cite priorFindings id(s): $($absent -join ', ') (name each id and what it changed, or 'lesson unchanged: <id> -- <why>')")
    return $false
}

function Test-PlanFile {
    # Prefer the workType-derived name; accept any WI<n>-*-plan.md so a spike/refactor
    # naming variation does not produce a false failure.
    param([switch]$CheckDigest)

    $expected = if ($workType) { "$Key-$workType-plan.md" } else { "$Key-<type>-plan.md" }
    $planFiles = @(Get-ChildItem -LiteralPath $PlansDir -Filter "$Key-*-plan.md" -File -ErrorAction SilentlyContinue)
    if ($planFiles.Count -eq 0) {
        $missing.Add("$expected -- approved plan; implement has nothing to follow without it")
        return
    }
    $planFile = $planFiles[0]

    # Digest presence is only checked when start-ticket verifies its own output (-Phase
    # start). implement/close load whatever plan already exists -- a plan approved before
    # this requirement existed must not retroactively fail those phases.
    if ($CheckDigest) {
        $content = Get-Content -LiteralPath $planFile.FullName -Raw -Encoding UTF8
        if ($content -notmatch '(?im)^\s*#{1,3}\s*Plan Digest\s*$') {
            $missing.Add("$($planFile.Name) -- missing '## Plan Digest' heading (see ticket-plan-output.md)")
            return
        }
        # Engineering Decisions is required before the Work Plan. 'None — <why>' is a
        # valid section; an absent section means the calls were never made explicit.
        if ($content -notmatch '(?im)^\s*#{1,4}\s*(\d+[a-z]?\.?\s*)?Engineering Decisions\s*$') {
            $missing.Add("$($planFile.Name) -- missing 'Engineering Decisions' heading (see engineering-decisions.md; 'None -- <why>' is valid)")
            return
        }
        # An unresolved placeholder is the thing the section exists to prevent: the
        # plan shipped with the call deferred to implementation instead of asked.
        if ($content -match '(?im)\bTBD\b') {
            $missing.Add("$($planFile.Name) -- contains 'TBD'; resolve the open decision or ask the user, do not persist a placeholder")
            return
        }
        if ($content -match '(?im)resolve[d]?\s+during\s+implement') {
            $missing.Add("$($planFile.Name) -- contains 'resolve during implement'; decide it now or ask the user")
            return
        }

        # Work Plan section: heading, numbered steps, difficulty tags, and (for any
        # [high] step) an architect result recorded in Engineering Decisions. This is
        # the model-usage.md/ticket-plan-output.md contract, checked mechanically.
        $planLines = $content -split "\r?\n"
        $workPlanHeadingPattern = '(?i)^\s*#{1,4}\s*(\d+[a-z]?\.?\s*)?Work plan\s*$'
        $workPlanIdx = -1
        for ($li = 0; $li -lt $planLines.Count; $li++) {
            if ($planLines[$li] -match $workPlanHeadingPattern) { $workPlanIdx = $li; break }
        }
        if ($workPlanIdx -lt 0) {
            $missing.Add("$($planFile.Name) -- missing 'Work Plan' heading (see ticket-plan-output.md)")
            return
        }

        # The section ends at the next heading of the same or a higher level, so steps grouped
        # under ### subheadings inside "## Work Plan" still count.
        $workPlanLevel = ([regex]::Match($planLines[$workPlanIdx], '#+')).Length
        $workPlanEndIdx = $planLines.Count
        for ($li = $workPlanIdx + 1; $li -lt $planLines.Count; $li++) {
            if ($planLines[$li] -match '^\s*(#{1,4})\s' -and $Matches[1].Length -le $workPlanLevel) { $workPlanEndIdx = $li; break }
        }
        $workPlanSection = if ($workPlanEndIdx -gt $workPlanIdx + 1) { $planLines[($workPlanIdx + 1)..($workPlanEndIdx - 1)] } else { @() }

        # Step lines are column-0 numbered lines only; indented sub-lists are notes,
        # not steps, and are not required to carry a tag.
        $stepLines = @($workPlanSection | Where-Object { $_ -match '^\d+\.\s' })
        if ($stepLines.Count -eq 0) {
            $missing.Add("$($planFile.Name) -- 'Work Plan' has no numbered steps")
            return
        }

        $tagPattern = '(?i)^\d+\.\s*[*`_]*\[(low|med|high)\]'
        $untaggedSteps = [System.Collections.Generic.List[string]]::new()
        $hasHighStep = $false
        foreach ($stepLine in $stepLines) {
            if ($stepLine -match $tagPattern) {
                if ($Matches[1] -match '(?i)^high$') { $hasHighStep = $true }
            }
            elseif ($stepLine -match '^(?<n>\d+)\.') {
                $untaggedSteps.Add($Matches['n'])
            }
        }
        if ($untaggedSteps.Count -gt 0) {
            $missing.Add("$($planFile.Name) -- Work Plan step(s) $($untaggedSteps -join ', ') missing a [low]|[med]|[high] tag (see ticket-plan-output.md)")
            return
        }

        # A bug plan is RED first (bug-fix.md section 5): its first step writes or runs the
        # failing test, or says why there can be none. Checked at start only, like the digest,
        # so a plan approved before this rule does not fail implement or close.
        if ($CheckDigest -and $workType -eq 'bug') {
            $first = $stepLines[0]
            $red = ($first -replace '(?i)no-test:.*$', '') -match '(?i)\b(test|tests|spec|red|repro|reproduce|regression|characteri[sz]ation)\b'
            $waived = $first -match '(?i)no-test:\s*\S.{9,}'
            if (-not $red -and -not $waived) {
                $missing.Add("$($planFile.Name) -- a bug plan's first Work Plan step must be RED (write or run the failing test) or say 'no-test: <reason>' (see skills/start-ticket/references/bug-fix.md section 5)")
                return
            }
        }

        if ($hasHighStep) {
            $edHeadingPattern = '(?i)^\s*(#{1,4})\s*(\d+[a-z]?\.?\s*)?Engineering Decisions\s*$'
            $edIdx = -1
            $edLevel = 0
            for ($li = 0; $li -lt $planLines.Count; $li++) {
                if ($planLines[$li] -match $edHeadingPattern) {
                    $edIdx = $li
                    $edLevel = $Matches[1].Length
                    break
                }
            }
            $edEndIdx = $planLines.Count
            if ($edIdx -ge 0) {
                for ($li = $edIdx + 1; $li -lt $planLines.Count; $li++) {
                    if ($planLines[$li] -match '^\s*(#{1,6})\s') {
                        if ($Matches[1].Length -le $edLevel) { $edEndIdx = $li; break }
                    }
                }
            }
            $edSection = if ($edIdx -ge 0 -and $edEndIdx -gt $edIdx + 1) { ($planLines[($edIdx + 1)..($edEndIdx - 1)] -join "`n") } else { '' }
            if ($edSection -notmatch '(?i)\barchitect') {
                $missing.Add("$($planFile.Name) -- has a [high] step but Engineering Decisions records no architect result or 'architect skipped: <reason>' (see skills/architect)")
                return
            }
        }
        if (-not (Test-PriorLessonCites -PlanName $planFile.Name -Content $content)) { return }
    }
    $found.Add($planFile.Name)
}

# Existence and mode in one entry, so a pass reports one line per artifact.
function Test-ManifestSchema {
    if (-not $manifestPath -or -not (Test-Path -LiteralPath $manifestPath)) { return }
    $schemaPath = Join-Path $PSScriptRoot 'manifest.schema.json'
    $raw = Get-Content -LiteralPath $manifestPath -Raw
    $schemaOk = $true
    $schemaError = $null
    try {
        $schemaOk = Test-Json -Json $raw -SchemaFile $schemaPath
    }
    catch {
        $schemaOk = $false
        $schemaError = $_.Exception.Message
    }
    if (-not $schemaOk) {
        if (-not $schemaError) { $schemaError = 'does not match manifest.schema.json' }
        $missing.Add("$Key-manifest.json -- schema: $schemaError")
    }
    else {
        $found.Add("$Key-manifest.json (schema)")
    }
    if ($workType -ne 'spike') { return }
    $plan = Get-ManifestField 'parallelPlan'
    if (-not $plan) { return }
    foreach ($slot in @('scope', 'branchSetup', 'verify', 'review')) {
        $names = @($plan.PSObject.Properties.Name)
        if ($names -contains $slot -and @($plan.$slot).Count -gt 0) {
            $missing.Add("$Key-manifest.json -- spike parallelPlan.$slot must be empty")
        }
    }
}

function Test-Manifest {
    param([string]$Why)

    if (-not (Test-Path -LiteralPath $manifestPath)) {
        $missing.Add("$Key-manifest.json -- $Why")
        return
    }
    if ($mode -in @('branch', 'worktree', 'investigate')) {
        $found.Add("$Key-manifest.json (mode: $mode)")
        return
    }
    if ($null -eq $mode) {
        $missing.Add("$Key-manifest.json -- no 'mode' field; must be 'branch', 'worktree', or 'investigate'")
        return
    }
    $missing.Add("$Key-manifest.json -- mode '$mode' is not 'branch', 'worktree', or 'investigate'")
}

<#
    Session timestamps moved from WI<n>-session.json into the manifest. Read the
    manifest first and fall back to the retired file, so a ticket started before
    the change can still close.
#>
function Get-SessionSource {
    $names = @()
    if ($manifest) { $names = $manifest.PSObject.Properties.Name }
    foreach ($field in @('startedAtUtc', 'completedAtUtc', 'reopenedAtUtc', 'reclosedAtUtc')) {
        if ($names -contains $field) {
            return [pscustomobject]@{ Data = $manifest; Label = "$Key-manifest.json" }
        }
    }

    $legacy = Join-Path $PlansDir "$Key-session.json"
    if (Test-Path -LiteralPath $legacy) {
        try {
            return [pscustomobject]@{
                Data  = (Get-Content -LiteralPath $legacy -Raw | ConvertFrom-Json)
                Label = "$Key-session.json (legacy)"
            }
        }
        catch {
            $missing.Add("$Key-session.json -- present but not valid JSON: $($_.Exception.Message)")
            return $null
        }
    }
    return $null
}

function Test-TimestampField {
    param([string[]]$Fields, [string]$Why)

    $src = Get-SessionSource
    if (-not $src) {
        $missing.Add("$Key-manifest.json -- $Why")
        return
    }
    $names = $src.Data.PSObject.Properties.Name
    $set = @($Fields | Where-Object {
        ($names -contains $_) -and -not [string]::IsNullOrWhiteSpace([string]$src.Data.$_)
    })
    if ($set.Count) {
        $found.Add("$($src.Label) ($($set -join ', '))")
    }
    else {
        $missing.Add("$($src.Label) -- $Why")
    }
}

<#
    The cached ticket fetch is scratch, not durable config, so it lives in
    tmp/tickets/. The old plans/ location is still accepted for in-flight tickets.
#>
function Test-WorkItemCache {
    $name = "$Key-workitem.json"
    foreach ($dir in @($ScratchDir, $PlansDir)) {
        $path = Join-Path $dir $name
        if (Test-Path -LiteralPath $path) {
            $found.Add((Join-Path (Split-Path $dir -Leaf) $name))
            return
        }
    }
    $missing.Add("tmp/tickets/$name -- cached ticket fetch; later chats reload it instead of re-fetching")
}

<#
    When profile.adrIndex is set, the manifest must carry it so the plan can cite it.
#>
function Test-AdrIndex {
    if (-not $manifest) { return }
    $profileAdr = $null
    $profilePath = Join-Path $Root 'profile.json'
    if (Test-Path -LiteralPath $profilePath) {
        try {
            $prof = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
            if ($prof.PSObject.Properties.Name -contains 'adrIndex') { $profileAdr = [string]$prof.adrIndex }
        } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($profileAdr)) { return }
    $repos = @()
    foreach ($entry in @(Get-ManifestField 'affectedRepos')) {
        if (-not $entry) { continue }
        if ($entry -is [string]) { $repos += $entry; continue }
        if ($entry.PSObject.Properties.Name -contains 'repo') { $repos += $entry.repo }
    }
    if (-not $repos.Count) { return }
    $adr = Get-ManifestField 'adrIndex'
    if ([string]::IsNullOrWhiteSpace([string]$adr)) {
        $missing.Add("$Key-manifest.json -- profile.adrIndex is set, so the manifest adrIndex must be set (see _shared/adr-policy.md)")
        return
    }
    $found.Add("$Key-manifest.json (adrIndex)")
}

<#
    Replaces the per-ticket WI<n>-closeout.md check. A full closeout page is now
    written only when the retrospective earns one, but every closed ticket must
    leave exactly one ledger row -- written by scripts/ticket/Update-TicketLedger.ps1.
#>
# Context percents are optional: a measured value, or blank. A blank is honest; an
# invented number is not, so only a present-but-malformed value fails.
function Test-CtxNumber {
    param($Ctx, [string]$Name, [string]$Why)
    if (-not ($Ctx -and ($Ctx.PSObject.Properties.Name -contains $Name)) -or $null -eq $Ctx.$Name) {
        $found.Add("$Key-manifest.json (ctxPct.$Name not recorded)")
        return
    }
    $raw = [string]$Ctx.$Name
    if ($raw -match '^\d+$' -and [int]$raw -le 100) { $found.Add("$Key-manifest.json (ctxPct.$Name)") }
    else { $missing.Add("$Key-manifest.json -- $Why") }
}

function Test-CloseContext {
    $ctx = $null
    if ($manifest -and ($manifest.PSObject.Properties.Name -contains 'ctxPct')) {
        $ctx = $manifest.ctxPct
    }
    foreach ($name in @('start', 'review', 'close')) {
        Test-CtxNumber -Ctx $ctx -Name $name -Why "ctxPct.$name must be 0-100 when present. Re-run Set-TicketCtxPct.ps1 -Phase $name without -Percent to use the measured value."
    }
}

function Get-CloseRepoNames {
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @(Get-ManifestField 'affectedRepos')) {
        if (-not $entry) { continue }
        if ($entry -is [string]) {
            $list.Add([pscustomobject]@{ repo = [string]$entry; path = $null })
            continue
        }
        $props = @($entry.PSObject.Properties.Name)
        if ($props -notcontains 'repo') { continue }
        $name = [string]$entry.repo
        if (-not $name) { continue }
        if (($props -contains 'local') -and ($null -ne $entry.local) -and -not [bool]$entry.local) {
            $skipPath = if (($props -contains 'path') -and $entry.path) { [string]$entry.path } else { $null }
            $script:LocalFalseRepos[$name] = $skipPath
            continue
        }
        $path = $null
        if (($props -contains 'path') -and $entry.path) { $path = [string]$entry.path }
        $list.Add([pscustomobject]@{ repo = $name; path = $path })
    }
    return @($list)
}

# Real closes resolve repo paths. Fixture runs pass -Root and only compare when the
# manifest entry itself names a path, so a missing checkout stays a JSON check.
function Get-ResolvedRepoPaths {
    if ($null -ne $script:ResolvedRepoPathsCache) { return $script:ResolvedRepoPathsCache }
    $map = @{}
    $script:ResolvedRepoPathsCache = $map
    if ($Root) { return $map }
    $resolveScript = Join-Path $PSScriptRoot 'Resolve-TicketRoot.ps1'
    if (-not (Test-Path -LiteralPath $resolveScript)) { return $map }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $json = & $resolveScript -Ticket $Key -Json 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $json) {
            $script:ResolveError = "Resolve-TicketRoot.ps1 -Ticket $Key exited $LASTEXITCODE"
            return $map
        }
        $resolved = $json | ConvertFrom-Json
        foreach ($r in @($resolved.repos)) {
            if (-not $r) { continue }
            $names = @($r.PSObject.Properties.Name)
            $exists = ($names -contains 'exists') -and [bool]$r.exists
            if ($exists -and $r.path) { $map[[string]$r.repo] = [string]$r.path }
        }
    }
    catch {
        # A failed lookup used to leave every repo as a JSON-only check. Close says so now.
        $script:ResolveError = "Resolve-TicketRoot.ps1 failed: $($_.Exception.Message)"
    }
    finally { $ErrorActionPreference = $prev }
    return $map
}

function Get-ProfileJson {
    $profilePath = Join-Path $RepoRoot 'profile.json'
    if (-not (Test-Path -LiteralPath $profilePath)) { return $null }
    try { return (Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-TicketBaseBranch {
    $base = Get-ManifestField 'baseBranch'
    if ($base) { return [string]$base }
    $prof = Get-ProfileJson
    if ($prof -and ($prof.PSObject.Properties.Name -contains 'baseBranchDefault') -and $prof.baseBranchDefault) {
        return [string]$prof.baseBranchDefault
    }
    return 'main'
}

# Files this ticket changed in one repo: everything since the merge-base with the base
# branch (origin/<base> first), plus staged, unstaged, and untracked files. $null when no
# base resolves -- callers then keep their older, weaker check instead of guessing.
function Get-WorkChangedFiles {
    param([Parameter(Mandatory)][string]$RepoPath)
    $base = Get-TicketBaseBranch
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $ref = $null
        foreach ($candidate in @("origin/$base", $base)) {
            & git -C $RepoPath rev-parse --verify --quiet "$candidate^{commit}" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $ref = $candidate; break }
        }
        if (-not $ref) { return $null }
        $mb = (& git -C $RepoPath merge-base $ref HEAD 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -ne 0 -or -not $mb) { return $null }
        $files = @(& git -C $RepoPath diff --name-only $mb 2>$null) + @(& git -C $RepoPath ls-files --others --exclude-standard 2>$null)
        return ,@($files | Where-Object { $_ } | ForEach-Object { $_ -replace '\\', '/' } | Sort-Object -Unique)
    }
    finally { $ErrorActionPreference = $prev }
}

function Test-DocsOnlyPath {
    param([string]$Path)
    foreach ($g in @('*.md', '*.markdown', '*.txt', 'docs/*', '*/docs/*')) { if ($Path -like $g) { return $true } }
    return $false
}

# A spike skips verify, review, and the Drive. That is right for an investigation and an
# escape hatch for anything else, so the tracker's item type (manifest ticket.adoType) has to agree.
function Test-SpikeClassification {
    $ticket = Get-ManifestField 'ticket'
    $adoType = if ($ticket -and ($ticket.PSObject.Properties.Name -contains 'adoType')) { [string]$ticket.adoType } else { '' }
    if ($adoType -in @('Bug', 'Issue', 'User Story', 'Product Backlog Item', 'Feature')) {
        $missing.Add("$Key-manifest.json -- workType is spike but the work item is a $adoType; a spike skips verify, review, and the Drive. Re-run the router or set workType to match.")
    }
}

# local:false means "not cloned here", so close skips the repo. A repo that is checked out
# after all must be verified and reviewed like the rest.
function Test-LocalFalseRepos {
    $resolved = Get-ResolvedRepoPaths
    foreach ($name in @($script:LocalFalseRepos.Keys)) {
        $path = $script:LocalFalseRepos[$name]
        if (-not $path -and $resolved.ContainsKey($name)) { $path = $resolved[$name] }
        if ($path -and (Test-Path -LiteralPath $path)) {
            $missing.Add("$Key-manifest.json -- affectedRepos.$name is local:false but it is checked out at $path; set local:true so close verifies and reviews it")
        }
    }
}

function Test-VerifyReceipt {
    $label = "$Key-manifest.json -- verify"
    $repos = $null
    if ($manifest -and ($manifest.PSObject.Properties.Name -contains 'verify') -and $manifest.verify -and
        ($manifest.verify.PSObject.Properties.Name -contains 'repos')) {
        $repos = $manifest.verify.repos
    }
    if (-not $repos) {
        $missing.Add("$label -- no verify results; run Set-VerifyReceipt.ps1 per repo after verify-repo")
        return
    }
    $resolved = Get-ResolvedRepoPaths
    foreach ($repo in @(Get-CloseRepoNames)) {
        $entry = $null
        if ($repos.PSObject.Properties.Name -contains $repo.repo) { $entry = $repos.($repo.repo) }
        if (-not $entry) {
            $missing.Add("$label.repos.$($repo.repo) -- missing; run Set-VerifyReceipt.ps1")
            continue
        }
        $names = @($entry.PSObject.Properties.Name)
        # A JSON string "false" is truthy in PowerShell, so only a real boolean counts.
        if (-not (($names -contains 'pass') -and ($entry.pass -is [bool]) -and $entry.pass)) {
            $missing.Add("$label.repos.$($repo.repo).pass must be boolean true")
            continue
        }
        $path = $repo.path
        if (-not $path -and $resolved.ContainsKey($repo.repo)) { $path = $resolved[$repo.repo] }
        $hasCheckout = $path -and (Test-Path -LiteralPath $path)
        if (($names -contains 'tests') -and ([string]$entry.tests -eq 'not-run')) {
            $why = if ($names -contains 'reason') { [string]$entry.reason } else { '' }
            # "Not run" is honest only when there was nothing to test: a docs-only change.
            if ($hasCheckout) {
                $changedFiles = Get-WorkChangedFiles -RepoPath $path
                $code = @($changedFiles | Where-Object { $_ -and -not (Test-DocsOnlyPath $_) })
                if ($null -ne $changedFiles -and $code.Count) {
                    $shown = ($code | Select-Object -First 3) -join ', '
                    $missing.Add("$label.repos.$($repo.repo) -- tests not run ($why) but the change touches code ($shown); run verify-repo, then Set-VerifyReceipt.ps1")
                    continue
                }
            }
            $found.Add("$Key-manifest.json (verify.repos.$($repo.repo): tests not run: $why)")
            continue
        }
        # Receipts written with evidenceVersion must carry a hashed evidence file. Older receipts
        # (no evidenceVersion) stay a JSON check.
        if (($names -contains 'tests') -and ([string]$entry.tests -eq 'pass') -and ($names -contains 'evidenceVersion')) {
            $ev = if ($names -contains 'evidence') { $entry.evidence } else { $null }
            $evShaOk = $ev -and ($ev.PSObject.Properties.Name -contains 'sha256') -and ([string]$ev.sha256 -match '^[0-9a-fA-F]{64}$')
            if (-not $evShaOk) {
                $missing.Add("$label.repos.$($repo.repo) -- evidence missing; re-run Set-VerifyReceipt.ps1 with -Evidence <.trx or log>")
                continue
            }
            $evPath = if ($ev.PSObject.Properties.Name -contains 'path') { [string]$ev.path } else { '' }
            $evFull = $null
            if ($evPath) {
                if ([System.IO.Path]::IsPathRooted($evPath)) { $evFull = $evPath }
                elseif ($evPath -match '^plans[/\\]evidence[/\\]') { $evFull = Join-Path (Split-Path $PlansDir -Parent) $evPath }   # beside the manifest: host root, or apps/<id> when an app is active
                elseif ($hasCheckout) { $evFull = Join-Path $path $evPath }
            }
            if ($evFull -and (Test-Path -LiteralPath $evFull -PathType Leaf)) {
                $nowSha = (Get-FileHash -LiteralPath $evFull -Algorithm SHA256).Hash
                if ($nowSha -ne ([string]$ev.sha256).ToUpperInvariant()) {
                    $missing.Add("$label.repos.$($repo.repo) -- evidence file changed since the receipt ($evPath); re-run Set-VerifyReceipt.ps1 with -Evidence <.trx or log>")
                    continue
                }
            }
        }
        # The receipt must describe the work that ships: same check as the review stamp.
        # A receipt with no recorded work (no mode, from before receipts recorded it) stays a
        # JSON check. On a real close a repo with no checkout fails: mark it local:false.
        if (-not (Get-StampEntryValue $entry 'mode')) {
            $found.Add("$Key-manifest.json (verify.repos.$($repo.repo): pass)")
            continue
        }
        if (-not $hasCheckout) {
            if ($Root) { $found.Add("$Key-manifest.json (verify.repos.$($repo.repo): pass)"); continue }
            $missing.Add("$label.repos.$($repo.repo) -- no checkout found for $($repo.repo), so the receipt cannot be checked against the work; check the path, or set affectedRepos local:false if it is not cloned here")
            continue
        }
        $check = Test-ReviewedWorkPresent -RepoPath $path -Entry $entry
        if (-not $check.ok) {
            $missing.Add("$label.repos.$($repo.repo) -- tests ran on older work ($($check.reason)); re-run verify-repo, then Set-VerifyReceipt.ps1")
            continue
        }
        $found.Add("$Key-manifest.json (verify.repos.$($repo.repo): pass, $($check.reason))")
    }
}

function Test-ReviewFingerprints {
    $repos = @(Get-CloseRepoNames)
    $resolved = Get-ResolvedRepoPaths
    $stampRepos = $null
    $stampMode = 'staged'
    if ($manifest -and ($manifest.PSObject.Properties.Name -contains 'reviewReady') -and $manifest.reviewReady) {
        $stamp = $manifest.reviewReady
        if ($stamp.PSObject.Properties.Name -contains 'repos') { $stampRepos = $stamp.repos }
        if (($stamp.PSObject.Properties.Name -contains 'mode') -and $stamp.mode) { $stampMode = [string]$stamp.mode }
    }
    foreach ($repo in $repos) {
        $label = "$Key-manifest.json -- reviewReady.repos.$($repo.repo)"
        $entry = $null
        if ($stampRepos -and ($stampRepos.PSObject.Properties.Name -contains $repo.repo)) {
            $entry = $stampRepos.($repo.repo)
        }
        if (-not $entry) {
            $missing.Add("$label -- no review stamp; run Set-ReviewReady.ps1 after review-diff")
            continue
        }
        $verdict = Get-StampEntryValue $entry 'verdict'
        if (-not (Test-ReviewVerdict $verdict)) {
            $missing.Add("$label.verdict is '$verdict' -- needs Ready, Ready with fixes, or No change")
            continue
        }
        # Ready with fixes means Minor/Nit work is left. A recorded Major (or Blocker) means
        # the reviewed work is not done: fix it, then re-run /review-changes so a new stamp
        # covers the fixed work (severity-and-output.md, Verdict rules).
        $entryFindings = @(if ($entry.PSObject.Properties.Name -contains 'findings') { $entry.findings })
        $open = Get-FindingCounts $entryFindings
        if ($open.Blocker -or $open.Major) {
            $missing.Add("$label has $($open.Blocker) Blocker and $($open.Major) Major finding(s) open -- fix them, then re-run /review-changes so the stamp covers the fixed work")
            continue
        }
        $mode = Get-StampEntryValue $entry 'mode'
        if (-not $mode) { $mode = $stampMode }
        $noChange = ($verdict.Replace('*', '').Trim() -eq 'No change')
        if ($noChange -or $mode -eq 'pre-merge') {
            if ((Get-StampEntryValue $entry 'headSha') -notmatch '^[0-9a-fA-F]{40}$') {
                $missing.Add("$label.headSha must name the reviewed commit")
                continue
            }
        } else {
            $fpNorm = (Get-StampEntryValue $entry 'fingerprint').ToLowerInvariant()
            if ($fpNorm -notmatch '^[0-9a-f]{64}$' -or $fpNorm -eq $script:EmptyDiffFingerprint) {
                $missing.Add("$label.fingerprint must be a non-empty review hash")
                continue
            }
        }
        $path = $repo.path
        if (-not $path -and $resolved.ContainsKey($repo.repo)) { $path = $resolved[$repo.repo] }
        if (-not $path -or -not (Test-Path -LiteralPath $path)) {
            # Fixture runs (-Root) stay a JSON check; a real close needs the checkout to
            # prove the reviewed work is what ships.
            if ($Root) { $found.Add("$Key-manifest.json (reviewReady.repos.$($repo.repo): $verdict)"); continue }
            $missing.Add("$label -- no checkout found for $($repo.repo), so the stamp cannot be checked against the work; check the path, or set affectedRepos local:false if it is not cloned here")
            continue
        }
        $check = Test-ReviewedWorkPresent -RepoPath $path -Entry $entry -StampMode $stampMode
        if (-not $check.ok) {
            $missing.Add("$label -- $($check.reason); re-review, then Set-ReviewReady.ps1")
            continue
        }
        $found.Add("$Key-manifest.json (reviewReady.repos.$($repo.repo): $verdict, $($check.reason))")
    }
}

function Get-FrontendRepoNames {
    $names = [System.Collections.Generic.List[string]]::new()
    $profilePath = Join-Path $RepoRoot 'profile.json'
    if (-not (Test-Path -LiteralPath $profilePath)) { return @() }
    try {
        $stackProfile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch { return @() }
    if (-not ($stackProfile.PSObject.Properties.Name -contains 'repos') -or -not $stackProfile.repos) { return @() }
    foreach ($repo in @($stackProfile.repos)) {
        if (-not $repo) { continue }
        $props = @($repo.PSObject.Properties.Name)
        if (($props -notcontains 'name') -or ($props -notcontains 'layers') -or -not $repo.name) { continue }
        $layers = @($repo.layers | ForEach-Object { [string]$_ })
        if ($layers -contains 'frontend') { [void]$names.Add([string]$repo.name) }
    }
    return @($names)
}

function Test-UiEvidence {
    $frontend = @(Get-FrontendRepoNames)
    if ($frontend.Count -eq 0) { return }
    $hit = @(Get-CloseRepoNames | Where-Object { $frontend -contains $_.repo } | ForEach-Object { $_.repo })
    if ($hit.Count -eq 0) { return }
    $stamp = $null
    if ($manifest -and ($manifest.PSObject.Properties.Name -contains 'stackSmoke')) { $stamp = $manifest.stackSmoke }
    $paths = @{}
    foreach ($repo in @(Get-CloseRepoNames)) {
        if ($repo.path) { $paths[$repo.repo] = $repo.path }
    }
    $resolved = Get-ResolvedRepoPaths
    foreach ($name in $hit) {
        if ((-not $paths.ContainsKey($name)) -and $resolved.ContainsKey($name)) { $paths[$name] = $resolved[$name] }
    }
    # The Drive is for UI changes, not for every change in a repo that has a UI: a
    # backend-only fix in a repo that also serves pages has nothing to Drive. profile.uiGlobs
    # names the UI file types; a repo whose changed files match none of them is exempt.
    # With no uiGlobs, or no base to diff against, the repo still needs the Drive.
    $prof = Get-ProfileJson
    $uiGlobs = @(if ($prof -and ($prof.PSObject.Properties.Name -contains 'uiGlobs')) { $prof.uiGlobs })
    if ($uiGlobs.Count) {
        $exempt = @()
        foreach ($name in $hit) {
            if (-not $paths.ContainsKey($name) -or -not (Test-Path -LiteralPath $paths[$name])) { continue }
            $changedFiles = Get-WorkChangedFiles -RepoPath $paths[$name]
            if ($null -eq $changedFiles) { continue }
            $ui = @($changedFiles | Where-Object { $f = $_; @($uiGlobs | Where-Object { $f -like $_ }).Count })
            if (-not $ui.Count) { $exempt += $name }
        }
        if ($exempt.Count) {
            $found.Add("$Key-manifest.json (stackSmoke not required: no UI files changed in $($exempt -join ', '))")
            $hit = @($hit | Where-Object { $exempt -notcontains $_ })
            if (-not $hit.Count) { return }
        }
    }
    $decision = Get-StackSmokeDecision -Stamp $stamp -RepoPaths $paths
    if ($decision.effective -eq 'passed') {
        $found.Add("$Key-manifest.json (stackSmoke: Tested, $($hit -join ', '))")
        return
    }
    $missing.Add("$Key-manifest.json -- frontend repo(s) $($hit -join ', ') need a current passed stackSmoke stamp (Drive the changed flow, then Set-StackSmoke.ps1 -Status passed after the user confirms). Effective: $($decision.effective).")
}

function Test-CloseWork {
    if ($workType -eq 'spike') { Test-SpikeClassification; return }
    $null = Get-CloseRepoNames   # records local:false entries
    $null = Get-ResolvedRepoPaths
    if (-not $Root -and $script:ResolveError) {
        $missing.Add("repo paths -- $($script:ResolveError); close cannot compare receipts and stamps with the work. Fix Resolve-TicketRoot, then re-run.")
    }
    Test-LocalFalseRepos
    Test-VerifyReceipt
    Test-ReviewFingerprints
    Test-UiEvidence
}

function Test-LedgerRow {
    $ledger = Join-Path $PlansDir 'ticket-ledger.md'
    if (-not (Test-Path -LiteralPath $ledger)) {
        $missing.Add("plans/ticket-ledger.md -- run scripts/ticket/Update-TicketLedger.ps1 -Ticket $Key ...")
        return
    }
    $rows = @(Get-Content -LiteralPath $ledger | Where-Object { $_ -match "^\|\s*$Key\s*\|" })
    if ($rows.Count -eq 1) {
        $found.Add("plans/ticket-ledger.md ($Key row)")
    }
    elseif ($rows.Count -eq 0) {
        $missing.Add("plans/ticket-ledger.md -- no row for $Key; run scripts/ticket/Update-TicketLedger.ps1 -Ticket $Key ...")
    }
    else {
        $missing.Add("plans/ticket-ledger.md -- $($rows.Count) rows for $Key; expected exactly one")
    }
}

switch ($Phase) {
    'start' {
        Test-ManifestSchema
        Test-Manifest 'routing table for every later chat (must include ticket object with title/adoType/state/area/priority)'
        Test-AdrIndex
        Test-TimestampField -Fields @('startedAtUtc') -Why 'startedAtUtc is null or absent; complete-task cannot compute hours without it'
        Test-PlanFile -CheckDigest
    }
    'implement' {
        Test-Manifest 'run /start-ticket first, or re-run its router step'
        Test-PlanFile
    }
    'prepush' {
        Test-Artifact "$Key-manifest.json" 'drives verify/review fan-out' | Out-Null
        Test-CloseWork
    }
    'close' {
        Test-ManifestSchema
        Test-Artifact "$Key-manifest.json" 'drives verify/review fan-out' | Out-Null
        Test-TimestampField -Fields @('completedAtUtc', 'reclosedAtUtc') -Why 'no completedAtUtc or reclosedAtUtc set'
        Test-CloseContext
        Test-LedgerRow
        Test-CloseWork
    }
}

$pass = $missing.Count -eq 0

if ($Json) {
    [pscustomobject]@{
        phase   = $Phase
        ticket  = $Key
        mode    = $mode
        pass    = $pass
        missing = @($missing)
        found   = @($found)
    } | ConvertTo-Json -Depth 4
}
else {
    if ($pass) {
        Write-Host "[PASS] $Key $Phase artifacts complete ($($found.Count) checked)." -ForegroundColor Green
        foreach ($f in $found) { Write-Host "       $f" }
    }
    else {
        Write-Host "[FAIL] $Key $Phase is incomplete -- $($missing.Count) artifact(s) missing:" -ForegroundColor Red
        foreach ($m in $missing) { Write-Host "       $m" -ForegroundColor Red }
        Write-Host "       Contract: _shared/ticket-artifacts.md" -ForegroundColor DarkGray
    }
}

if (-not $pass) { exit 1 }
exit 0
