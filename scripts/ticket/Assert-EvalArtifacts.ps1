#Requires -Version 7
<#
.SYNOPSIS
    Runs the real start or close gate over what each `claude plugin eval` run wrote.

.DESCRIPTION
    `claude plugin eval` has no shell grader, so it cannot call Assert-TicketArtifacts. This
    script reads the eval's JSON result (run with --keep-temp), finds each run's kept
    workspace from its tracePath (<tmp>/out/trace.jsonl -> <tmp>/home/cwd/plans), copies the
    plans/ files to a scratch folder (the kept folder is agent-written, so nothing runs inside
    it), and runs Assert-TicketArtifacts.ps1 for each <prefix>*-manifest.json it finds. The
    prefix is profile.ticketPrefix (lib/TicketPrefix.ps1) unless -Prefix names another.
    A case whose name starts with close uses -Phase close. Every other case uses -Phase
    (default start). A run may set workspace to the kept folder instead of tracePath.
    Only the plugin arm ("with") is checked. A run that wrote no manifest is a failure.

    A case may carry evals/<case>/expect.json: { "outcome": "gate" | "refuse" | "graders",
    "phase": "start" | "close" }. gate (the default) runs the gate as above. refuse passes
    only when the run wrote no *-manifest.json and no *-plan.md under plans/, whatever the
    prefix (the agent declined, as the playbook requires). graders skips the gate; the case's
    own graders decide.
    Exit 0 = every run passed, 1 = at least one failed or none were found.

.PARAMETER Results
    Path to the eval's --json output.

.PARAMETER Phase
    Gate phase for cases that are not a close case. Default start. Close cases always use close.

.PARAMETER EvalDir
    Folder holding the case folders, read for expect.json. Default: evals/ at the repo root.

.PARAMETER Prefix
    Ticket prefix of the manifests to gate. Default: profile.ticketPrefix ("TICKET-" when unset).

.EXAMPLE
    ./scripts/ticket/Assert-EvalArtifacts.ps1 -Results tmp/eval.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Results,
    [ValidateSet('start', 'close')][string]$Phase = 'start',
    [string]$EvalDir = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'evals'),
    [string]$Prefix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/TicketPrefix.ps1')
if (-not $Prefix) { $Prefix = Get-TicketPrefix }

$gate = Join-Path $PSScriptRoot 'Assert-TicketArtifacts.ps1'
$data = Get-Content -LiteralPath $Results -Raw | ConvertFrom-Json
$failed = 0
$checked = 0

foreach ($case in @($data.cases)) {
    $casePhase = if ($Phase -eq 'close' -or [string]$case.name -like 'close*') { 'close' } else { 'start' }
    $outcome = 'gate'
    $expectFile = Join-Path (Join-Path $EvalDir ([string]$case.name)) 'expect.json'
    if (Test-Path -LiteralPath $expectFile) {
        $expect = Get-Content -LiteralPath $expectFile -Raw | ConvertFrom-Json
        if ($expect.PSObject.Properties.Name -contains 'outcome') { $outcome = [string]$expect.outcome }
        if ($expect.PSObject.Properties.Name -contains 'phase') { $casePhase = [string]$expect.phase }
        if ($outcome -notin 'gate', 'refuse', 'graders') {
            Write-Output "[FAIL] eval-gate: $expectFile has unknown outcome '$outcome'"
            $failed++
            continue
        }
    }
    $runs = @()
    if ($case.arms.PSObject.Properties.Name -contains 'with') { $runs = @($case.arms.with) }
    $n = 0
    foreach ($run in $runs) {
        $n++
        $label = "$($case.name) run $n"
        $trace = if ($run.PSObject.Properties.Name -contains 'tracePath') { [string]$run.tracePath } else { '' }
        $workspace = if ($run.PSObject.Properties.Name -contains 'workspace') { [string]$run.workspace } else { '' }
        if ($workspace) {
            $plans = Join-Path $workspace 'plans'
        }
        elseif ($trace) {
            $plans = Join-Path (Join-Path (Join-Path (Split-Path (Split-Path $trace -Parent) -Parent) 'home') 'cwd') 'plans'
        }
        else {
            Write-Output "[FAIL] eval-gate: $label has no tracePath (run the eval with --keep-temp)"
            $failed++
            continue
        }
        if ($outcome -eq 'graders') {
            $checked++
            Write-Output "[PASS] eval-gate: $label graders decide (no gate)"
            continue
        }
        if ($outcome -eq 'refuse') {
            $written = @()
            if (Test-Path -LiteralPath $plans) {
                $written = @(Get-ChildItem -LiteralPath $plans -File | Where-Object { $_.Name -like '*-manifest.json' -or $_.Name -like '*-plan.md' })
            }
            $checked++
            if ($written.Count) {
                $failed++
                Write-Output "[FAIL] eval-gate: $label should have refused but wrote $(@($written | ForEach-Object { $_.Name }) -join ', ')"
            } else {
                Write-Output "[PASS] eval-gate: $label refused and wrote no ticket files"
            }
            continue
        }
        $manifests = @()
        if (Test-Path -LiteralPath $plans) { $manifests = @(Get-ChildItem -LiteralPath $plans -Filter "$Prefix*-manifest.json" -File) }
        if (-not $manifests.Count) { Write-Output "[FAIL] eval-gate: $label wrote no $Prefix*-manifest.json under $plans"; $failed++; continue }

        $scratch = Join-Path ([IO.Path]::GetTempPath()) ("eval-gate-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $scratch 'plans') -Force | Out-Null
        try {
            Copy-Item -Path (Join-Path $plans '*') -Destination (Join-Path $scratch 'plans') -Recurse -Force
            foreach ($m in $manifests) {
                $ticket = ($m.Name -replace '-manifest\.json$', '')
                $out = & $gate -Ticket $ticket -Phase $casePhase -Root $scratch 2>&1 | Out-String
                $checked++
                if ($LASTEXITCODE -eq 0) {
                    Write-Output "[PASS] eval-gate: $label $ticket"
                } else {
                    $failed++
                    Write-Output "[FAIL] eval-gate: $label $ticket`n$($out.TrimEnd())"
                }
            }
        } finally {
            Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if (-not $checked -and -not $failed) { Write-Output '[FAIL] eval-gate: no runs found in the results'; exit 1 }
if ($failed) { exit 1 }
Write-Output "[PASS] eval-gate: $checked ticket(s) passed."
exit 0
