# Aerie — agent notes

Native macOS SwiftUI app, **pure SwiftPM** (no `.xcodeproj`). Built and run via
the `Makefile`.

## Dev loop — use `make dev`

While iterating on code, **use `make dev`, not `make install`**:

```bash
make dev
```

It does a debug `swift build`, assembles a minimal `Aerie.app`, and relaunches
it in place (~20s, mostly the incremental build). It deliberately skips
everything `install` does that the dev loop doesn't need: release optimisation,
icon regeneration, the `/Applications` copy, and the `dist/` zip.

It *does* stamp `CFBundleShortVersionString` from the latest git tag — so a dev
build reports the tag it sits on, not the `0.1.0` placeholder in the source
`Info.plist` — but skips the `GitCommitSHA` / `GitCommitDate` /
`CFBundleVersion` injection that `install` does.

It reuses the same bundle id (`dev.echoulen.Aerie`) and the `AerieDev` signing
cert as `make install`, so the app's database, preferences, and TCC permission
grants persist across rebuilds — it's the same app state you get from the
installed build.

There is **no save-to-reload hot reload**. Each code change needs a `make dev`
to see it in the running app.

## Other make targets

| Target | Use |
|--------|-----|
| `make dev` | **Default while developing.** Debug build + relaunch in place. |
| `make build` | `swift build -c release` — compile only. |
| `make run` | Release build + bundle + launch `Aerie.app` from the repo. |
| `make install` | Release build + copy to `/Applications` + zip to `dist/`. For shipping a build, not iterating. |
| `make test` | `swift test`. |
| `make clean` | Remove `.build`, `Aerie.app`, `dist/`, generated icon. |

## Tests

`swift test` runs the suite. Note: ~70 snapshot-test failures here are
environmental (baselines are machine-dependent), not regressions — see the
project memory note before treating snapshot diffs as real failures.

## Releasing

Push a version tag; CI creates the release and publishes it once the installer
is attached:

```bash
git fetch origin && git tag vX.Y.Z origin/main && git push origin vX.Y.Z
```

`.github/workflows/build-app.yml` builds the tag, creates a draft release with
generated notes, uploads `Aerie-macOS-arm64.zip`, then publishes it. Don't
create the release first with `gh release create --draft`: GitHub doesn't run
workflows for a draft's `created` event, so nothing would build. A release made
already published (`gh release create vX.Y.Z`) still gets its zip, but apps see
it for several minutes before the zip exists ("still being published").
