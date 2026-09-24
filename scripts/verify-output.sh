#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
publish_dir="${repo_root}/publish"
build_dir="${repo_root}/.build"
rulesets_file="${build_dir}/rulesets.json"
catalog_file="${publish_dir}/catalog.json"
entries_file="${build_dir}/verification-entries.tsv"
apple_clients="surge loon shadowrocket quantumultx"

mkdir -p "${build_dir}/decompiled"
: > "${entries_file}"

command -v sing-box >/dev/null
command -v mihomo >/dev/null
test -s "${rulesets_file}"
test -s "${catalog_file}"

expected_count="$(jq 'length' "${rulesets_file}")"
jq -e --argjson expected "${expected_count}" '
  .schema == 2 and
  (.rulesets | length == $expected) and
  (all(.rulesets[];
    (.id | test("^[a-z0-9][a-z0-9-]{0,63}$")) and
    (.upstream_key | type == "string" and length > 0) and
    (.behavior == "domain" or .behavior == "ipcidr") and
    (.group | type == "string" and length > 0) and
    ((.clients | keys | sort) == ["clash", "loon", "quantumultx", "shadowrocket", "singbox", "surge"])
  ))
' "${catalog_file}" >/dev/null

diff -u \
  <(jq -r '.[].id' "${rulesets_file}" | LC_ALL=C sort) \
  <(jq -r '.rulesets[].id' "${catalog_file}" | LC_ALL=C sort)

while IFS= read -r relative_path; do
  case "${relative_path}" in
    /*|*..*) printf 'Unsafe catalog path: %s\n' "${relative_path}" >&2; exit 1 ;;
  esac
  test -s "${publish_dir}/${relative_path}"
done < <(jq -r '.rulesets[].clients[].path' "${catalog_file}")

line_count() {
  awk 'END { print NR + 0 }' "$1"
}

while IFS= read -r ruleset; do
  singbox_srs="${publish_dir}/singbox/${ruleset}.srs"
  mihomo_yaml="${publish_dir}/mihomo/${ruleset}.yaml"
  test -s "${singbox_srs}"
  test -s "${mihomo_yaml}"
  grep -qx 'payload:' <(sed -n '1p' "${mihomo_yaml}")

  decompiled="${build_dir}/decompiled/${ruleset}.json"
  rm -f "${decompiled}"
  sing-box rule-set decompile "${singbox_srs}" --output "${decompiled}" >/dev/null
  jq -e '.version >= 1 and (.rules | length > 0)' "${decompiled}" >/dev/null

  canonical_count="$(grep -c '^  - ' "${mihomo_yaml}")"
  test "${canonical_count}" -gt 0
  singbox_count="$(jq '[.rules[] | to_entries[] | (.value | if type == "array" then length else 1 end)] | add // 0' "${decompiled}")"
  test "${singbox_count}" -eq "${canonical_count}"
  portable_count=""

  for client in ${apple_clients}; do
    client_file="${publish_dir}/${client}/${ruleset}.list"
    test -s "${client_file}"
    actual_count="$(line_count "${client_file}")"
    test "${actual_count}" -gt 0
    if [ -z "${portable_count}" ]; then
      portable_count="${actual_count}"
    else
      test "${actual_count}" -eq "${portable_count}"
    fi

    if [ "${client}" = "quantumultx" ]; then
      awk -F, '
        !/^(host|host-suffix|host-keyword|ip-cidr|ip6-cidr),/ { exit 1 }
        NF < 3 { exit 1 }
      ' "${client_file}"
    else
      awk -F, '
        !/^(DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD|IP-CIDR|IP-CIDR6),/ { exit 1 }
      ' "${client_file}"
    fi
  done

  test "${portable_count}" -le "${canonical_count}"
  omitted_count=$((canonical_count - portable_count))
  printf '%s\t%s\t%s\t%s\n' "${ruleset}" "${canonical_count}" "${portable_count}" "${omitted_count}" >> "${entries_file}"
done < <(jq -r '.[].id' "${rulesets_file}")

entries_json="$(jq -Rn '
  [inputs | split("\t") as $fields | {
    key: $fields[0],
    value: {
      canonical_count: ($fields[1] | tonumber),
      portable_count: ($fields[2] | tonumber),
      omitted_from_portable_clients: {unsupported_rules: ($fields[3] | tonumber)},
      clients: {
        mihomo: ($fields[1] | tonumber),
        singbox: ($fields[1] | tonumber),
        surge: ($fields[2] | tonumber),
        loon: ($fields[2] | tonumber),
        shadowrocket: ($fields[2] | tonumber),
        quantumultx: ($fields[2] | tonumber)
      }
    }
  }] | from_entries
' < "${entries_file}")"

mihomo_home="${build_dir}/mihomo-home"
mihomo_config="${mihomo_home}/config.yaml"
mihomo_provider_dir="${mihomo_home}/providers"
rm -rf "${mihomo_home}"
mkdir -p "${mihomo_provider_dir}"
while IFS= read -r ruleset; do
  cp "${publish_dir}/mihomo/${ruleset}.yaml" "${mihomo_provider_dir}/${ruleset}.yaml"
done < <(jq -r '.[].id' "${rulesets_file}")
{
  printf '%s\n' \
    'mixed-port: 7890' \
    'mode: rule' \
    'log-level: silent' \
    'proxies: []' \
    'proxy-groups:' \
    '  - name: PROXY' \
    '    type: select' \
    '    proxies: [DIRECT]' \
    'rule-providers:'
  while IFS= read -r ruleset; do
    printf '  %s:\n' "${ruleset}"
    printf '%s\n' \
      '    type: file' \
      '    behavior: classical' \
      '    format: yaml'
    printf '    path: "./providers/%s.yaml"\n' "${ruleset}"
  done < <(jq -r '.[].id' "${rulesets_file}")
  printf '%s\n' 'rules:'
  while IFS= read -r ruleset; do
    printf '  - RULE-SET,%s,DIRECT\n' "${ruleset}"
  done < <(jq -r '.[].id' "${rulesets_file}")
  printf '%s\n' '  - MATCH,DIRECT'
} > "${mihomo_config}"

mihomo -t -d "${mihomo_home}" -f "${mihomo_config}"

jq -n \
  --arg status "passed" \
  --arg mihomo_config "passed" \
  --arg singbox_decompile "passed" \
  --argjson ruleset_count "${expected_count}" \
  --argjson rulesets "${entries_json}" \
  '{
    status: $status,
    ruleset_count: $ruleset_count,
    checks: {
      mihomo_config: $mihomo_config,
      singbox_srs_decompile: $singbox_decompile
    },
    rulesets: $rulesets
  }' > "${build_dir}/verification.json"

printf 'Verified %d rule sets across six clients\n' "${expected_count}"
