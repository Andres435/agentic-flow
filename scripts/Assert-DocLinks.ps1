#Requires -Version 7
<#
.SYNOPSIS
    Link gate for workflow documentation. Fails on relative links that do not
    resolve, on link labels that name a path that does not exist, and on
    backticked paths into this repo that do not exist.

.DESCRIPTION
    Four checks, in descending order of how much damage they prevent:

    Links that resolve OUTSIDE this repo are out of scope for every check --
    ../../<product-repo>/..., a sibling's .cursor. Whether they resolve depends
    on the developer's workspace layout, and CI checks out this repo alone, so
    validating them would fail there and nowhere else. The one exception: a link
    or path into <Sibling>/<this folder>/ always fails when profile.json places
    this folder beside that repo (its repos[].path is not '.'), because then it
    is never inside one.

      1. BROKEN TARGET  (hard fail)
         A relative link whose target file does not exist. The corpus exists to
         tell a model where to look; a doc that names a file it cannot open
         sends the reader away with nothing. The 2026 capability reorg inserted
         a directory level under skills/ and left 100+ links one '../' short —
         this check is what stops that class from coming back.

      2. STALE LABEL    (hard fail)
         Many docs use the path itself as the visible link text:
             [../../_shared/foo.md](../../../_shared/foo.md)
         When only the target is repaired the label still names a path that
         does not exist, and a reader following the rendered text — human or
         model — goes to the wrong place. Only labels that are themselves
         relative paths ('../' or './') are checked; readable labels such as
         '.cursor/rules/x.mdc' or a prose label are deliberate and ignored.

      3. TIER CYCLE    (hard fail)
         A _shared/ contract and a skills/ doc that link at each other. A
         ONE-WAY contract -> skill link is just a reference and is allowed;
         only the mutual pair is a cycle, because the phase doc already points
         up at the contract. Redirect stubs (a 'Canonical:' line) and README
         indexes are exempt — both are navigational by design.
      4. STALE PATH    (hard fail; sibling paths warn)
         A path in an inline code span, outside fenced blocks, that does not
         exist. A find-and-replace of a folder name can leave spans like
         `<Repo>/<this folder>/skills/...` that no link check could see. Only
         spans that name this repo unambiguously are hard-checked (see the setup
         comment); a missing path git ignores is a runtime file and passes.

    Scope: the docs git sees (tracked plus new untracked, not ignored), so a
    Claude Code session worktree nested at .claude/worktrees/ is not scanned.

    This is a CORRECTNESS gate, not a growth gate. Assert-DocBudget.ps1 owns
    size. Exit 0 = pass, 1 = at least one hard failure.

.PARAMETER Root
    Workspace root (the .cursor repo dir). Defaults to the parent of $PSScriptRoot.

.PARAMETER WarnOnly
    Print violations but exit 0 (advisory mode, suitable for CI comments).

.EXAMPLE
    .\scripts\Assert-DocLinks.ps1

.EXAMPLE
    .\scripts\Assert-DocLinks.ps1 -WarnOnly
    # Advisory; always exits 0.

.NOTES
    UTF-8 encoding note: read with -Encoding UTF8 so BOM-less UTF-8 does not
    decode as ANSI on Windows PowerShell 5.1.
#>

[CmdletBinding()]
param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [switch]$WarnOnly
)

Set-StrictMode -Version Latest

# Ticket artifacts and test fixtures are out of scope: <ticket>-plan files reference
# source paths in sibling repos, and fixtures must stay byte-stable for tests.
. (Join-Path $PSScriptRoot 'ticket/lib/TicketPrefix.ps1')
$ticketPrefix = Get-TicketPrefix -Root ([IO.Path]::GetFullPath($Root))
$excluded = @('tmp/*', 'scripts/ticket/fixtures/*', "plans/$ticketPrefix*", 'node_modules/*')

$linkPattern = '\[([^\]]*)\]\(([^)\s]+)\)'

