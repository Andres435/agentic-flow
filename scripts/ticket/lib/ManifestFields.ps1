#Requires -Version 7
<#
.SYNOPSIS
    Shared helpers for reviewReady stamps, staged fingerprints, ctxPct, and
    stackSmoke on a ticket manifest. Dot-sourced by Set-ReviewReady /
    Get-ReviewSkip / Set-TicketCtxPct / Set-StackSmoke / Get-StackSmoke.
    Do not run directly.
#>

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'TicketPrefix.ps1')
$script:AgenticAppResolver = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib/Resolve-AgenticApp.ps1'
if ((Test-Path -LiteralPath $script:AgenticAppResolver) -and -not (Get-Command Resolve-AgenticApp -ErrorAction SilentlyContinue)) {
    . $script:AgenticAppResolver
}
$ErrorActionPreference = 'Stop'

function Get-TicketKeyFromRaw {
    param([Parameter(Mandatory)][string]$Ticket)
    $digits = $Ticket -replace '[^\d]', ''
    if (-not $digits) { throw "Could not read a work item number from '$Ticket'." }
    if ($Ticket -match '^(?<pre>[A-Za-z]+-?)\d') { return $Matches['pre'] + $digits }
    return (Get-TicketPrefix) + $digits
}

# Open = never closed, or reopened and not yet re-closed (a reopen keeps completedAtUtc).
function Test-TicketManifestOpen {
    param($Manifest)
    $names = @($Manifest.PSObject.Properties.Name)
    $completed = ($names -contains 'completedAtUtc') -and $Manifest.completedAtUtc
    if (-not $completed) { return $true }
    $reopened = ($names -contains 'reopenedAtUtc') -and $Manifest.reopenedAtUtc
    $reclosed = ($names -contains 'reclosedAtUtc') -and $Manifest.reclosedAtUtc
    return [bool]($reopened -and -not $reclosed)
}

# Ticket keys from the current branch of each repo, for chats opened at the workspace root (no
# ticket folder in the path). A key whose manifest is open (no completedAtUtc) wins over a repo
# left on an old branch. Returns { ticket; candidates[]; reason }; ticket is $null when there is
# no candidate or more than one, and the caller asks.
function Get-TicketKeyFromBranches {
    param(
        [Parameter(Mandatory)][string[]]$RepoPaths,
        [Parameter(Mandatory)][string]$Prefix,
        [string]$PlansDir
    )
    $escaped = [regex]::Escape($Prefix)
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($path in $RepoPaths) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
        $branch = Get-GitDiffText -RepoPath $path -GitArgs @('branch', '--show-current')
        if (-not $branch) { continue }
        if ($branch.Trim() -match "(?i)(?:^|[/_-])$escaped(\d+)$") {
            $key = $Prefix + $Matches[1]
            if (-not $keys.Contains($key)) { [void]$keys.Add($key) }
        }
    }
    $open = @($keys | Where-Object {
        if (-not $PlansDir) { return $false }
        $file = Join-Path $PlansDir "$_-manifest.json"
        if (-not (Test-Path -LiteralPath $file)) { return $false }
        try { $m = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json } catch { return $false }
        Test-TicketManifestOpen $m
    })
    $pool = @(if ($open.Count -gt 0) { $open } else { $keys })
    $hasManifest = $PlansDir -and $pool.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $PlansDir "$($pool[0])-manifest.json"))
    # closed-manifest: the only branch belongs to a closed ticket; confirm with the user before using it.
    $reason = if ($pool.Count -eq 1) { if ($open.Count -gt 0) { 'open-manifest' } elseif ($hasManifest) { 'closed-manifest' } else { 'branch' } }
              elseif ($pool.Count -eq 0) { 'no-ticket-branch' } else { 'ambiguous' }
    return [pscustomobject]@{
        ticket     = if ($pool.Count -eq 1) { $pool[0] } else { $null }
        candidates = @($keys)
        reason     = $reason
    }
}

