# PPVPN Rulesets

PPVPN Rulesets automatically discovers every list in v2fly's data directory
and builds native remote rule sets for Clash/Mihomo, sing-box, Surge, Loon,
Shadowrocket, and Quantumult X. China IPv4 and IPv6 ranges are published as an
additional `cn-ip` rule set.

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

The catalog is generated rather than curated by hand. At the time of writing it
contains 1,540 v2fly domain lists plus `cn-ip`; the exact count and upstream
commits are recorded in every release. New upstream files appear automatically
and removed files disappear from the next catalog.

Names are preserved unless they cannot be used as stable PPVPN IDs. The only
current transformation replaces `!` with `not-`, for example
`geolocation-!cn` becomes `geolocation-not-cn`. The original name remains in
the catalog as `upstream_key`; invalid names or collisions fail the build.

Every catalog entry is generated for the six target clients. sing-box is
published as compiled SRS.

Some v2fly categories contain regular-expression domain rules. They are kept
for Mihomo and sing-box, but omitted for clients whose native remote rule-set
syntax cannot represent them safely. The exact per-client counts and omissions
are published in `manifest.json`; no omission is silent.

## Release contract

- `catalog.json` is the stable machine-readable contract used by downstream
  subscription services. It defines each atomic rule set's upstream identity,
  behavior, group, and six client-specific relative paths. It deliberately does
  not assign routing actions.
- `publish` is the stable moving branch for subscription URLs.
- Every changed build also receives an immutable `rulesets-YYYYMMDDHHMMSS` tag.
- `manifest.json` records source commits, tool versions, file hashes, per-client
  counts, and capability-related omissions.
- Builds fail on missing inputs, empty rule sets, ID collisions, compiler
  errors, missing outputs, invalid target syntax, or unreadable SRS output.

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
