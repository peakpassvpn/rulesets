#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sources_file="${repo_root}/.build/sources.json"
verification_file="${repo_root}/.build/verification.json"
publish_dir="${repo_root}/publish"
builder_repository="${GITHUB_REPOSITORY:-peakpassvpn/rulesets}"

test -s "${sources_file}"
test -s "${verification_file}"
test -d "${publish_dir}"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

files_json="$({
  find "${publish_dir}" -type f ! -name manifest.json -print | LC_ALL=C sort | while IFS= read -r file; do
    relative_path="${file#"${publish_dir}/"}"
    jq -cn \
      --arg path "${relative_path}" \
      --arg sha256 "$(hash_file "${file}")" \
      --argjson size "$(wc -c < "${file}" | tr -d ' ')" \
      '{path: $path, sha256: $sha256, size: $size}'
  done
} | jq -s '.')"

jq -n \
  --slurpfile sources "${sources_file}" \
  --slurpfile verification "${verification_file}" \
  --arg builder_commit "$(git -C "${repo_root}" rev-parse HEAD)" \
  --arg builder_repository "${builder_repository}" \
  --arg sing_box_version "$(sing-box version | sed -n '1s/^sing-box version //p')" \
  --arg mihomo_version "$(mihomo -v | sed -n '1s/^Mihomo Meta v\([^ ]*\).*/\1/p')" \
  --argjson files "${files_json}" \
  '{
    schema: 1,
    builder_commit: $builder_commit,
    builder: {
      repository: $builder_repository,
      license: "GPL-3.0",
      upstream_engine: "samqvz/DIY-Ruleset"
    },
    tools: {sing_box: $sing_box_version, mihomo: $mihomo_version},
    sources: $sources[0],
    verification: $verification[0],
    files: $files
  }' > "${publish_dir}/manifest.json"
