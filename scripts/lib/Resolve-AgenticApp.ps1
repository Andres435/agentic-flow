#Requires -Version 7
<#
.SYNOPSIS
    Match the opened checkout's git origin to apps/registry.json.

.DESCRIPTION
    Dot-sourced. Do not run directly. Ticket scripts and stack launchers live in
    the host repo. When the current directory (or -Checkout) is a registered app,
    OverlayRoot is apps/<id> (profile.json and plans/) and CheckoutRoot is that
    git toplevel (stack cwd). When nothing matches, both are the host root.

.NOTES
    AGENTIC_APP_OVERLAY, when set and existing, wins (sessionStart sets it).
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
        return [string]$out.Trim()
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
        return [string]$out.Trim()
    } catch {
        return $null
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

    if ($env:AGENTIC_APP_OVERLAY -and (Test-Path -LiteralPath $env:AGENTIC_APP_OVERLAY -PathType Container)) {
        $overlay = [IO.Path]::GetFullPath($env:AGENTIC_APP_OVERLAY)
        $id = Split-Path $overlay -Leaf
        return [pscustomobject]@{
            Id           = $id
            HostRoot     = $hostFull
            OverlayRoot  = $overlay
            CheckoutRoot = $top
            ProfilePath  = Join-Path $overlay 'profile.json'
            PlansDir     = Join-Path $overlay 'plans'
        }
    }

    $registryPath = Join-Path $hostFull 'apps/registry.json'
    if (-not (Test-Path -LiteralPath $registryPath)) {
        return [pscustomobject]@{
            Id           = $null
            HostRoot     = $hostFull
            OverlayRoot  = $hostFull
            CheckoutRoot = $hostFull
            ProfilePath  = Join-Path $hostFull 'profile.json'
            PlansDir     = Join-Path $hostFull 'plans'
        }
    }

    $origin = ConvertTo-AgenticOrigin (Get-AgenticGitOrigin $top)
    $matched = $null
    if ($origin) {
        try {
            $reg = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($app in @($reg.apps)) {
                if (-not $app) { continue }
                $appId = [string]$app.id
                $appOrigin = ConvertTo-AgenticOrigin ([string]$app.origin)
                if ($appId -and $appOrigin -and $appOrigin -eq $origin) {
                    $matched = $appId
                    break
                }
            }
        } catch { }
    }

    if ($matched) {
        $overlay = Join-Path $hostFull (Join-Path 'apps' $matched)
        return [pscustomobject]@{
            Id           = $matched
            HostRoot     = $hostFull
            OverlayRoot  = $overlay
            CheckoutRoot = $top
            ProfilePath  = Join-Path $overlay 'profile.json'
            PlansDir     = Join-Path $overlay 'plans'
        }
    }

    return [pscustomobject]@{
        Id           = $null
        HostRoot     = $hostFull
        OverlayRoot  = $hostFull
        CheckoutRoot = $hostFull
        ProfilePath  = Join-Path $hostFull 'profile.json'
        PlansDir     = Join-Path $hostFull 'plans'
    }
}