function Get-CursorRepoRoot {
    param([string]$FromScriptRoot)
    # scripts/ticket or scripts/ticket/lib → workflow repo root
    $dir = $FromScriptRoot
    if ((Split-Path $dir -Leaf) -eq 'lib') { $dir = Split-Path $dir -Parent }
    $parent = Split-Path $dir -Parent
    if ((Split-Path $parent -Leaf) -eq 'scripts') { return (Split-Path $parent -Parent) }
    return $parent
}

function Get-TicketManifestFile {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$TicketKey
    )
    $plans = Join-Path $RepoRoot 'plans'
    if (Get-Command Resolve-AgenticApp -ErrorAction SilentlyContinue) {
        $app = Resolve-AgenticApp -HostRoot $RepoRoot
        if ($app.Id) { $plans = $app.PlansDir }
    }
    return (Join-Path $plans "$TicketKey-manifest.json")
}

# SHA-256 of an empty string. A stamp carrying it reviewed nothing.
$script:EmptyDiffFingerprint = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'

function Get-DiffFingerprintFromText {
    param([AllowEmptyString()][string]$Diff)
    if ([string]::IsNullOrEmpty($Diff)) { return $null }
    $bytes = [Text.Encoding]::UTF8.GetBytes($Diff)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return (([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant())
    } finally {
        $sha.Dispose()
    }
}

# $null on a missing path or a git failure. An empty diff is '' so the caller can tell
# "nothing staged" apart from "git failed".
function Get-GitDiffText {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string[]]$GitArgs
    )
    if (-not (Test-Path -LiteralPath $RepoPath)) { return $null }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = & git -C $RepoPath @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        if ($null -eq $raw) { return '' }
        if ($raw -is [array]) { return ($raw -join "`n") }
        return [string]$raw
    } finally {
        $ErrorActionPreference = $prev
    }
}

# Pinned so a hash does not move with diff.mnemonicPrefix, core.abbrev, color, or an external
# diff driver. Stamps carry fpVersion 2 for these args. Older stamps (no fpVersion) used plain
# `git diff` and are still compared that way.
$script:CanonicalDiffArgs = @('--no-color', '--no-ext-diff', '--no-textconv', '--full-index', '--src-prefix=a/', '--dst-prefix=b/')
$script:EmptyTreeSha = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'

function Get-DiffArgsForVersion {
    param([int]$Version = 2)
    if ($Version -ge 2) { return $script:CanonicalDiffArgs }
    return @()
}

function Get-StampEntryValue {
    param($Entry, [string]$Name)
    if ($Entry -and ($Entry.PSObject.Properties.Name -contains $Name) -and $null -ne $Entry.$Name) {
        return [string]$Entry.$Name
    }
    return ''
}

function Get-EntryFingerprintVersion {
    param($Entry)
    $v = Get-StampEntryValue $Entry 'fpVersion'
    if ($v) { return [int]$v }
    return 1
}

# Returns $null when there is nothing to fingerprint: missing path, git failure, or an empty
# staged diff. Callers must treat $null as "no review possible", never as a match.
function Get-StagedDiffFingerprint {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [int]$Version = 2
    )
    $gitArgs = @('diff') + @(Get-DiffArgsForVersion -Version $Version) + @('--staged')
    $diff = Get-GitDiffText -RepoPath $RepoPath -GitArgs $gitArgs
    if ($null -eq $diff) { return $null }
    return (Get-DiffFingerprintFromText -Diff $diff)
}

function Get-RangeDiffFingerprint {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To,
        [int]$Version = 2
    )
    $gitArgs = @('diff') + @(Get-DiffArgsForVersion -Version $Version) + @($From, $To)
    $diff = Get-GitDiffText -RepoPath $RepoPath -GitArgs $gitArgs
    if ($null -eq $diff) { return $null }
    return (Get-DiffFingerprintFromText -Diff $diff)
}

