#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

./scripts/prepare-inputs.sh
go test ./...
go run . .build/config.yaml
./scripts/generate-catalog.sh
cp LICENSE NOTICE publish/
./scripts/verify-output.sh
./scripts/generate-manifest.sh

printf 'PPVPN Rulesets build completed successfully\n'
