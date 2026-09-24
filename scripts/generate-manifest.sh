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

files_tsv="${repo_root}/.build/manifest-files.tsv"
: > "${files_tsv}"
{
  find "${publish_dir}" -type f ! -name manifest.json -print | LC_ALL=C sort | while IFS= read -r file; do
    relative_path="${file#"${publish_dir}/"}"
    printf '%s\t%s\t%s\n' \
      "${relative_path}" \
      "$(hash_file "${file}")" \
      "$(wc -c < "${file}" | tr -d ' ')"
  done
} > "${files_tsv}"
files_json_file="${repo_root}/.build/manifest-files.json"
jq -Rn '[inputs | split("\t") | {path: .[0], sha256: .[1], size: (.[2] | tonumber)}]' \
  < "${files_tsv}" > "${files_json_file}"

jq -n \
  --slurpfile sources "${sources_file}" \
  --slurpfile verification "${verification_file}" \
  --slurpfile files "${files_json_file}" \
  --arg builder_commit "$(git -C "${repo_root}" rev-parse HEAD)" \
  --arg builder_repository "${builder_repository}" \
  --arg sing_box_version "$(sing-box version | sed -n '1s/^sing-box version //p')" \
  --arg mihomo_version "$(mihomo -v | sed -n '1s/^Mihomo Meta v\([^ ]*\).*/\1/p')" \
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
    files: $files[0]
  }' > "${publish_dir}/manifest.json"