# Full SHA of HEAD, or $null (missing path, not a repo, unborn branch).
function Get-GitHeadSha {
    param([Parameter(Mandatory)][string]$RepoPath)
    $sha = Get-GitDiffText -RepoPath $RepoPath -GitArgs @('rev-parse', '--verify', '--quiet', 'HEAD')
    if (-not $sha) { return $null }
    return $sha.Trim().ToLowerInvariant()
}

# First-parent commits newest first, as { sha; parent; isMerge }. With -Since, only the commits
# after it. First-parent keeps a merged-in base branch (prep-pr merges origin/dev) out of the walk.
function Get-FirstParentCommits {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [string]$Since,
        [int]$Limit = 50
    )
    $range = if ($Since) { "$Since..HEAD" } else { 'HEAD' }
    $raw = Get-GitDiffText -RepoPath $RepoPath -GitArgs @('rev-list', '--first-parent', '--parents', "--max-count=$Limit", $range)
    if ($null -eq $raw) { return @() }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($line in ($raw -split "`n")) {
        $parts = @($line.Trim() -split '\s+' | Where-Object { $_ })
        if ($parts.Count -eq 0) { continue }
        $parent = if ($parts.Count -gt 1) { $parts[1] } else { $null }
        [void]$list.Add([pscustomobject]@{ sha = $parts[0]; parent = $parent; isMerge = ($parts.Count -gt 2) })
    }
    return $list.ToArray()
}

function Test-GitIsAncestor {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$Ancestor
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git -C $RepoPath merge-base --is-ancestor $Ancestor HEAD 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } finally {
        $ErrorActionPreference = $prev
    }
}

# Staged diff when one exists; otherwise the newest first-parent non-merge commit, so a merge of
# the base branch does not count as the work. $null means there is nothing to compare.
function Get-WorkDiffFingerprint {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [int]$Version = 2
    )
    $staged = Get-StagedDiffFingerprint -RepoPath $RepoPath -Version $Version
    if ($staged) { return $staged }
    $work = @(Get-FirstParentCommits -RepoPath $RepoPath | Where-Object { -not $_.isMerge }) | Select-Object -First 1
    if (-not $work) { return $null }
    $from = if ($work.parent) { $work.parent } else { $script:EmptyTreeSha }
    return (Get-RangeDiffFingerprint -RepoPath $RepoPath -From $from -To $work.sha -Version $Version)
}

# Hash of the work commits alone, replayed onto -From in a throwaway index. Used when the base
# branch was merged between two work commits, so headSha..newest would also carry the base's
# changes. $null when a commit does not apply cleanly (for example conflict edits in the merge).
function Get-ReplayedWorkFingerprint {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][object[]]$Commits,
        [int]$Version = 2
    )
    $index = [IO.Path]::GetTempFileName()
    $patch = [IO.Path]::GetTempFileName()
    $prevIndex = $env:GIT_INDEX_FILE
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $env:GIT_INDEX_FILE = $index
        & git -C $RepoPath read-tree $From 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { return $null }
        foreach ($c in $Commits) {
            & git -C $RepoPath diff --binary --full-index --no-color --no-ext-diff --no-textconv "--output=$patch" $c.parent $c.sha 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { return $null }
            if ((Get-Item -LiteralPath $patch).Length -eq 0) { continue }
            & git -C $RepoPath apply --cached --binary $patch 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { return $null }
        }
        $gitArgs = @('diff') + @(Get-DiffArgsForVersion -Version $Version) + @('--cached', $From)
        $diff = Get-GitDiffText -RepoPath $RepoPath -GitArgs $gitArgs
        if ($null -eq $diff) { return $null }
        return (Get-DiffFingerprintFromText -Diff $diff)
    } finally {
        if ($null -eq $prevIndex) { Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue } else { $env:GIT_INDEX_FILE = $prevIndex }
        $ErrorActionPreference = $prev
        Remove-Item -LiteralPath $index, $patch -Force -ErrorAction SilentlyContinue
    }
}

