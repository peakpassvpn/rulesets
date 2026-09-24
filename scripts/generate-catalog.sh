#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rulesets_file="${repo_root}/.build/rulesets.json"
sources_file="${repo_root}/.build/sources.json"
publish_dir="${repo_root}/publish"

test -s "${rulesets_file}"
test -s "${sources_file}"
mkdir -p "${publish_dir}"

jq -n \
  --slurpfile rulesets "${rulesets_file}" \
  --slurpfile sources "${sources_file}" '
  {
    schema: 2,
    sources: $sources[0],
    rulesets: ($rulesets[0] | map(. as $ruleset | . + {
      clients: {
        clash: {path: ("mihomo/" + $ruleset.id + ".yaml"), format: "yaml"},
        singbox: {path: ("singbox/" + $ruleset.id + ".srs"), format: "srs"},
        surge: {path: ("surge/" + $ruleset.id + ".list"), format: "text"},
        loon: {path: ("loon/" + $ruleset.id + ".list"), format: "text"},
        shadowrocket: {path: ("shadowrocket/" + $ruleset.id + ".list"), format: "text"},
        quantumultx: {path: ("quantumultx/" + $ruleset.id + ".list"), format: "text", requires_force_policy: true}
      }
    }))
  }
' > "${publish_dir}/catalog.json"
