#!/usr/bin/env bash
# Seeds the run folder (claude plugin eval --scaffold): the diff under review, plus the plugin files
# that decide staging and severity, copied from this repo so the case grades the real rules.
set -euo pipefail
case_dir="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$case_dir/../.." && pwd)"
cp -R "$case_dir/workspace/." .
mkdir -p plugin/rules plugin/_shared plugin/skills/review-changes
cp "$root/rules/security.mdc" plugin/rules/
cp "$root/_shared/severity-and-output.md" plugin/_shared/
cp "$root/skills/review-changes/playbooks/review-changes.md" plugin/skills/review-changes/
