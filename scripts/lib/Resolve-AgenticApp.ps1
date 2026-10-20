#Requires -Version 7
<#
.SYNOPSIS
    Match the opened checkout's git origin to apps/registry.json.

.DESCRIPTION
    Dot-sourced. Do not run directly. Ticket scripts and stack launchers live in
    the host repo. When the current directory (or -Checkout) is a registered app,
    OverlayRoot is apps/<id> (profile.json and plans/) and CheckoutRoot is that
    git toplevel (stack cwd). When nothing matches, both are the host root.

    Same rules as hooks/core/resolve-app.js: an app counts only when the registry
    lists its id, and its overlay is always apps/<id> under the host.

.NOTES
    AGENTIC_APP_OVERLAY (sessionStart sets it) wins when it is apps/<id> under this
    host and the registry lists <id>; any other value is ignored. When the registry
    lists apps but none matches, one warning per process says the host plans/ is in
    use, because a script run from the wrong folder would otherwise pick it silently.
#>

Set-StrictMode -Version Latest

function ConvertTo-AgenticOrigin {
    param([string]$Url)
    if (-not $Url) { return '' }
    $s = $Url.Trim()
    $s = $s -replace '^git@([^:]+):', 'https://$1/'
    $s = $s -replace '^ssh://git@([^/]+)/', 'https://$1/'
    $s = $s.TrimEnd('/')
    $s = $s -replace '\.git$', ''
    return $s.ToLowerInvariant()
}

function Get-AgenticGitOrigin {
    param([string]$Dir)
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir)) { return '' }
    try {
        $out = & git -C $Dir remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0) { return '' }
        return ([string]$out).Trim()
    } catch {
        return ''
    }
}

function Get-AgenticGitToplevel {
    param([string]$Dir)
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir)) { return $null }
    try {
        $out = & git -C $Dir rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
        return ([string]$out).Trim()
    } catch {
        return $null
    }
}

# Registry entries with both an id and an origin; @() when the file is missing or unreadable.
function Get-AgenticRegistryApps {
    param([Parameter(Mandatory)][string]$HostRoot)
    $registryPath = Join-Path $HostRoot 'apps/registry.json'
    if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) { return @() }
    try {
        $reg = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warning "apps/registry.json is not valid JSON, so no app is active: $($_.Exception.Message)"
        return @()
    }
    if (-not $reg -or -not ($reg.PSObject.Properties.Name -contains 'apps')) { return @() }
    return @(@($reg.apps) | Where-Object {
        $_ -and ($_.PSObject.Properties.Name -contains 'id') -and ($_.PSObject.Properties.Name -contains 'origin') -and
        [string]$_.id -and [string]$_.origin
    })
}

function New-AgenticAppResult {
    param([string]$HostFull, [string]$Id, [string]$CheckoutRoot)
    $overlay = if ($Id) { Join-Path $HostFull (Join-Path 'apps' $Id) } else { $HostFull }
    return [pscustomobject]@{
        Id           = if ($Id) { $Id } else { $null }
        HostRoot     = $HostFull
        OverlayRoot  = $overlay
        CheckoutRoot = if ($Id) { $CheckoutRoot } else { $HostFull }
        ProfilePath  = Join-Path $overlay 'profile.json'
        PlansDir     = Join-Path $overlay 'plans'
    }
}

function Resolve-AgenticApp {
    param(
        [Parameter(Mandatory)][string]$HostRoot,
        [string]$Checkout
    )
    $hostFull = [IO.Path]::GetFullPath($HostRoot)
    $here = if ($Checkout) { $Checkout } else { (Get-Location).Path }
    $top = Get-AgenticGitToplevel $here
    if (-not $top) { $top = $here }
    $apps = @(Get-AgenticRegistryApps -HostRoot $hostFull)
    if ($apps.Count -eq 0) { return New-AgenticAppResult -HostFull $hostFull }

    if ($env:AGENTIC_APP_OVERLAY) {
        $overlay = [IO.Path]::GetFullPath($env:AGENTIC_APP_OVERLAY).TrimEnd('\', '/')
        $id = Split-Path $overlay -Leaf
        $expected = [IO.Path]::GetFullPath((Join-Path $hostFull (Join-Path 'apps' $id))).TrimEnd('\', '/')
        $listed = @($apps | Where-Object { [string]$_.id -eq $id }).Count -gt 0
        if ($listed -and $overlay -eq $expected -and (Test-Path -LiteralPath $overlay -PathType Container)) {
            return New-AgenticAppResult -HostFull $hostFull -Id $id -CheckoutRoot $top
        }
    }

    $origin = ConvertTo-AgenticOrigin (Get-AgenticGitOrigin $top)
    if ($origin) {
        foreach ($app in $apps) {
            if ((ConvertTo-AgenticOrigin ([string]$app.origin)) -eq $origin) {
                return New-AgenticAppResult -HostFull $hostFull -Id ([string]$app.id) -CheckoutRoot $top
            }
        }
    }

    if (-not (Get-Variable -Name AgenticAppNoMatchWarned -Scope Script -ValueOnly -ErrorAction SilentlyContinue)) {
        $script:AgenticAppNoMatchWarned = $true
        $shown = if ($origin) { $origin } else { 'no origin' }
        Write-Warning ("No app in apps/registry.json matches $top ($shown); using the host plans/ and profile.json. " +
            'Run from the app checkout, or set AGENTIC_APP_OVERLAY to apps/<id>.')
    }
    return New-AgenticAppResult -HostFull $hostFull
}
