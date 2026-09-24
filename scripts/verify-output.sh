#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
publish_dir="${repo_root}/publish"
build_dir="${repo_root}/.build"
rulesets=(cn private proxy reject cn-ip)
apple_clients=(surge loon shadowrocket quantumultx)
catalog_file="${publish_dir}/catalog.json"

mkdir -p "${build_dir}/decompiled"
entries_file="${build_dir}/verification-entries.jsonl"
: > "${entries_file}"

command -v sing-box >/dev/null
command -v mihomo >/dev/null
test -s "${catalog_file}"
jq -e '
  .schema == 1 and
  (.rulesets | length == 5) and
  (all(.rulesets[];
    (.id | type == "string") and
    (.behavior == "domain" or .behavior == "ipcidr") and
    (.default_action == "direct" or .default_action == "proxy" or .default_action == "reject") and
    ((.clients | keys | sort) == ["clash", "loon", "quantumultx", "shadowrocket", "singbox", "surge"])
  ))
' "${catalog_file}" >/dev/null

while IFS= read -r relative_path; do
  case "${relative_path}" in
    /*|*..*) printf 'Unsafe catalog path: %s\n' "${relative_path}" >&2; exit 1 ;;
  esac
  test -s "${publish_dir}/${relative_path}"
done < <(jq -r '.rulesets[].clients[].path' "${catalog_file}")

line_count() {
  awk 'END { print NR + 0 }' "$1"
}

for ruleset in "${rulesets[@]}"; do
    singbox_json="${publish_dir}/singbox/${ruleset}.json"
    singbox_srs="${publish_dir}/singbox/${ruleset}.srs"
    mihomo_yaml="${publish_dir}/mihomo/${ruleset}.yaml"

    test -s "${singbox_json}"
    test -s "${singbox_srs}"
    test -s "${mihomo_yaml}"
    grep -qx 'payload:' <(sed -n '1p' "${mihomo_yaml}")

    decompiled="${build_dir}/decompiled/${ruleset}.json"
    rm -f "${decompiled}"
    sing-box rule-set decompile "${singbox_srs}" --output "${decompiled}" >/dev/null
    diff -u \
      <(jq -S '.rules | map(with_entries(.value |= if type == "array" then . else [.] end))' "${singbox_json}") \
      <(jq -S '.rules | map(with_entries(.value |= if type == "array" then . else [.] end))' "${decompiled}") \
      >&2

    canonical_count="$(jq '[.rules[] | to_entries[] | (.value | if type == "array" then length else 1 end)] | add // 0' "${singbox_json}")"
    portable_count="$(jq '[.rules[] | {domain, domain_suffix, domain_keyword, ip_cidr} | to_entries[] | select(.value != null) | (.value | if type == "array" then length else 1 end)] | add // 0' "${singbox_json}")"
    regex_count="$(jq '[.rules[] | .domain_regex? // [] | length] | add // 0' "${singbox_json}")"
    mihomo_count="$(grep -c '^  - ' "${mihomo_yaml}")"

    test "${mihomo_count}" -eq "${canonical_count}"

    client_counts='{}'
    for client in "${apple_clients[@]}"; do
      client_file="${publish_dir}/${client}/${ruleset}.list"
      test -s "${client_file}"
      actual_count="$(line_count "${client_file}")"
      test "${actual_count}" -eq "${portable_count}"

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

      client_counts="$(jq -cn \
        --argjson current "${client_counts}" \
        --arg client "${client}" \
        --argjson count "${actual_count}" \
        '$current + {($client): $count}')"
    done

    jq -cn \
      --arg key "${ruleset}" \
      --argjson canonical "${canonical_count}" \
      --argjson portable "${portable_count}" \
      --argjson regex "${regex_count}" \
      --argjson mihomo "${mihomo_count}" \
      --argjson clients "${client_counts}" \
      '{
        key: $key,
        value: {
          canonical_count: $canonical,
          portable_count: $portable,
          omitted_from_portable_clients: {domain_regex: $regex},
          clients: ({mihomo: $mihomo, singbox: $canonical} + $clients)
        }
      }' >> "${entries_file}"
done

entries_json="$(jq -s 'from_entries' "${entries_file}")"

mihomo_home="${build_dir}/mihomo-home"
mihomo_config="${mihomo_home}/config.yaml"
mihomo_provider_dir="${mihomo_home}/providers"
rm -rf "${mihomo_home}"
mkdir -p "${mihomo_provider_dir}"
for ruleset in "${rulesets[@]}"; do
  cp "${publish_dir}/mihomo/${ruleset}.yaml" "${mihomo_provider_dir}/${ruleset}.yaml"
done
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
  for ruleset in "${rulesets[@]}"; do
    printf '  %s:\n' "${ruleset}"
    printf '%s\n' \
      '    type: file' \
      '    behavior: classical' \
      '    format: yaml'
    printf '    path: "./providers/%s.yaml"\n' "${ruleset}"
  done
  printf '%s\n' 'rules:'
  for ruleset in "${rulesets[@]}"; do
    printf '  - RULE-SET,%s,DIRECT\n' "${ruleset}"
  done
  printf '%s\n' '  - MATCH,DIRECT'
} > "${mihomo_config}"

mihomo -t -d "${mihomo_home}" -f "${mihomo_config}"

jq -n \
  --arg status "passed" \
  --arg mihomo_config "passed" \
  --arg singbox_roundtrip "passed" \
  --argjson rulesets "${entries_json}" \
  '{
    status: $status,
    checks: {
      mihomo_config: $mihomo_config,
      singbox_srs_roundtrip: $singbox_roundtrip
    },
    rulesets: $rulesets
  }' > "${build_dir}/verification.json"

printf 'Verified catalog and %d rule sets across six clients\n' "${#rulesets[@]}"
