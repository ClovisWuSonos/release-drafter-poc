# action-update-region-rollout-status

## 0.1.0

### Minor Changes

- [#1706](https://github.com/Sonos-Inc/platform-core/pull/1706) [`d226d80`](https://github.com/Sonos-Inc/platform-core/commit/d226d80eaa7e6418e755f22653b422c06eff0f08) Thanks [@ClovisWuSonos](https://github.com/ClovisWuSonos)! - Add `update-region-rollout-status`, a composite action that adds or updates region rollout status in a GitHub release.

  - `tag` (required) — git tag of the release (e.g. `account-service-2.14.200`).
  - `regions-status` (required) — JSON array of `{region, status}` pairs. Statuses: `complete`, `failed`, `rolled-back`. Both `complete` and `failed` are allowed on draft and published releases; `rolled-back` requires a published release and `reverted-to-tag`.
  - `reverted-to-tag` (optional) — tag that production was reverted to. Required for rollback only.
  - `github-token` (required) — GitHub token with `contents: write` permission.

  The rollout status block is written between `<!-- rollout-status:start -->` and `<!-- rollout-status:end -->` delimiters.
