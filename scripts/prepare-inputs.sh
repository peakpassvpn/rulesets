#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_root="$(mktemp -d)"
trap 'rm -rf "${work_root}"' EXIT

dlc_dir="${work_root}/domain-list-community"
china_ip_dir="${work_root}/china-operator-ip"
export_dir="${work_root}/exported"
upstream_keys="${work_root}/upstream-keys.txt"
mapping_file="${work_root}/mapping.tsv"

git clone --quiet --depth 1 https://github.com/v2fly/domain-list-community.git "${dlc_dir}"
git clone --quiet --depth 1 --branch ip-lists https://github.com/gaoyifan/china-operator-ip.git "${china_ip_dir}"

mkdir -p "${export_dir}" "${repo_root}/add" "${repo_root}/.build"
find "${repo_root}/add" -type f -name '*.list' -delete

find "${dlc_dir}/data" -maxdepth 1 -type f -exec basename {} \; | LC_ALL=C sort > "${upstream_keys}"
awk '{ id=$0; gsub(/!/, "not-", id); print $0 "\t" id }' "${upstream_keys}" > "${mapping_file}"

if invalid="$(cut -f2 "${mapping_file}" | awk 'length($0)>64 || $0 !~ /^[a-z0-9][a-z0-9-]*$/')" && [ -n "${invalid}" ]; then
  printf 'Invalid generated ruleset IDs:\n%s\n' "${invalid}" >&2
  exit 1
fi
if duplicates="$(cut -f2 "${mapping_file}" | LC_ALL=C sort | uniq -d)" && [ -n "${duplicates}" ]; then
  printf 'Colliding generated ruleset IDs:\n%s\n' "${duplicates}" >&2
  exit 1
fi
if cut -f2 "${mapping_file}" | grep -qx 'cn-ip'; then
  printf 'Generated ruleset ID cn-ip conflicts with the China IP ruleset\n' >&2
  exit 1
fi

export_lists="$(paste -sd, "${upstream_keys}")"
(
  cd "${dlc_dir}"
  go run ./ --outputdir="${export_dir}" --exportlists="${export_lists}"
)

while IFS=$'\t' read -r upstream_key ruleset_id; do
  source_file="${export_dir}/${upstream_key}.txt"
  target_file="${repo_root}/add/${ruleset_id}.list"
  test -s "${source_file}"
  sed -E 's/:@[^[:space:]]+$//' "${source_file}" | sed '/^[[:space:]]*$/d; s/^/v2ray=/' > "${target_file}"
  test -s "${target_file}"
done < "${mapping_file}"

test -s "${china_ip_dir}/china.txt"
test -s "${china_ip_dir}/china6.txt"
{
  sed '/^[[:space:]]*$/d' "${china_ip_dir}/china.txt"
  sed '/^[[:space:]]*$/d' "${china_ip_dir}/china6.txt"
} > "${repo_root}/add/cn-ip.list"

jq -Rn '
  [inputs | split("\t") as $fields | {
    id: $fields[1],
    upstream_key: $fields[0],
    behavior: "domain",
    group: (if ($fields[0] | startswith("category-")) then "category"
            elif ($fields[0] | startswith("geolocation-")) then "geolocation"
            elif ($fields[0] | startswith("tld-")) then "tld"
            else "service" end)
  }] + [{id: "cn-ip", upstream_key: "china-operator-ip", behavior: "ipcidr", group: "ip"}]
' < "${mapping_file}" > "${repo_root}/.build/rulesets.json"

{
  cat <<'YAML'
global:
  enable_gh_proxy: false
  gh_proxy: ""
  split_cnip: false
  singbox:      {enable: true, single_file: true, json: false, srs: true}
  mihomo:       {enable: true, single_file: true, txt: false, yaml: true, mrs: false}
  v2ray:        {enable: false, single_file: true}
  surge:        {enable: true, single_file: true}
  loon:         {enable: true, single_file: true}
  stash:        {enable: false, single_file: true}
  egern:        {enable: false, single_file: true}
  shadowrocket: {enable: true, single_file: true}
  quantumultx:  {enable: true, single_file: true}

categories:
YAML
  jq -r '.[] | "  - name: \(.id)\n    upstreams: []\n"' "${repo_root}/.build/rulesets.json"
} > "${repo_root}/.build/config.yaml"

jq -n \
  --arg v2fly_repository "v2fly/domain-list-community" \
  --arg v2fly_commit "$(git -C "${dlc_dir}" rev-parse HEAD)" \
  --arg china_ip_repository "gaoyifan/china-operator-ip" \
  --arg china_ip_commit "$(git -C "${china_ip_dir}" rev-parse HEAD)" \
  --argjson ruleset_count "$(jq 'length' "${repo_root}/.build/rulesets.json")" \
  '{
    v2fly: {
      repository: $v2fly_repository,
      commit: $v2fly_commit,
      license: "MIT",
      url: "https://github.com/v2fly/domain-list-community"
    },
    china_ip: {
      repository: $china_ip_repository,
      commit: $china_ip_commit,
      license: "MIT",
      url: "https://github.com/gaoyifan/china-operator-ip"
    },
    ruleset_count: $ruleset_count
  }' > "${repo_root}/.build/sources.json"

printf 'Prepared %s PPVPN rulesets in %s/add\n' "$(jq 'length' "${repo_root}/.build/rulesets.json")" "${repo_root}"
