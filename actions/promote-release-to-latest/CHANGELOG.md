# action-promote-release-to-latest

## 0.1.0

### Minor Changes

- [#1696](https://github.com/Sonos-Inc/platform-core/pull/1696) [`284174d`](https://github.com/Sonos-Inc/platform-core/commit/284174dfb8e4dbd7c27e0cc002819ba6376d4b65) Thanks [@ClovisWuSonos](https://github.com/ClovisWuSonos)! - Add `promote-release-to-latest`, a composite action that promotes a release to the Latest Release via the GitHub API. Handles two scenarios:

  - **Forward deployment** — promotes a draft release to published and marks it as latest. Intended to be called at the end of a fully successful rollout — all regions deployed and clear.
  - **Manual rollback** — re-points `--latest` to an existing published release.

  - `github-token` (required) — GitHub token with `contents: write` permission to promote the release.
  - `tag` (required) — the release tag to promote (e.g. `account-service-2.14.200`).
