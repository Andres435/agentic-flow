#Requires -Version 7
Describe 'Resolve-AgenticApp' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Resolve-AgenticApp.ps1')
        Remove-Item Env:AGENTIC_APP_OVERLAY -ErrorAction SilentlyContinue
    }

    It 'normalizes ssh and https origins' {
        ConvertTo-AgenticOrigin 'git@github.com:Andres435/foo.git' |
            Should -Be (ConvertTo-AgenticOrigin 'https://github.com/Andres435/foo')
    }

    It 'returns the host overlay when the registry is empty' {
        $hostRoot = Join-Path $TestDrive 'host'
        New-Item -ItemType Directory -Path (Join-Path $hostRoot 'apps') | Out-Null
        Set-Content -LiteralPath (Join-Path $hostRoot 'apps/registry.json') -Value '{ "apps": [] }'
        $got = Resolve-AgenticApp -HostRoot $hostRoot -Checkout $hostRoot
        $got.Id | Should -Be $null
        $got.OverlayRoot | Should -Be ([IO.Path]::GetFullPath($hostRoot))
        $got.ProfilePath | Should -Be (Join-Path ([IO.Path]::GetFullPath($hostRoot)) 'profile.json')
    }

    It 'honors AGENTIC_APP_OVERLAY when that folder exists' {
        $hostRoot = Join-Path $TestDrive 'host2'
        $overlay = Join-Path $hostRoot 'apps/demo'
        New-Item -ItemType Directory -Path $overlay | Out-Null
        $env:AGENTIC_APP_OVERLAY = $overlay
        try {
            $got = Resolve-AgenticApp -HostRoot $hostRoot -Checkout $hostRoot
            $got.Id | Should -Be 'demo'
            $got.PlansDir | Should -Be (Join-Path $overlay 'plans')
        } finally {
            Remove-Item Env:AGENTIC_APP_OVERLAY -ErrorAction SilentlyContinue
        }
    }
}
