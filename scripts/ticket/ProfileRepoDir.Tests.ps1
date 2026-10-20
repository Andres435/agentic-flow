#Requires -Version 7
# Parity with hooks/core/session-context.js profileRepoDir: both read fixtures/profile-repo-dirs.json,
# so the session hook and Get-TicketFromBranch look in the same folder for each profile repo.
Describe 'Get-ProfileRepoDir' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'lib/ManifestFields.ps1')
        $fixture = Join-Path $PSScriptRoot 'fixtures/profile-repo-dirs.json'
        $script:cases = @((Get-Content -LiteralPath $fixture -Raw | ConvertFrom-Json).cases)
    }

    It 'has shared cases to check' {
        $script:cases.Count | Should -BeGreaterThan 0
    }

    It 'maps every shared case to the same folder as the session hook' {
        foreach ($c in $script:cases) {
            $label = $c.repo | ConvertTo-Json -Compress
            Get-ProfileRepoDir $c.repo | Should -Be $c.dir -Because $label
        }
    }
}
