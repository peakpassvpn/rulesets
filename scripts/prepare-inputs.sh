#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_root="$(mktemp -d)"
trap 'rm -rf "${work_root}"' EXIT

dlc_dir="${work_root}/domain-list-community"
china_ip_dir="${work_root}/china-operator-ip"
export_dir="${work_root}/exported"

git clone --quiet --depth 1 https://github.com/v2fly/domain-list-community.git "${dlc_dir}"
git clone --quiet --depth 1 --branch ip-lists https://github.com/gaoyifan/china-operator-ip.git "${china_ip_dir}"

mkdir -p "${export_dir}" "${repo_root}/add" "${repo_root}/.build"

(
  cd "${dlc_dir}"
  go run ./ \
    --outputdir="${export_dir}" \
    --exportlists="cn,private,geolocation-!cn,category-ads-all"
)

write_v2fly_input() {
  source_name="$1"
  target_name="$2"
  source_file="${export_dir}/${source_name}.txt"
  target_file="${repo_root}/add/${target_name}.list"

  test -s "${source_file}"
  sed -E 's/:@[^[:space:]]+$//' "${source_file}" | sed 's/^/v2ray=/' > "${target_file}"
  test -s "${target_file}"
}

write_v2fly_input "cn" "cn"
write_v2fly_input "private" "private"
write_v2fly_input "geolocation-!cn" "proxy"
write_v2fly_input "category-ads-all" "reject"

test -s "${china_ip_dir}/china.txt"
test -s "${china_ip_dir}/china6.txt"
{
  sed '/^[[:space:]]*$/d' "${china_ip_dir}/china.txt"
  sed '/^[[:space:]]*$/d' "${china_ip_dir}/china6.txt"
} > "${repo_root}/add/cn-ip.list"

jq -n \
  --arg v2fly_repository "v2fly/domain-list-community" \
  --arg v2fly_commit "$(git -C "${dlc_dir}" rev-parse HEAD)" \
  --arg china_ip_repository "gaoyifan/china-operator-ip" \
  --arg china_ip_commit "$(git -C "${china_ip_dir}" rev-parse HEAD)" \
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
    }
  }' > "${repo_root}/.build/sources.json"

printf 'Prepared PPVPN inputs in %s/add\n' "${repo_root}"
