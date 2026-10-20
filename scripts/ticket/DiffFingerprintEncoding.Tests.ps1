#Requires -Version 7
#Requires -Modules Pester
<#
.SYNOPSIS
    Pester 5 tests: work fingerprints must not depend on the console code page. A diff with a
    non-ASCII byte (a copyright sign) hashes the same in an interactive pwsh (UTF-8 console) and in a
    pwsh spawned with redirected stdout from Node or Git Bash (OEM code page).
#>

BeforeAll {
    $script:Lib = Join-Path (Join-Path $PSScriptRoot 'lib') 'ManifestFields.ps1'
    $script:Assert = Join-Path $PSScriptRoot 'Assert-AgenticProof.ps1'
    . $script:Lib

    function Invoke-Git([string]$Repo, [string[]]$GitArgs) {
        & git -C $Repo -c user.email=t@e.com -c user.name=t @GitArgs 2>&1 | Out-Null
    }
    # Run a pwsh child with redirected stdout (so its console encoding is the OEM code page).
    function Invoke-Child([string[]]$ChildArgs) {
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = 'pwsh'
        foreach ($a in @('-NoProfile', '-NonInteractive') + $ChildArgs) { $psi.ArgumentList.Add($a) }
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [Diagnostics.Process]::Start($psi)
        $err = $p.StandardError.ReadToEndAsync()
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        [void]$err.Wait()
        return [pscustomobject]@{ out = $out.Trim(); code = $p.ExitCode }
    }
    # The pre-fix approach: native command output under a UTF-8 console, in this process.
    function Get-OldStyleText([string]$Repo, [string[]]$GitArgs) {
        $prevEnc = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
            $raw = & git -C $Repo @GitArgs 2>$null
            if ($null -eq $raw) { return '' }
            if ($raw -is [array]) { return ($raw -join "`n") }
            return [string]$raw
        } finally {
            [Console]::OutputEncoding = $prevEnc
        }
    }
    function New-Repo([string]$Name, [string[]]$Lines) {
        $repo = Join-Path $TestDrive "$Name-repo"
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        Invoke-Git $repo @('init', '-q')
        [IO.File]::WriteAllText((Join-Path $repo 'a.vb'), (($Lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
        Invoke-Git $repo @('add', 'a.vb')
        Invoke-Git $repo @('commit', '-q', '-m', 'init')
        return $repo
    }
    function Set-FileLines([string]$Repo, [string[]]$Lines) {
        [IO.File]::WriteAllText((Join-Path $Repo 'a.vb'), (($Lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
        Invoke-Git $Repo @('add', 'a.vb')
    }
    $script:Copyright = ' ' + [char]0x00A9 + ' 2014'
    $script:Cafe = 'caf' + [char]0x00E9
}

Describe 'Get-StagedDiffFingerprint encoding independence' {
    BeforeAll {
        $script:NonAscii = New-Repo 'nonascii' @("' Copyright$($script:Copyright)", "' $($script:Cafe)", 'Dim x = 1')
        Set-FileLines $script:NonAscii @("' Copyright$($script:Copyright)", "' $($script:Cafe)", 'Dim x = 2')
        $script:Ascii = New-Repo 'ascii' @("' plain", 'Dim x = 1')
        Set-FileLines $script:Ascii @("' plain", 'Dim x = 2')
    }

    It 'matches between this process and a child pwsh with redirected stdout (OEM console)' {
        # Reference is pinned to a UTF-8 console so the test does not depend on how Pester was launched.
        $inProc = Get-DiffFingerprintFromText -Diff (Get-OldStyleText $script:NonAscii (@("diff") + $script:CanonicalDiffArgs + @("--staged")))
        $inProc | Should -Match '^[0-9a-f]{64}$'
        $cmd = ". '$($script:Lib)'; Write-Output (Get-StagedDiffFingerprint -RepoPath '$($script:NonAscii)')"
        $child = Invoke-Child @('-Command', $cmd)
        $child.code | Should -Be 0
        $child.out | Should -Be $inProc
    }

    It 'hashes the UTF-8 text of the diff, so the non-ASCII text survives' {
        $diff = Get-GitDiffText -RepoPath $script:NonAscii -GitArgs (@('diff') + $script:CanonicalDiffArgs + @('--staged'))
        $diff | Should -Match ([regex]::Escape($script:Copyright))
        $diff | Should -Match ([regex]::Escape($script:Cafe))
        $sha = [Security.Cryptography.SHA256]::Create()
        $expected = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($diff))) -replace '-', '').ToLowerInvariant()
        $sha.Dispose()
        Get-StagedDiffFingerprint -RepoPath $script:NonAscii | Should -Be $expected
    }

    It 'equals the old UTF-8-console native-command text for the non-ASCII diff' {
        $gitArgs = @('diff') + $script:CanonicalDiffArgs + @('--staged')
        (Get-GitDiffText -RepoPath $script:NonAscii -GitArgs $gitArgs) | Should -BeExactly (Get-OldStyleText $script:NonAscii $gitArgs)
    }

    It 'is unchanged for an ASCII-only diff (new text equals the old native-command text)' {
        $gitArgs = @('diff') + $script:CanonicalDiffArgs + @('--staged')
        $old = Get-OldStyleText $script:Ascii $gitArgs
        $old | Should -Not -BeNullOrEmpty
        (Get-GitDiffText -RepoPath $script:Ascii -GitArgs $gitArgs) | Should -BeExactly $old
        Get-StagedDiffFingerprint -RepoPath $script:Ascii | Should -Be (Get-DiffFingerprintFromText -Diff $old)
    }

    It 'keeps the contract: null on a missing path or git failure, empty string for no output' {
        Get-GitDiffText -RepoPath (Join-Path $TestDrive 'nope') -GitArgs @('status') | Should -BeNullOrEmpty
        Get-GitDiffText -RepoPath $script:Ascii -GitArgs @('rev-parse', '--verify', '--quiet', 'refs/heads/none') | Should -BeNullOrEmpty
        Get-GitDiffText -RepoPath $script:Ascii -GitArgs @('rev-parse', '--verify', '--quiet', 'refs/heads/none') | Should -Be $null
        Get-GitDiffText -RepoPath $script:Ascii -GitArgs @('log', '--max-count=0') | Should -BeExactly ''
    }
}

Describe 'Assert-AgenticProof under a redirected-stdout child pwsh' {
    It 'PASSes a commit whose diff contains a non-ASCII character' {
        $repo = New-Repo 'proof' @("' Copyright$($script:Copyright)", 'Dim x = 1')
        Set-FileLines $repo @("' Copyright$($script:Copyright)", 'Dim x = 2')
        $fp = Get-DiffFingerprintFromText -Diff (Get-OldStyleText $repo (@("diff") + $script:CanonicalDiffArgs + @("--staged")))
        $fp | Should -Match '^[0-9a-f]{64}$'
        Invoke-Git $repo @('commit', '-q', '-m', 'work', '-m', "Agentic-Proof: v1 fp=$fp verify=pass evidence=none review=ready")
        $child = Invoke-Child @('-File', $script:Assert, '-RepoPath', $repo)
        $child.out | Should -Match '^\[PASS\] agentic-proof: [0-9a-f]{7} fp matches'
        $child.code | Should -Be 0
    }
}