$brokenTargets  = [System.Collections.Generic.List[object]]::new()
$staleLabels    = [System.Collections.Generic.List[object]]::new()
$tierCandidates = [System.Collections.Generic.List[object]]::new()
$tierWarnings   = [System.Collections.Generic.List[object]]::new()
$pathMisses     = [System.Collections.Generic.List[object]]::new()
$stalePaths     = [System.Collections.Generic.List[object]]::new()
$siblingWarns   = [System.Collections.Generic.List[object]]::new()
$checked        = 0
$external       = 0
$spanPaths      = 0

# Links that resolve outside this repo (../../<product-repo>/..., a
# sibling's .cursor) point at repos cloned beside this one. Whether they resolve
# depends on the developer's workspace layout, and on CI nothing but this repo is
# checked out -- so they are out of scope rather than broken.
$RootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')

function Test-InsideRepo {
    param([string]$FullPath)
    return $FullPath.StartsWith($RootFull + [IO.Path]::DirectorySeparatorChar) -or $FullPath -eq $RootFull
}

# The docs as git sees them: tracked plus new untracked files, minus ignored ones. A new doc
# is checked before its first commit, and a Claude Code session worktree nested at
# .claude/worktrees/<name>/ (git-excluded) is not scanned as if it were this repo -- its links
# to sibling repos resolve one level too deep from there. Outside a git checkout (tests, an
# exported copy) walk the tree instead, skipping any folder that is its own checkout.
$atGitRoot = $false
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitPrefix = & git -C $RootFull rev-parse --show-prefix 2>$null
    $atGitRoot = $LASTEXITCODE -eq 0 -and -not "$gitPrefix".Trim()
}
if ($atGitRoot) {
    $docs = @(& git -C $RootFull -c core.quotePath=false ls-files --cached --others --exclude-standard -- '*.md' '*.mdc' '*.markdown' 2>$null |
        ForEach-Object { Join-Path $RootFull $_ } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |  # deleted, not yet staged
        ForEach-Object { Get-Item -LiteralPath $_ -Force })
} else {
    $nestedRoots = @(Get-ChildItem -LiteralPath $RootFull -Recurse -Force -Filter '.git' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne (Join-Path $RootFull '.git') } |
        ForEach-Object { (Split-Path $_.FullName -Parent) + [IO.Path]::DirectorySeparatorChar })
    $docs = @(Get-ChildItem -LiteralPath $RootFull -Recurse -File -Include '*.md', '*.mdc', '*.markdown' -ErrorAction SilentlyContinue |
        Where-Object {
            $full = $_.FullName
            $full -notmatch '[\\/]\.git[\\/]' -and -not ($nestedRoots | Where-Object { $full.StartsWith($_) })
        })
}