function Test-ReviewVerdict {
    param([AllowNull()][AllowEmptyString()][string]$Verdict)
    $v = ([string]$Verdict).Replace('*', '').Trim()
    return ($v -in @('Ready', 'Ready with fixes', 'No change'))
}

# Count stored finding lines by severity. A line starts with its label, optionally
# bolded or bracketed: "Major: ...", "**Blocker** ...", "[Major] ...".
function Get-FindingCounts {
    param($Findings)
    $counts = @{ Blocker = 0; Major = 0 }
    foreach ($line in @($Findings)) {
        if ([string]$line -match '^\W*(Blocker|Major)\b') { $counts[$Matches[1]]++ }
    }
    return $counts
}

# The verdict a repo's findings allow (severity-and-output.md "Verdict rules"), or $null
# when the pair is consistent. Any Blocker is Not ready; any Major is not Ready.
function Get-VerdictFindingConflict {
    param([AllowNull()][AllowEmptyString()][string]$Verdict, $Findings)
    $v = ([string]$Verdict).Replace('*', '').Trim()
    $c = Get-FindingCounts $Findings
    if ($c.Blocker -and $v -ne 'Not ready') {
        return "$($c.Blocker) Blocker finding(s) mean the verdict is Not ready, not '$v'"
    }
    if ($c.Major -and $v -eq 'Ready') {
        return "$($c.Major) Major finding(s) mean the verdict is Ready with fixes or Not ready, not Ready"
    }
    if (($c.Blocker + $c.Major) -and $v -eq 'No change') {
        return "'No change' cannot carry Blocker/Major findings"
    }
    return $null
}

# A merge commit after the stamp whose tree is not a clean merge of its two parents
# (conflict resolution, or any other edit made in the merge). $null when every such merge is clean.
function Get-UnreviewedMergeReason {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [string]$Since
    )
    if (-not $Since) { return $null }
    $merges = @(Get-FirstParentCommits -RepoPath $RepoPath -Since $Since | Where-Object { $_.isMerge })
    foreach ($m in $merges) {
        $sha = $m.sha.ToLowerInvariant()
        $reason = "merge commit $sha contains edits beyond both parents; review the branch and stamp -Mode pre-merge"
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $p1 = (& git -C $RepoPath rev-parse --verify --quiet "$sha^1" 2>$null | Out-String).Trim()
            $p2 = (& git -C $RepoPath rev-parse --verify --quiet "$sha^2" 2>$null | Out-String).Trim()
            if (-not $p1 -or -not $p2) { return $reason }
            $clean = & git -C $RepoPath merge-tree --write-tree $p1 $p2 2>$null
            if ($LASTEXITCODE -ne 0) { return $reason }
            $cleanTree = if ($clean -is [array]) { [string]$clean[0] } else { [string]$clean }
            $cleanTree = $cleanTree.Trim().ToLowerInvariant()
            $actual = (& git -C $RepoPath rev-parse --verify --quiet ('{0}^{{tree}}' -f $sha) 2>$null | Out-String).Trim().ToLowerInvariant()
            if (-not $actual -or $cleanTree -ne $actual) { return $reason }
        } finally {
            $ErrorActionPreference = $prev
        }
    }
    return $null
}

