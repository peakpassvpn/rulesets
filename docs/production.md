# Production integration

PPVPN Rulesets publishes generated assets from the `publish` branch. A changed
build also creates an immutable `rulesets-YYYYMMDDHHMMSS` tag that points to the
same publish commit.

## Downstream synchronization

Do not independently fetch `catalog.json`, `manifest.json`, and rule files from
the moving `publish` ref during one synchronization. The ref may advance
between requests.

The downstream service must:

1. Resolve `refs/heads/publish` to one commit SHA.
2. Fetch `catalog.json` and `manifest.json` from that immutable SHA.
3. Require `manifest.verification.status == "passed"`.
4. Verify every selected file's SHA-256 against `manifest.files`.
5. Construct client URLs from the selected commit SHA and the relative paths in
   `catalog.json`.
6. Atomically replace its complete catalog snapshot only after all selected
   files pass verification.

If any step fails, retain the previous complete snapshot. Never combine files
from different publish commits and never silently omit a required client.

## URL forms

Stable moving metadata URL:

```text
https://raw.githubusercontent.com/<owner>/rulesets/publish/catalog.json
```

Immutable production asset URL:

```text
https://raw.githubusercontent.com/<owner>/rulesets/<publish-commit>/<relative-path>
```

Client subscriptions should use immutable URLs selected by the PPVPN backend.
The backend may advance them after a complete catalog synchronization. Directly
using the moving `publish` URL is acceptable for manual testing, not for an
atomic production rollout.

## Catalog behavior

`catalog.json` is the source contract for consumers:

- `behavior` selects domain or IP-CIDR handling.
- `default_action` describes the intended PPVPN policy action.
- `clients` contains exactly the six supported clients and their native asset
  paths.
- Quantumult X entries require the subscription formatter to set an explicit
  `force-policy`; the policy placeholder inside the rule file is not a user
  policy decision.

`manifest.json` records source commits, compiler versions, output hashes,
per-client counts, and rule types omitted because a target client cannot safely
express them.

## Promotion and rollback

The daily workflow publishes only when generated content changes. Before a new
publish commit is selected by PPVPN, its GitHub Actions run must be successful
and the downstream synchronization above must pass.

To roll back, select an earlier immutable tag or publish commit in PPVPN. If the
moving `publish` branch itself must be restored, create a normal new commit with
the old contents. Do not force-push or delete release history.

## Operational checks

- Monitor scheduled workflow failures and the age of the latest successful
  publish commit.
- Alert when any source commit cannot be resolved, any input is empty, or the
  output count changes outside the reviewed upstream change.
- Keep the previous known-good commit available until the new commit has served
  real subscriptions successfully.
- Update pinned sing-box or Mihomo versions only through a reviewed source
  change followed by the complete build and verification gate.
