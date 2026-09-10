# Toolbox — Build & Audit Notes (2026-09-10)

## Build
- `./build.sh` succeeds: universal (arm64 + x86_64) binary, signed with the
  local Developer ID Application identity, installed to /Applications.
- 0 errors, 172 warnings before this pass → 164 after.
- No `Package.swift` / SwiftPM target — the app is built by compiling
  `Sources/**/*.swift` directly with `swiftc`, per `build.sh`.

## Tests
- No test target exists: no `Package.swift`, no `Tests/` directory, no
  `run_tests.sh`. Nothing to run.

## Fixes made (committed)
- `Sources/Services/VideoService.swift`, `Sources/Services/YtDlp.swift`:
  removed a redundant `try?` around `FileHandle.availableData` in the
  ffmpeg/yt-dlp progress-polling loops. `availableData` doesn't throw, so
  the `try?` was dead and tripped a compiler warning ("no calls to
  throwing functions occur within 'try' expression"). No behavior change.

## Audited, found OK (no change made)
- **`as! CMFormatDescription` casts** in `FileInfoService.swift` (3 sites):
  looked like risky force-casts at first glance, but
  `AVAssetTrack.formatDescriptions` is `[Any]?` under the (deprecated)
  synchronous API this file uses, and the array is documented to only ever
  contain `CMFormatDescription` values for that track type — so the cast is
  safe in practice. Attempted to simplify by binding `fd` directly off the
  `[CMFormatDescription]`-typed array and hit a compiler error confirming
  the array element type really is `Any`, not `CMFormatDescription` — so
  the cast is required, not dead code. Reverted that attempt; left as-is.
- **TODO/FIXME/XXX**: none in the codebase.
- **Other force-unwraps (`try!`, `.first!`, `.last!`)**: none found.
- **Entitlements** (`Toolbox.entitlements`): No App Sandbox (deliberate,
  documented inline — direct DMG distribution needs unrestricted file/
  system access). Hardened Runtime exemptions (`allow-jit`,
  `disable-library-validation`, `disable-executable-page-protection`) are
  all explicitly `false`. `Info.plist` declares exactly one usage
  description, `NSSpeechRecognitionUsageDescription`, and it's the only
  privacy-sensitive API actually used in the codebase (on-device
  transcription via `SFSpeechRecognizer`) — no camera/microphone/photo-
  library APIs are referenced anywhere else, so there's nothing missing or
  stale here.
- **SF Symbols vs custom assets**: fully consistent — the app icon is
  rendered at build time from an SF Symbol (`wrench.and.screwdriver.fill`,
  in `build.sh`), and every in-app icon is `Image(systemName:)`. No
  `NSImage(named:)` / `Image("...")` custom asset references anywhere, no
  `Assets.xcassets` catalog. Nothing partially migrated or mixed.
- **Dead code / unused files**: none found. Swept every `Sources/**/*.swift`
  file for cross-references; all are wired in (view/service pairs match up,
  `App.swift`/`Tool.swift`/`Support.swift` are the shared plumbing).
- **Version currency**: `Info.plist` embedded in `build.sh` has
  `CFBundleShortVersionString = 1.0`; the DMG this repo ships,
  `Toolbox-1.0.dmg`, matches (and `make-dmg.sh` derives its filename from
  the built app's Info.plist directly, so this can't drift). No git tags
  exist in the repo to cross-check against.
- Neither the app bundle (`Toolbox.app/`) nor the `.dmg` is tracked in git
  (`.gitignore` excludes both) — the checked-in `Toolbox-1.0.dmg` is a
  local build artifact, not a repo asset.

## Still open (not fixed — out of scope for this pass / needs a real refactor)
- **~150 AVFoundation deprecation warnings** (`duration`, `tracks(withMediaType:)`,
  `formatDescriptions`, `commonMetadata`, `stringValue`, `estimatedDataRate`,
  `nominalFrameRate`, `preferredTransform`, `naturalSize`,
  `exportPresets(compatibleWith:)`) across `FileInfoService.swift`,
  `VideoService.swift`, `AudioService.swift`, `TranscriptionService.swift`.
  All are the synchronous AVFoundation API deprecated in macOS 13 in favor
  of the `async`/`load(...)` API. Fixing these properly means threading
  `async`/`await` through several call sites (some currently synchronous,
  called from sync contexts) — a real refactor, deliberately left for a
  dedicated pass rather than done piecemeal here.
- **~10 Swift 6 concurrency warnings** ("reference to captured var 'self' in
  concurrently-executing code", "main actor-isolated property ... can not
  be mutated from a Sendable closure") in the video/audio progress-callback
  paths. These are warnings under today's language mode but will become
  hard errors under Swift 6 strict concurrency — worth a dedicated pass,
  not a safe one-line fix.

## Current version
**1.0** (`CFBundleShortVersionString` in `build.sh`'s generated
`Info.plist`; matches `Toolbox-1.0.dmg`). No git tags in the repo.
