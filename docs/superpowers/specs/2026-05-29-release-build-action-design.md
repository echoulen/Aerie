# Release Build & Upload Action — Design

Status: Draft
Date: 2026-05-29

## Goal

When a GitHub release is published (typically via the `/release` skill →
`gh release create`), automatically build Aerie as a macOS `.app`, package
it into a zip, and attach the zip to the release as a downloadable asset.

The shipped `.app`'s `CFBundleShortVersionString` must match the release
tag so the user-visible version inside the app agrees with the release the
download came from.

## Non-Goals

- Universal binary or Intel (`x86_64`) build — arm64 only.
- DMG packaging.
- Sparkle update feed / in-app update channel.
- Apple Developer ID signing or notarization. The shipped binary is
  ad-hoc signed; first launch on a clean Mac requires the user to right-click
  → Open to bypass Gatekeeper.
- Automated version bumping. The release tag is the source of truth; the
  `/release` skill creates it.

## Trigger

```yaml
on:
  release:
    types: [published]
```

`release.published` fires once per `gh release create`. If the release is
later edited (notes, title), the workflow does NOT re-run — assets are
built once at publish time.

## Runner

`macos-14` — Apple Silicon (arm64), ships with Xcode and a Swift toolchain
new enough for `swift-tools-version: 5.9`.

## Workflow Steps

1. **Checkout**
   - `actions/checkout@v4` with `fetch-depth: 0`.
   - Full history is required because `make app` injects values from
     `git rev-list --count HEAD` (CFBundleVersion), `git rev-parse --short=7 HEAD`
     (GitCommitSHA), and `git log -1 --format=%cd` (GitCommitDate).

2. **Sync release tag → `CFBundleShortVersionString`**
   - Read `${{ github.event.release.tag_name }}` (e.g. `v0.2.0`).
   - Strip a leading `v` if present → `0.2.0`. The `/release` skill always
     produces `vX.Y.Z`-shaped tags, but the strip is defensive and handles
     a bare `0.2.0` tag identically.
   - Use `PlistBuddy` to overwrite `CFBundleShortVersionString` in
     `Sources/Aerie/Resources/Info.plist` before `make app` runs.
   - This ensures the `.app` shipped in the `v0.2.0` release reports
     version `0.2.0` in About / Finder Get Info / Settings.

3. **Build the .app**
   - `make app`.
   - Inside the runner, `$CI` is set to `true` by GitHub Actions, which
     causes `scripts/ensure_signing_cert.sh` to no-op (see "Makefile
     touchpoints" below). With no `AerieDev` cert present, the Makefile's
     existing fallback signs the bundle ad-hoc (`codesign --sign -`).

4. **Zip**
   - `mkdir -p dist`
   - `ditto -c -k --sequesterRsrc --keepParent Aerie.app dist/Aerie-macOS-arm64.zip`
   - The `ditto` flags match `make install` so the produced zip is
     bit-for-bit equivalent to a local `make install` zip.

5. **Upload asset to the triggering release**
   - `gh release upload "${{ github.event.release.tag_name }}" dist/Aerie-macOS-arm64.zip --clobber`
   - `--clobber` lets a re-run replace an existing asset of the same name
     instead of failing.
   - Uses the workflow's `GITHUB_TOKEN`.

## Permissions

```yaml
permissions:
  contents: write   # required to write release assets
```

No other scopes are needed.

## File Changes

| Path | Change |
| --- | --- |
| `.github/workflows/build-app.yml` | New file — the workflow described above. |
| `scripts/ensure_signing_cert.sh` | Add an early `exit 0` when `$CI` is non-empty, so CI runs don't pollute the runner's login keychain with a throwaway self-signed cert. |
| `Makefile` | Unchanged. |
| `Package.swift` | Unchanged. |
| `Sources/Aerie/Resources/Info.plist` | Unchanged at rest. The workflow mutates a copy in the runner's working tree before `make app` reads it; it never gets committed back. |

## Output

A single release asset per release:

```
Aerie-macOS-arm64.zip
```

The name matches the `make install` convention (`$(APP_NAME)-macOS-$(ARCH).zip`)
so users moving between local install and downloaded release see consistent
naming.

## Error Handling

The workflow does NOT attempt to repair partial states. If a step fails:

- **`swift build` fails** → workflow fails red. The release is already
  published (we trigger on `release.published`), so it sits there with no
  asset. The author decides whether to delete the release, fix the build,
  and re-tag, or re-run the workflow once fixed.
- **`gh release upload` fails** → same outcome: release exists, no asset.
- **PlistBuddy fails** (malformed tag) → workflow fails red before any
  artifact is produced.

No retry, no cleanup. The failure message in the Actions log is the
single source of truth.

## Makefile / Script Touchpoints

The single supporting change is in `scripts/ensure_signing_cert.sh`:

```bash
# At top, before the find-certificate check:
if [ -n "$CI" ]; then
    exit 0
fi
```

Rationale: the helper exists to create a stable self-signed identity in the
*developer's* login keychain so macOS TCC permission grants survive
rebuilds. On a CI runner, the keychain is discarded with the runner, so
there's nothing to preserve — running the helper just slows the job and
adds noise. The Makefile already gracefully falls back to ad-hoc signing
when no cert is present (`Using ad-hoc signing` branch).

Local developer flow is unaffected: `$CI` is unset on dev machines, so the
helper still creates / reuses `AerieDev` on first build.

## Open Questions

None at design time. If notarization is needed later, it slots in between
steps 3 and 4 without restructuring the workflow.

## Out-of-Scope Risks (acknowledged, not addressed)

- **Gatekeeper on download**: an ad-hoc signed app shows the "cannot be
  opened because Apple cannot check it for malicious software" dialog on
  first launch. Users must right-click → Open. This is acceptable for
  early releases and matches the current local-build experience.
- **Quarantine attribute**: `ditto -c -k` preserves the file structure but
  the download itself acquires `com.apple.quarantine` via the browser.
  Right-click → Open clears this for the user. We do not attempt to
  pre-clear it.
