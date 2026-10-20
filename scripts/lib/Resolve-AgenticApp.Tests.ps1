#Requires -Version 7
Describe 'Resolve-AgenticApp' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Resolve-AgenticApp.ps1')
        Remove-Item Env:AGENTIC_APP_OVERLAY -ErrorAction SilentlyContinue

        function New-TestHost([string]$Name, [string]$RegistryJson) {
            $hostRoot = Join-Path $TestDrive $Name
            New-Item -ItemType Directory -Path (Join-Path $hostRoot 'apps') -Force | Out-Null
            if ($null -ne $RegistryJson) {
                Set-Content -LiteralPath (Join-Path $hostRoot 'apps/registry.json') -Value $RegistryJson
            }
            return [IO.Path]::GetFullPath($hostRoot)
        }

        function New-TestCheckout([string]$Name, [string]$Origin) {
            $dir = Join-Path $TestDrive $Name
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            & git -C $dir init -q 2>$null
            if ($Origin) { & git -C $dir remote add origin $Origin 2>$null }
            return $dir
        }

        $script:demoRegistry = '{ "apps": [ { "id": "demo", "origin": "https://github.com/someone/demo.git" } ] }'
    }

    BeforeEach {
        Remove-Variable -Name AgenticAppNoMatchWarned -Scope Script -ErrorAction SilentlyContinue
        Remove-Item Env:AGENTIC_APP_OVERLAY -ErrorAction SilentlyContinue
    }

    AfterAll {
        Remove-Item Env:AGENTIC_APP_OVERLAY -ErrorAction SilentlyContinue
    }

    It 'normalizes ssh and https origins' {
        ConvertTo-AgenticOrigin 'git@github.com:Andres435/foo.git' |
            Should -Be (ConvertTo-AgenticOrigin 'https://github.com/Andres435/foo')
    }

    It 'returns the host overlay when the registry is empty' {
        $hostRoot = New-TestHost 'host' '{ "apps": [] }'
        $got = Resolve-AgenticApp -HostRoot $hostRoot -Checkout $hostRoot -WarningVariable w -WarningAction SilentlyContinue
        $got.Id | Should -Be $null
        $got.OverlayRoot | Should -Be $hostRoot
        $got.ProfilePath | Should -Be (Join-Path $hostRoot 'profile.json')
        $w | Should -BeNullOrEmpty
    }

    It 'returns the host overlay without a warning when the registry file is missing' {
        $hostRoot = New-TestHost 'host-missing' $null
        $got = Resolve-AgenticApp -HostRoot $hostRoot -Checkout $hostRoot -WarningVariable w -WarningAction SilentlyContinue
        $got.Id | Should -Be $null
        $got.PlansDir | Should -Be (Join-Path $hostRoot 'plans')
        $w | Should -BeNullOrEmpty
    }

    It 'warns and falls back to the host when the registry is not valid JSON' {
        $hostRoot = New-TestHost 'host-bad' '{ "apps": [ '
        $got = Resolve-AgenticApp -HostRoot $hostRoot -Checkout $hostRoot -WarningVariable w -WarningAction SilentlyContinue
        $got.Id | Should -Be $null
        ($w -join ' ') | Should -Match 'not valid JSON'
    }

    It 'matches a checkout whose origin is in the registry' {
        $hostRoot = New-TestHost 'host-match' $script:demoRegistry
        $checkout = New-TestCheckout 'demo-checkout' 'git@github.com:someone/demo.git'
        $got = Resolve-AgenticApp -HostRoot $hostRoot -Checkout $checkout
        $got.Id | Should -Be 'demo'
        $got.OverlayRoot | Should -Be (Join-Path $hostRoot 'apps/demo')
        $got.PlansDir | Should -Be (Join-Path $hostRoot 'apps/demo/plans')
        [IO.Path]::GetFullPath($got.CheckoutRoot) | Should -Be ([IO.Path]::GetFullPath($checkout))
    }

    It 'warns once per process when the registry lists apps but none matches' {
        $hostRoot = New-TestHost 'host-nomatch' $script:demoRegistry
        $checkout = New-TestCheckout 'other-checkout' 'https://github.com/someone/other.git'
        $first = Resolve-AgenticApp -HostRoot $hostRoot -Checkout $checkout -WarningVariable w1 -WarningAction SilentlyContinue
        $null = Resolve-AgenticApp -HostRoot $hostRoot -Checkout $checkout -WarningVariable w2 -WarningAction SilentlyContinue
        $first.Id | Should -Be $null
        $first.PlansDir | Should -Be (Join-Path $hostRoot 'plans')
        ($w1 -join ' ') | Should -Match 'No app in apps/registry.json matches'
        $w2 | Should -BeNullOrEmpty
    }

    It 'honors AGENTIC_APP_OVERLAY when it is a listed app folder under apps' {
        $hostRoot = New-TestHost 'host-env' $script:demoRegistry
        $overlay = Join-Path $hostRoot 'apps/demo'
        New-Item -ItemType Directory -Path $overlay | Out-Null
        $env:AGENTIC_APP_OVERLAY = $overlay
        $got = Resolve-AgenticApp -HostRoot $hostRoot -Checkout $hostRoot
        $got.Id | Should -Be 'demo'
        $got.PlansDir | Should -Be (Join-Path $overlay 'plans')
    }

    It 'ignores AGENTIC_APP_OVERLAY when the registry does not list that id' {
        $hostRoot = New-TestHost 'host-env-unlisted' $script:demoRegistry
        $overlay = Join-Path $hostRoot 'apps/stale'
        New-Item -ItemType Directory -Path $overlay | Out-Null
        $env:AGENTIC_APP_OVERLAY = $overlay
        $got = Resolve-AgenticApp -HostRoot $hostRoot -Checkout $hostRoot -WarningAction SilentlyContinue
        $got.Id | Should -Be $null
    }

    It 'ignores AGENTIC_APP_OVERLAY outside this host''s apps folder' {
        $hostRoot = New-TestHost 'host-env-outside' $script:demoRegistry
        $outside = Join-Path $TestDrive 'elsewhere/demo'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        $env:AGENTIC_APP_OVERLAY = $outside
        $got = Resolve-AgenticApp -HostRoot $hostRoot -Checkout $hostRoot -WarningAction SilentlyContinue
        $got.Id | Should -Be $null
    }
}