# --- 4. inline code paths: setup --------------------------------------------
# A backticked path is a pointer the model follows just like a link. A span is checked
# when it starts with this folder's own name (`<this folder>/`), with a folder only this
# repo has, or with hooks/ or scripts/ plus one of this repo's own subfolders (other repos
# have hooks/ and scripts/ too, so a bare `scripts/setup.ps1` may be a product repo's).
# Spans that start with a repo from profile.json are checked against the workspace and only
# warn. Everything else in backticks is code or prose. Matching is case-sensitive:
# `Scripts/x` in a product repo is not this repo's scripts/.
$selfName = Split-Path $RootFull -Leaf
$ownDirs = @('_shared', 'skills', 'agents', 'rules', 'environments', 'adapters', 'commands', 'output-styles')
$sharedNameDirs = @{}
foreach ($name in @('hooks', 'scripts')) {
    $p = Join-Path $RootFull $name
    $sharedNameDirs[$name] = @(Get-ChildItem -LiteralPath $p -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
}
$siblingRepos = @()
# Repos this folder sits beside (repos[].path is not '.'): a path <Repo>/<this folder>/ is wrong.
$besideRepos = @()
$profilePath = Join-Path $RootFull 'profile.json'
if (Test-Path -LiteralPath $profilePath) {
    try {
        $profileJson = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($profileJson.PSObject.Properties.Name -contains 'repos') {
            $siblingRepos = @($profileJson.repos | ForEach-Object { $_.name } | Where-Object { $_ })
            $besideRepos = @($profileJson.repos | Where-Object {
                $_.name -and -not (($_.PSObject.Properties.Name -contains 'path') -and ([string]$_.path).Trim() -in @('.', './', ''))
            } | ForEach-Object { $_.name })
        }
    } catch { $siblingRepos = @(); $besideRepos = @() }
}
$ticketSpanPattern = [regex]::Escape($ticketPrefix) + '(\d|\*)'
$workspaceFull = Split-Path $RootFull -Parent
$fencePattern = '(?ms)^[ \t]*(```|~~~).*?^[ \t]*\1[ \t]*\r?$'
$spanPattern  = '`([^`\r\n]+)`'

# The path inside one inline code span, or $null when the span is not a checkable path.
function Get-SpanPath {
    param([string]$Span)
    $s = $Span.Trim()
    if ($s -match '\s') {
        # A command line: check only its first token, and only when it names a file.
        $s = ($s -split '\s+')[0]
        if ($s -notmatch '\.(ps1|md|mdc|markdown|json|js|psd1)$') { return $null }
    }
    $s = $s -replace '\\', '/' -replace '^\./', '' -replace '[,;:.)]+$', ''
    $s = ($s -split '#')[0] -replace ':\d+(-\d+)?$', ''
    if ($s -notmatch '/') { return $null }
    if ($s -match '[<>{}$%|"''()\[\]]|\.\.\.|…|#|^https?:|^[A-Za-z]:/|^/|^\.\./') { return $null }
    if ($s -match $ticketSpanPattern) { return $null }  # per-ticket files are user-local
    return $s.TrimEnd('/')
}

foreach ($doc in $docs) {
    $relative = ($doc.FullName.Substring($RootFull.Length).TrimStart('\', '/') -replace '\\', '/')

    $skip = $false
    foreach ($ex in $excluded) { if ($relative -like $ex) { $skip = $true; break } }
    if ($skip) { continue }

    $text = Get-Content -LiteralPath $doc.FullName -Encoding UTF8 -Raw -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    $checked++

    $dir     = $doc.DirectoryName
    $isStub  = $text -match '(?m)^Canonical:'
    $isIndex = [IO.Path]::GetFileName($relative) -in @('README.md', 'README.markdown', 'INDEX.md')

    # --- 4. inline code paths ---------------------------------------------------
    $prose = [regex]::Replace($text, $fencePattern, '')
    foreach ($sm in [regex]::Matches($prose, $spanPattern)) {
        $path = Get-SpanPath $sm.Groups[1].Value
        if (-not $path) { continue }
        $segments = @($path -split '/')
        $first = $segments[0]
        $prefixed = $first -ceq $selfName
        if ($prefixed) {
            $segments = @($segments | Select-Object -Skip 1)
            if (-not $segments.Count) { continue }
            $first = $segments[0]
            $path = $segments -join '/'
        }
        if (-not $prefixed -and $first -cin $siblingRepos) {
            if ($segments.Count -gt 1 -and $segments[1] -ceq $selfName -and $first -cin $besideRepos) {
                $stalePaths.Add([pscustomobject]@{ File = $relative; Path = $sm.Groups[1].Value; Why = "$selfName is a sibling of $first, not inside it" })
                continue
            }
            if (-not (Test-Path -LiteralPath (Join-Path $workspaceFull $first))) { continue }  # not cloned here (CI)
            if ($path.Contains('**')) { continue }  # recursive globs are scan patterns, not pointers
            $spanPaths++
            # Repo-relative spans are written two ways: <Repo>/<path>, or a repo whose code
            # sits in a same-named inner folder (<Repo>/<Repo>/<path>).
            $rest = ($segments | Select-Object -Skip 1) -join '/'
            $candidates = @($path, "$first/$first/$rest")
            $hit = $candidates | Where-Object { Test-Path -Path (Join-Path $workspaceFull ($_ -replace '/', [IO.Path]::DirectorySeparatorChar)) }
            if (-not $hit) { $siblingWarns.Add([pscustomobject]@{ File = $relative; Path = $path }) }
            continue
        }
        if ($first -ceq 'plans') { continue }  # user-local ticket files
        $own = $prefixed -or ($first -cin $ownDirs) -or
            ($sharedNameDirs.ContainsKey($first) -and $segments.Count -gt 2 -and ($segments[1] -cin $sharedNameDirs[$first]))
        if (-not $own) { continue }
        $spanPaths++
        $full = Join-Path $RootFull ($path -replace '/', [IO.Path]::DirectorySeparatorChar)
        $nearDoc = Join-Path $dir ($path -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -Path $full) -and ($prefixed -or -not (Test-Path -Path $nearDoc))) {
            $pathMisses.Add([pscustomobject]@{ File = $relative; Path = $path; Span = $sm.Groups[1].Value })
        }
    }

    foreach ($m in [regex]::Matches($text, $linkPattern)) {
        $label  = $m.Groups[1].Value
        $target = $m.Groups[2].Value

        if ($target -match '^(https?://|mailto:|#)') { continue }

        # --- 1. broken target -------------------------------------------------
        $targetPath = ($target -split '#')[0]
        if ($targetPath) {
            $resolved = [IO.Path]::GetFullPath([IO.Path]::Combine($dir, ($targetPath -replace '/', [IO.Path]::DirectorySeparatorChar)))
            if (-not (Test-InsideRepo $resolved)) {
                # A link into <Sibling>/<this folder>/... is a bad find-and-replace, never a
                # layout difference: this folder sits beside that repo, not inside it.
                $wsRel = if ($resolved.StartsWith($workspaceFull)) { $resolved.Substring($workspaceFull.Length).TrimStart('\', '/') -replace '\\', '/' } else { '' }
                $wsSeg = @($wsRel -split '/')
                if ($wsSeg.Count -gt 1 -and $wsSeg[0] -cin $besideRepos -and $wsSeg[1] -ceq $selfName) {
                    $stalePaths.Add([pscustomobject]@{ File = $relative; Path = $target; Why = "$selfName is a sibling of $($wsSeg[0]), not inside it" })
                    continue
                }
                $external++
                continue
            }
            if (-not (Test-Path -LiteralPath $resolved)) {
                $brokenTargets.Add([pscustomobject]@{ File = $relative; Link = $target })
            }
        }

        # --- 2. stale path label ---------------------------------------------
        if ($label -like '../*' -or $label -like './*') {
            $labelPath = (($label -split '#')[0] -split ' ')[0].Trim()
            if ($labelPath) {
                $lresolved = [IO.Path]::GetFullPath([IO.Path]::Combine($dir, ($labelPath -replace '/', [IO.Path]::DirectorySeparatorChar)))
                if ((Test-InsideRepo $lresolved) -and -not (Test-Path -LiteralPath $lresolved)) {
                    $staleLabels.Add([pscustomobject]@{ File = $relative; Label = $label; Target = $target })
                }
            }
        }

        # --- 3. tier direction (deferred; needs the full graph) ---------------
        # A one-way _shared/ -> skills/ link is just a reference and creates no
        # cycle. Only a MUTUAL pair does, so collect candidates here and decide
        # after every doc has been read.
        # Only this workspace's own skills/ tree — a link into a tracked repo's
        # .cursor (e.g. <product-repo>/.cursor/skills/...) is a cross-repo reference.
        if ($relative -like '_shared/*' -and -not $isStub -and -not $isIndex -and $targetPath) {
            $tierResolved = [IO.Path]::GetFullPath([IO.Path]::Combine($dir, ($targetPath -replace '/', [IO.Path]::DirectorySeparatorChar)))
            $skillsRoot = [IO.Path]::GetFullPath([IO.Path]::Combine($Root, 'skills'))
            if ($tierResolved.StartsWith($skillsRoot + [IO.Path]::DirectorySeparatorChar)) {
                $tierCandidates.Add([pscustomobject]@{
                    File   = $relative
                    Link   = $target
                    Target = ($tierResolved.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/')
                })
            }
        }
    }
}

# --- resolve tier candidates into real cycles -------------------------------
# A candidate is a violation only when the skills/ doc links back to the same
# _shared/ contract: that mutual pair is the cycle. One-way references are fine.
foreach ($c in $tierCandidates) {
    $skillFile = Join-Path $Root ($c.Target -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $skillFile)) { continue }
    $skillText = Get-Content -LiteralPath $skillFile -Encoding UTF8 -Raw -ErrorAction SilentlyContinue
    if (-not $skillText) { continue }

    $contractName = [IO.Path]::GetFileName($c.File)
    $skillDir     = Split-Path -Parent $skillFile
    foreach ($bm in [regex]::Matches($skillText, $linkPattern)) {
        $backTarget = ($bm.Groups[2].Value -split '#')[0]
        if (-not $backTarget) { continue }
        if ([IO.Path]::GetFileName($backTarget) -ne $contractName) { continue }
        $backResolved = [IO.Path]::GetFullPath([IO.Path]::Combine($skillDir, ($backTarget -replace '/', [IO.Path]::DirectorySeparatorChar)))
        $contractFull = [IO.Path]::GetFullPath([IO.Path]::Combine($Root, ($c.File -replace '/', [IO.Path]::DirectorySeparatorChar)))
        if ($backResolved -eq $contractFull) {
            $tierWarnings.Add([pscustomobject]@{ File = $c.File; Link = $c.Link; Back = $c.Target })
            break
        }
    }
}

# A missing in-repo path that git ignores is a runtime file (scripts/.hook-errors.log,
# a launcher state file): documented on purpose, absent on a clean checkout.
if ($pathMisses.Count) {
    $ignored = @()
    if (Get-Command git -ErrorAction SilentlyContinue) {
        # Paths as arguments, not --stdin: a PowerShell pipe to a native command ends each
        # line with CRLF, and git then looks for a name ending in '\r'.
        $missPaths = @($pathMisses | ForEach-Object { $_.Path } | Sort-Object -Unique)
        $ignored = @(& git -C $RootFull check-ignore --no-index -- @missPaths 2>$null | ForEach-Object { $_ -replace '\\', '/' })
    }
    foreach ($miss in $pathMisses) {
        if ($ignored -notcontains $miss.Path) {
            $stalePaths.Add([pscustomobject]@{ File = $miss.File; Path = $miss.Span; Why = 'no such file or folder in this repo' })
        }
    }
}

$hardFailures = $brokenTargets.Count + $staleLabels.Count + $tierWarnings.Count + $stalePaths.Count

if ($brokenTargets.Count) {
    Write-Host "[FAIL] $($brokenTargets.Count) broken link target(s):" -ForegroundColor Red
    foreach ($v in $brokenTargets) { Write-Host ("  {0,-58} -> {1}" -f $v.File, $v.Link) }
}

if ($staleLabels.Count) {
    Write-Host "[FAIL] $($staleLabels.Count) stale link label(s) — label names a path that does not exist:" -ForegroundColor Red
    foreach ($v in $staleLabels) { Write-Host ("  {0,-58} [{1}] -> ({2})" -f $v.File, $v.Label, $v.Target) }
}

if ($tierWarnings.Count) {
    $color = 'Red'
    $tag   = 'FAIL'
    Write-Host "[$tag] $($tierWarnings.Count) tier cycle(s) — a _shared/ contract and a skills/ doc link at each other:" -ForegroundColor $color
    foreach ($v in $tierWarnings) { Write-Host ("  {0,-46} <-> {1}" -f $v.File, $v.Back) }
    Write-Host "  Contracts are hubs: let the phase doc point up at the contract, not both ways."
}

if ($stalePaths.Count) {
    Write-Host "[FAIL] $($stalePaths.Count) stale code path(s) — a backticked path that does not exist:" -ForegroundColor Red
    foreach ($v in $stalePaths) { Write-Host ("  {0,-58} ``{1}`` ({2})" -f $v.File, $v.Path, $v.Why) }
}

if ($siblingWarns.Count) {
    Write-Host "[WARN] $($siblingWarns.Count) sibling-repo path(s) not found in this workspace (advisory; CI cannot check them):" -ForegroundColor Yellow
    foreach ($v in $siblingWarns) { Write-Host ("  {0,-58} ``{1}``" -f $v.File, $v.Path) }
}

if ($hardFailures -eq 0) {
    Write-Host "[PASS] Doc links: $checked file(s) checked, all targets, labels, and $spanPaths code path(s) resolve, no tier cycles." -ForegroundColor Green
    if ($external) {
        Write-Host "       ($external link(s) into sibling repos not checked — they depend on workspace layout.)"
    }
    exit 0
}

if ($WarnOnly) { exit 0 }
exit 1
