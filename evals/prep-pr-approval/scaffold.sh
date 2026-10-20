#!/usr/bin/env bash
# Seeds this case's workspace/ into the run folder (claude plugin eval --scaffold).
set -euo pipefail
cp -R "$(dirname "$0")/workspace/." .