# Does the repo still hold exactly the work this review stamp saw? Returns { ok; reason }.
# Staged stamp: the staged diff matches, or, once committed, headSha..newest first-parent
#   non-merge commit matches. Splitting the reviewed set across commits is fine, and a clean
#   merge of the base branch afterwards is ignored. A merge commit that is not a clean merge of
#   its parents fails the stamp. Any edit after the review changes the hash.
# No change / pre-merge: nothing staged, headSha still on the branch, and only clean merges after it.
# Legacy stamp (no headSha): version-1 hash of the staged diff or of the newest non-merge commit.
function Test-ReviewedWorkPresent {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)]$Entry,
        [string]$StampMode = 'staged'
    )
    $verdict = (Get-StampEntryValue $Entry 'verdict').Replace('*', '').Trim()
    $mode = Get-StampEntryValue $Entry 'mode'
    if (-not $mode) { $mode = $StampMode }
    $headSha = (Get-StampEntryValue $Entry 'headSha').ToLowerInvariant()
    $fp = (Get-StampEntryValue $Entry 'fingerprint').ToLowerInvariant()
    $version = Get-EntryFingerprintVersion $Entry
    $staged = Get-StagedDiffFingerprint -RepoPath $RepoPath -Version $version

    if ($verdict -eq 'No change' -or $mode -eq 'pre-merge') {
        if ($staged) { return [pscustomobject]@{ ok = $false; reason = 'staged change after the review' } }
        if (-not $headSha) { return [pscustomobject]@{ ok = $false; reason = 'stamp has no headSha' } }
        if (-not (Test-GitIsAncestor -RepoPath $RepoPath -Ancestor $headSha)) {
            return [pscustomobject]@{ ok = $false; reason = 'reviewed commit is not on this branch (rebased, or another branch is checked out)' }
        }
        $after = @(Get-FirstParentCommits -RepoPath $RepoPath -Since $headSha | Where-Object { -not $_.isMerge })
        if ($after.Count -gt 0) { return [pscustomobject]@{ ok = $false; reason = "$($after.Count) commit(s) after the review" } }
        $mergeReason = Get-UnreviewedMergeReason -RepoPath $RepoPath -Since $headSha
        if ($mergeReason) { return [pscustomobject]@{ ok = $false; reason = $mergeReason } }
        $why = if ($verdict -eq 'No change') { 'no-change' } else { 'pre-merge-head' }
        return [pscustomobject]@{ ok = $true; reason = $why }
    }

    if ($staged) {
        if ($staged -eq $fp) { return [pscustomobject]@{ ok = $true; reason = 'staged-match' } }
        return [pscustomobject]@{ ok = $false; reason = 'staged diff differs from the reviewed diff' }
    }

    if ($headSha) {
        if (-not (Test-GitIsAncestor -RepoPath $RepoPath -Ancestor $headSha)) {
            return [pscustomobject]@{ ok = $false; reason = 'review base is not on this branch (rebased, or another branch is checked out)' }
        }
        $since = @(Get-FirstParentCommits -RepoPath $RepoPath -Since $headSha)
        $workCommits = @($since | Where-Object { -not $_.isMerge })
        if ($workCommits.Count -eq 0) { return [pscustomobject]@{ ok = $false; reason = 'reviewed change is neither staged nor committed' } }
        $work = $workCommits[0]
        # A base merge older than the newest work commit sits inside headSha..work: replay the
        # work commits alone instead of diffing across it.
        $workIndex = [array]::IndexOf($since, $work)
        $mergeInside = @($since | Select-Object -Skip ($workIndex + 1) | Where-Object { $_.isMerge }).Count -gt 0
        if ($mergeInside) {
            [array]::Reverse($workCommits)
            $current = Get-ReplayedWorkFingerprint -RepoPath $RepoPath -From $headSha -Commits $workCommits -Version $version
            if ($null -eq $current) {
                return [pscustomobject]@{ ok = $false; reason = 'base merged between work commits and the work does not replay cleanly; review the branch and stamp -Mode pre-merge' }
            }
            if ($current -eq $fp) {
                $mergeReason = Get-UnreviewedMergeReason -RepoPath $RepoPath -Since $headSha
                if ($mergeReason) { return [pscustomobject]@{ ok = $false; reason = $mergeReason } }
                return [pscustomobject]@{ ok = $true; reason = 'commit-match-replayed' }
            }
            return [pscustomobject]@{ ok = $false; reason = 'committed work differs from the reviewed diff' }
        }
        $current = Get-RangeDiffFingerprint -RepoPath $RepoPath -From $headSha -To $work.sha -Version $version
        if ($current -and $current -eq $fp) {
            $mergeReason = Get-UnreviewedMergeReason -RepoPath $RepoPath -Since $headSha
            if ($mergeReason) { return [pscustomobject]@{ ok = $false; reason = $mergeReason } }
            return [pscustomobject]@{ ok = $true; reason = 'commit-match' }
        }
        return [pscustomobject]@{ ok = $false; reason = 'committed work differs from the reviewed diff' }
    }

    $legacy = Get-WorkDiffFingerprint -RepoPath $RepoPath -Version 1
    if ($legacy -and $legacy -eq $fp) { return [pscustomobject]@{ ok = $true; reason = 'legacy-commit-match' } }
    return [pscustomobject]@{ ok = $false; reason = 'does not match the staged diff or last commit' }
}

