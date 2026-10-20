---
name: agentic-proof
description: The commit trailer that carries proof of verify and review out of the local manifest, how it is verified, what may leave the machine, and the Azure Pipelines step for product teams.
keywords: agentic proof, trailer, Agentic-Proof, fingerprint, verify receipt, review stamp, PR pipeline, server-side, Azure Pipelines
---

# Agentic proof

Verify receipts and review stamps live in the local, gitignored manifest, so a PR pipeline cannot see
them and the push gate only covers pushes through Claude, Cursor, or the git `pre-push` hook. The proof
is a one-line commit trailer that lets anyone confirm a commit's work was verified and reviewed.

**Status: advisory.** The writer and verifier exist and are tested; no product repo pipeline enforces
it yet (that needs each team to accept the step, and a way to ship the verifier into each repo).

## Format

```text
Agentic-Proof: v1 fp=<64 hex> verify=pass evidence=<12 hex or none> review=<ready|ready-with-fixes>
```

- `fp` is the SHA-256 fingerprint of the commit's own diff against its first parent, hashed exactly like
  a stamp ([ManifestFields.ps1](../scripts/ticket/lib/ManifestFields.ps1): fpVersion 2 canonical diff args).
  The staged diff taken just before `git commit` is byte-identical to that commit's diff, so the writer
  uses it. It is the diff, not the commit SHA, because a commit cannot contain its own hash.
- `evidence` is the first 12 hex of the verify receipt's evidence SHA-256 (`Set-VerifyReceipt.ps1 -Evidence`), or `none`.
- `review` is the stamp verdict (`Ready`, `Ready with fixes`). `Not ready` and `No change` produce no proof.

## What may leave the machine

Only hashes and verdict words: a diff hash, a 12-character evidence prefix, `pass`, `ready`. No ticket
text, titles, paths, code, repo names, or manifest content.

## Write and verify

- **Write** (prep-pr, before the commit, with the work staged): `Get-AgenticProof.ps1 -Ticket <ticket> -Repo <repo>`
  prints the line. It refuses unless the verify receipt and review stamp both describe the staged work.
  Put the line in the commit message as the last trailer.
- **Verify** (anywhere, one file, no repo dependencies): `Assert-AgenticProof.ps1 -RepoPath <repo> [-Commit <sha>]
  [-Base <ref>] [-Require]`. It picks the newest first-parent non-merge commit in the range (a merged-in base
  branch is skipped), recomputes `fp` from that commit's diff, and compares. A present but invalid or
  mismatched trailer always fails. A missing trailer is `[INFO]` and exits 0 unless `-Require`.

## Limits

- **Self-asserted.** The same local scripts write it, so it proves "the process ran on this diff", not that
  it is tamper-proof; anyone can hand-write a matching line for a diff they did not verify. Signing with a
  shared secret would close this and is out of scope for now.
- Only the newest work commit is checked. Earlier commits in a multi-commit PR are not.
- A squash merge replaces the commits; verify before the squash (on the PR source commit).

## Azure Pipelines step (for a product repo's `ci.yml`)

Not yet adopted by any product repo, and untested in a real pipeline. Copy `Assert-AgenticProof.ps1` into
the repo (for example `.azuredevops/scripts/`) and add to PR validation. The PR build checks out a merge
commit, whose first parent is the target branch, so verify the source commit explicitly:

```yaml
- checkout: self
  fetchDepth: 0
- pwsh: |
    git fetch origin "$(System.PullRequest.TargetBranchName)"
    ./.azuredevops/scripts/Assert-AgenticProof.ps1 -RepoPath . `
      -Commit "$(System.PullRequest.SourceCommitId)" -Base "origin/$(System.PullRequest.TargetBranchName)"
  displayName: Agentic proof
  condition: eq(variables['Build.Reason'], 'PullRequest')
```

Run it without `-Require` first: a PR from someone who does not use this workflow then gets an `[INFO]`
instead of a failure. Add `-Require` once the team agrees to enforce it.
