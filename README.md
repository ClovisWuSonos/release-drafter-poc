# release-drafter-poc

POC for testing whether a `release-drafter` running-draft, combined with a
manual deploy pipeline that live-patches and then publishes that draft, can
**self-heal from a mid-deploy race condition** without leaking release notes
across versions.

## Files

| File | Purpose |
|---|---|
| `.github/release-drafter.yml` | release-drafter config (`Cloud Settings $RESOLVED_VERSION`, tag `cloud-settings-$RESOLVED_VERSION`) |
| `.github/workflows/release-drafter.yml` | Runs release-drafter on every push to `main`, keeps the running draft up to date |
| `.github/workflows/manual-deploy.yml` | `workflow_dispatch` deploy simulator: patches rollout status onto the draft, sleeps, then publishes the version being deployed |
| `.github/workflows/auto-tag.yml` | **Added beyond your original 4 files** — see "Why auto-tag.yml exists" below |

## Why `auto-tag.yml` exists

You asked for 4 files, but the whole test depends on constraint #1 from your
real architecture: *"every PR merge to main auto-increments the version and
creates a git tag immediately."* This repo has no such pipeline yet, so
without something creating real `cloud-settings-X.Y.Z` tags at merge time,
there'd be nothing for `manual-deploy.yml`'s publish step to anchor to —
release-drafter would fall back to whatever `main` HEAD is *at publish time*,
which is exactly the wrong thing during a race.

`auto-tag.yml` is a minimal stand-in: on every push to `main` it reads the
latest `cloud-settings-*` tag, bumps the patch number, and pushes a new tag
at that exact merge commit SHA. That's the mechanism that makes the race
self-heal — see below.

## Why the race is expected to self-heal

1. `auto-tag.yml` tags every merge **immediately**, at that merge's commit
   SHA — so `cloud-settings-1.1.3` is a fixed, immutable pointer the moment
   the 1.1.3 PR merges, regardless of what merges after it.
2. `manual-deploy.yml` Step D calls release-drafter with an explicit
   `tag: cloud-settings-1.1.3` (+ matching `version`). Since that tag already
   exists as a real git ref, GitHub/release-drafter anchors the changelog
   computation to that commit — it diffs "last published release → this tag",
   which by construction excludes anything merged later (like 1.1.4).
3. release-drafter **fully regenerates** the release body from its template
   every time it runs — it does not preserve manual edits. That means the
   rollout-status table Step B PATCHed onto the draft would normally get
   wiped out the moment release-drafter runs again (e.g. triggered by the
   1.1.4 merge, or by the publish step itself). Step D works around this by
   passing the same rollout table back in as `footer`, so it survives into
   the final published body.
4. Step E immediately re-runs release-drafter (no publish) right after, so a
   clean draft for 1.1.4 appears deterministically instead of waiting on the
   next unrelated push.

If any of steps 1–4 didn't hold, this is where you'd expect notes to leak
(e.g. the published 1.1.3 release picking up the 1.1.4 commit, or losing the
rollout table, or 1.1.4's draft inheriting the rollout table).

## One-time setup

```bash
cd release-drafter-poc
gh repo clone spoorthibhatsonos/release-drafter-poc .   # if not already cloned

# Seed a starting tag so the first real merge becomes 1.1.1, matching your example
git tag cloud-settings-1.1.0
git push origin cloud-settings-1.1.0
```

## Testing checklist

### 1. Build up a running draft (1.1.1 → 1.1.3)

Repeat 3 times (once per version), each as its own PR:

```bash
git checkout -b poc/change-1
echo "change 1 - $(date)" >> service-notes.md
git add service-notes.md && git commit -m "Change 1"
git push -u origin poc/change-1
gh pr create --fill --base main
gh pr merge --squash --auto   # or merge in the UI
```

After each merge, confirm:

```bash
# tag was created immediately
git fetch --tags && git tag --list 'cloud-settings-*'

# draft was updated
gh api repos/spoorthibhatsonos/release-drafter-poc/releases \
  --jq '.[] | select(.draft==true) | {tag_name, name, body}'
```

Do this 3 times so you end up with tags `cloud-settings-1.1.1`,
`1.1.2`, `1.1.3`, and an open draft titled **"Cloud Settings 1.1.3"**
containing all 3 commits.

### 2. Kick off the deploy for 1.1.3

```bash
gh workflow run manual-deploy.yml -f version=1.1.3
```

Watch it run:

```bash
gh run watch
```

### 3. During the ~15s sleep (Step C), merge the race PR

In a **second terminal**, while the run is sleeping:

```bash
git checkout main && git pull
git checkout -b poc/change-4
echo "change 4 - race condition commit" >> service-notes.md
git add service-notes.md && git commit -m "Change 4 (the race)"
git push -u origin poc/change-4
gh pr create --fill --base main
gh pr merge --squash --auto
```

This should:
- create tag `cloud-settings-1.1.4` (via `auto-tag.yml`)
- trigger `release-drafter.yml`, which will temporarily retitle the still-open
  draft to **"Cloud Settings 1.1.4"** and append PR #4's commit

### 4. Let the deploy finish, then verify

```bash
gh run watch   # wait for manual-deploy.yml to finish (Steps D and E)
```

**Check the published 1.1.3 release:**

```bash
gh release view cloud-settings-1.1.3 --json tagName,isDraft,body
```

Expect:
- `isDraft: false`
- body lists **only** the 3 commits from step 1 (not PR #4)
- body ends with the completed `🚀 Rollout Status` table

**Check the new draft:**

```bash
gh api repos/spoorthibhatsonos/release-drafter-poc/releases \
  --jq '.[] | select(.draft==true) | {tag_name, name, body}'
```

Expect:
- a brand-new draft (e.g. tracking `cloud-settings-1.1.4`)
- body contains **only** PR #4's commit
- **no** rollout status table present

### 5. Cleanup between runs

```bash
gh release delete cloud-settings-1.1.1 --yes 2>/dev/null || true
gh release delete cloud-settings-1.1.2 --yes 2>/dev/null || true
gh release delete cloud-settings-1.1.3 --yes 2>/dev/null || true
gh api repos/spoorthibhatsonos/release-drafter-poc/releases \
  --jq '.[] | select(.draft==true) | .id' | xargs -I{} \
  gh api -X DELETE repos/spoorthibhatsonos/release-drafter-poc/releases/{}
git tag -l 'cloud-settings-*' | xargs -I{} git push origin --delete {}
git tag -l 'cloud-settings-*' | xargs -I{} git tag -d {}
```

## Pass/fail criteria

| Check | Pass |
|---|---|
| Published `cloud-settings-1.1.3` release | Contains exactly commits 1–3, nothing from PR #4 |
| Published `cloud-settings-1.1.3` release | Contains the completed rollout table |
| New draft after publish | Exists automatically, without a manual trigger |
| New draft after publish | Contains only PR #4's commit |
| New draft after publish | Has a clean template body, no rollout table |