# Skip review-diff only when the stamp's work is still exactly what is in the repo. Uses the same
# Test-ReviewedWorkPresent the close gate uses, so a skip can never be refused at close.
function Get-ReviewSkipDecision {
    param(
        $Stamp,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$RepoPath
    )
    if (-not $Stamp) {
        return [pscustomobject]@{ repo = $Repo; skip = $false; reason = 'no-stamp'; verdict = $null }
    }
    $entry = $null
    if ($Stamp.PSObject.Properties.Name -contains 'repos' -and $Stamp.repos) {
        $names = @($Stamp.repos.PSObject.Properties.Name)
        if ($names -contains $Repo) { $entry = $Stamp.repos.$Repo }
    }
    $stampMode = Get-StampEntryValue $Stamp 'mode'
    if (-not $stampMode) { $stampMode = 'staged' }
    $mode = Get-StampEntryValue $entry 'mode'
    if (-not $mode) { $mode = $stampMode }
    if ($mode -notin @('staged', 'pre-merge')) {
        return [pscustomobject]@{ repo = $Repo; skip = $false; reason = 'unknown-mode'; verdict = $null }
    }
    if (-not $entry) {
        return [pscustomobject]@{ repo = $Repo; skip = $false; reason = 'repo-not-in-stamp'; verdict = $null }
    }
    $verdict = (Get-StampEntryValue $entry 'verdict').Replace('*', '').Trim()
    if ($verdict -inotin @('Ready', 'No change')) {
        return [pscustomobject]@{ repo = $Repo; skip = $false; reason = 'verdict-not-ready'; verdict = $verdict }
    }
    if ($verdict -ieq 'Ready' -and $mode -eq 'staged') {
        $stored = Get-StampEntryValue $entry 'fingerprint'
        if (-not $stored -or $stored -eq $script:EmptyDiffFingerprint) {
            return [pscustomobject]@{ repo = $Repo; skip = $false; reason = 'empty-stamp'; verdict = $verdict }
        }
    }
    $check = Test-ReviewedWorkPresent -RepoPath $RepoPath -Entry $entry -StampMode $stampMode
    if (-not $check.ok) {
        return [pscustomobject]@{ repo = $Repo; skip = $false; reason = "work-changed: $($check.reason)"; verdict = $verdict }
    }
    return [pscustomobject]@{ repo = $Repo; skip = $true; reason = $check.reason; verdict = $verdict }
}

function Merge-TicketManifestFields {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][hashtable]$Patch
    )
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Manifest not found: $ManifestPath"
    }
    $obj = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($key in $Patch.Keys) {
        $val = $Patch[$key]
        if ($obj.PSObject.Properties.Name -contains $key) {
            $obj.$key = $val
        } else {
            $obj | Add-Member -NotePropertyName $key -NotePropertyValue $val
        }
    }
    $json = ConvertTo-Json -InputObject $obj -Depth 30
    [System.IO.File]::WriteAllText($ManifestPath, $json + "`n", (New-Object System.Text.UTF8Encoding $false))
}

