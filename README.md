# PPVPN Rulesets

PPVPN Rulesets builds native remote rule sets for Clash/Mihomo, sing-box,
Surge, Loon, Shadowrocket, and Quantumult X from a small set of established
upstream projects.

The project does not maintain its own routing accuracy database. Domain
classification comes from
[v2fly/domain-list-community](https://github.com/v2fly/domain-list-community),
and China IPv4/IPv6 ranges come from
[gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip).

## Build locally

Requirements: Git, Go 1.25.12+, curl, jq, and compatible `sing-box` and `mihomo`
executables on `PATH`. CI pins and verifies exact official release artifacts.

```bash
./scripts/build.sh
```

Generated files are written to `publish/` and are intentionally not committed
to the source branch.

## Published rule sets

The initial catalog contains:

- `cn`: v2fly `cn`
- `private`: v2fly `private`
- `proxy`: v2fly `geolocation-!cn`
- `reject`: v2fly `category-ads-all`
- `cn-ip`: China IPv4 and IPv6 from `china-operator-ip`

Every catalog entry is generated for the six target clients. sing-box receives
both source JSON and compiled SRS output.

Some v2fly categories contain regular-expression domain rules. They are kept
for Mihomo and sing-box, but omitted for clients whose native remote rule-set
syntax cannot represent them safely. The exact per-client counts and omissions
are published in `manifest.json`; no omission is silent.

## Release contract

- `catalog.json` is the stable machine-readable contract used by downstream
  subscription services. It defines each rule set's behavior, default action,
  and six client-specific relative paths.
- `publish` is the stable moving branch for subscription URLs.
- Every changed build also receives an immutable `rulesets-YYYYMMDDHHMMSS` tag.
- `manifest.json` records source commits, tool versions, file hashes, per-client
  counts, and capability-related omissions.
- Builds fail on missing inputs, empty rule sets, compiler errors, missing
  outputs, invalid target syntax, or JSON/SRS disagreement.

See [docs/production.md](docs/production.md) for downstream synchronization,
stable URL, rollback, and release procedures.

## Upstream engine

This repository is derived from
[samqvz/DIY-Ruleset](https://github.com/samqvz/DIY-Ruleset). Its existing Go
engine performs parsing, normalization, deduplication, rendering, and SRS
compilation. PPVPN-specific work is intentionally limited to source preparation,
configuration, validation, and publishing.

## License

The builder remains licensed under GPL-3.0. Generated rule files retain the
applicable terms and attribution of their data sources. See [LICENSE](LICENSE).