function Get-ManifestCtxPctValue {
    param($Manifest, [string]$Phase)
    if (-not $Manifest) { return $null }
    if (-not ($Manifest.PSObject.Properties.Name -contains 'ctxPct')) { return $null }
    $ctx = $Manifest.ctxPct
    if (-not $ctx) { return $null }
    if (-not ($ctx.PSObject.Properties.Name -contains $Phase)) { return $null }
    $v = $ctx.$Phase
    if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) { return $null }
    return [int]$v
}

function Get-StackSmokeWorkFingerprint {
    param([hashtable]$RepoPaths, [int]$Version = 2)
    if (-not $RepoPaths -or $RepoPaths.Count -eq 0) { return $null }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($name in ($RepoPaths.Keys | Sort-Object)) {
        $path = [string]$RepoPaths[$name]
        $fp = if ($path) { Get-WorkDiffFingerprint -RepoPath $path -Version $Version } else { $null }
        if ($fp) { [void]$parts.Add("$name=$fp") }
    }
    if ($parts.Count -eq 0) { return $null }
    return (Get-DiffFingerprintFromText -Diff ($parts -join "`n"))
}

function Get-StackSmokeDecision {
    param(
        $Stamp,
        [hashtable]$RepoPaths
    )
    $labels = @{
        never   = 'Never tested'
        passed  = 'Tested'
        failed  = 'Failed'
        skipped = 'Skipped'
        stale   = 'Untested latest changes'
    }
    $recorded = 'never'
    $storedFp = ''
    $lastStatus = $null
    if ($Stamp) {
        if ($Stamp.PSObject.Properties.Name -contains 'status' -and $Stamp.status) {
            $recorded = [string]$Stamp.status
        }
        if ($Stamp.PSObject.Properties.Name -contains 'fingerprint') {
            $storedFp = [string]$Stamp.fingerprint
        }
        if ($Stamp.PSObject.Properties.Name -contains 'lastStatus' -and $Stamp.lastStatus) {
            $lastStatus = [string]$Stamp.lastStatus
        }
    }
    if ($recorded -eq 'never') {
        return [pscustomobject]@{ recorded = 'never'; effective = 'never'; reason = 'no-stamp'; label = $labels.never }
    }
    if ($recorded -eq 'skipped') {
        return [pscustomobject]@{ recorded = 'skipped'; effective = 'skipped'; reason = 'skipped'; label = $labels.skipped }
    }
    if ($recorded -eq 'stale') {
        return [pscustomobject]@{ recorded = 'stale'; effective = 'stale'; reason = 'marked-stale'; label = $labels.stale; lastStatus = $lastStatus }
    }
    # Stamps before fpVersion hashed plain `git diff`; compare them the same way.
    $current = Get-StackSmokeWorkFingerprint -RepoPaths $RepoPaths -Version (Get-EntryFingerprintVersion $Stamp)
    if ($recorded -in @('passed', 'failed')) {
        if ($storedFp -and $current -and ($storedFp -eq $current)) {
            return [pscustomobject]@{ recorded = $recorded; effective = $recorded; reason = 'fingerprint-match'; label = $labels[$recorded] }
        }
        if ($storedFp -and $current -and ($storedFp -ne $current)) {
            return [pscustomobject]@{ recorded = $recorded; effective = 'stale'; reason = 'fingerprint-mismatch'; label = $labels.stale; lastStatus = $recorded }
        }
        if (-not $storedFp -and $current) {
            return [pscustomobject]@{ recorded = $recorded; effective = 'stale'; reason = 'no-stored-fingerprint'; label = $labels.stale; lastStatus = $recorded }
        }
        return [pscustomobject]@{ recorded = $recorded; effective = $recorded; reason = 'no-current-fingerprint'; label = $labels[$recorded] }
    }
    return [pscustomobject]@{ recorded = $recorded; effective = $recorded; reason = 'unknown-status'; label = $recorded }
}
