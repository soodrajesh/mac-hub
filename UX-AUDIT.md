# Toolbox — UI/UX + Functional Audit

## Fix Pass (2026-09-10)

Addressed, in priority order:

1. **FIXED — Redact confirmation.** `RedactView` now gates "Apply Redaction"
   behind a real `.alert` confirmation ("This can't be undone") the first
   time it's used per app launch (`RedactConfirmationState.hasConfirmedThisSession`,
   a static in-memory flag — resets on relaunch, survives navigating away
   from and back to the tool within the same run). Also added inline copy
   above the button restating the action is irreversible, and the run
   action now refuses with an error message instead of silently no-op'ing
   when no boxes have been drawn.
2. **FIXED — Placeholder Polar config now fails distinctly.** Added
   `ToolboxLicenseConfig.isConfigured` (checks both the org ID and
   purchase-URL TODOs). `LicenseChecker.verify()` throws a new
   `.notYetConfigured` error immediately — before touching the network or
   cache — whenever it's false, with the message "Toolbox Pro isn't
   available for purchase yet — check back soon." `ProUpsellView` shows
   that message in place of the "Unlock Pro" button when unconfigured
   (instead of a button to a dead checkout URL), and
   `LicenseManagementView` hides "Get Toolbox Pro" and shows the same
   message. A real customer's real key will now see this distinct message
   rather than "invalid license key" once the org exists but is still
   misconfigured. Not yet done (explicitly out of scope for this pass):
   applying the same `isConfigured` pattern to the other 3 monetized apps
   in this line — each has its own `LicenseCheck.swift` and can implement
   this independently; no shared code needed.
3. **FIXED (partial, as scoped) — ToolScaffold migration.** `PDFOrganizeView`
   and `RedactView` (the audit's own top two picks — Organize Pages is
   free/high-usage, Redact is a flagship Pro feature) now use the shared
   `ToolScaffold` wrapper instead of hand-rolling their own header/button
   row; their bespoke content (the page grid + trash tray, the region
   selector + page nav) now lives in `ToolScaffold`'s `preview:`/`options:`
   slots, the same pattern `RemoveBackgroundView`/`BlurView` already use.
   **Deliberately deferred, not fixed:** `PDFMetadataView`, `PDFSignView`,
   `QRCodeView`, `OCRView`, `YouTubeDownloadView` — the audit's own
   recommendation was to migrate the two highest-traffic offenders first;
   migrating the remaining five is noted here as a follow-up, out of scope
   for this pass.
4. **FIXED — discard confirmation on tool switch.** Added
   `Components/UnsavedWorkTracker.swift`, a small shared `ObservableObject`
   injected into the environment from `ToolboxApp`. `CollageView` marks it
   dirty whenever Freeform mode has placed elements; `PDFOrganizeView`
   marks it dirty whenever the working page order has been touched
   (reorder/rotate/remove/restore) since the last load or save. The
   sidebar's `selection` binding is now wrapped (`selectionBinding` in
   `App.swift`) so switching away from either tool while it's dirty shows
   a "Discard your in-progress poster/page order?" alert before the switch
   is allowed to go through, instead of silently tearing down the state.
5. **FIXED — the 5 real font-scale gaps** flagged under Accessibility:
   added an `appFont(_:weight:design:)` overload (monospaced variant) to
   `Support.swift` and repointed the 5 raw `.font(.system(.body, design:
   .monospaced))` call sites (`OCRView.swift`, `YouTubeDownloadView.swift`,
   `LicenseManagementView.swift`, `QRCodeView.swift` ×2) onto it — cheap,
   low-risk, and explicitly the audit's own suggested fix.

**Not fixed, deliberately out of scope for this pass** (Medium/lower, not
cheap enough to bundle in, or explicitly excluded by the fix brief):

- **No tool search/filter for the 27-tool sidebar** (Top Issue #4,
  Medium) — a real feature addition (search field, filtering/matching
  logic across sections), not a cheap fix; left as a follow-up.
- **"Utilities" section holding only QR/Barcode** — cosmetic, low
  priority, left as-is.
- **No ETA/elapsed time on long-running batch jobs** — noted by the audit
  as a minor follow-up once the AVFoundation async migration lands, not
  independently actionable now.
- **AVFoundation deprecation warnings / Swift 6 concurrency warnings**
  (Tech Debt Risk) — explicitly out of scope for this pass per the fix
  brief; untouched.
- **VoiceOver labels/traits, keyboard-only operability of Collage's
  Freeform canvas and `RegionSelector`** — flagged by the audit as
  unverified/probable gaps needing a dedicated Accessibility Inspector
  pass, not something to guess-fix without live testing.
- **Settings' independent license-verification flow** — already covered
  by the shared `isConfigured` fix in `ToolboxLicenseCheck.swift` (both
  `App.swift` and `LicenseManagementView` call the same `LicenseChecker`),
  so no separate action was needed there beyond what's in fix #2.

---

**Scope of this pass:** Static, code-driven audit (no live GUI automation). Read in full: `App.swift`, `Tool.swift`, `Components/ToolScaffold.swift`, `Components/ProUpsell.swift`, `Components/JobModel.swift`, `Support.swift`, `ToolboxLicenseCheck.swift`, and 14 of 28 tool Views in full — the 3 free "hero" tools (Compress/Merge/Split PDF) plus PDF Organize, PDF Security, Redact, Blur/Pixelate, Remove Background, Watermark, Collage, Convert & Compress (image), Convert & Compress Video, Video Downloader. Grep-swept all 28 Views for `.font(`, `TODO`/empty-closure patterns, and any confirmation-dialog usage. **Not individually read in this pass:** Image Editor, Icon Generator, QR/Barcode, OCR, Transcribe, PDF Pages/Crop/Sign/Metadata/Page Numbers, Extract Audio, Trim/Merge/Loop Audio, Settings, License Management (~14 views) — architectural conclusions below (ToolScaffold usage, Pro gating, font discipline) are still measured across all 28 via grep, but per-tool UX judgment for those 14 should be treated as unverified.

Overall polish: **7/10** against a paid Mac-utility bar, for the surface audited. Foundations (JobModel, ToolScaffold, OutputPath, ProGate) are unusually disciplined for a solo-built utility — non-destructive-by-default output naming, real cancellable per-file progress, and honest Pro pitches are all better than most indie tools ship. It loses points on: zero confirmation step anywhere for irreversible operations, ~1/4 of tool views skipping the shared scaffold (visible inconsistency), no tool search across a 27-entry sidebar, and a licensing backend that is currently a hard-coded placeholder (functionally fine today only because it fails closed).

---

## Top 5 Issues (ranked)

1. **No confirmation/undo step before any destructive action, including Redact's explicitly-irreversible one.** `RedactView.apply()` (`Sources/Views/RedactView.swift:125`) commits on a single button click straight to disk. The tool's own copy says "the content underneath is destroyed, not just hidden" — that sentence is the strongest signal in the whole app that a confirm step is warranted, and it's the one place that doesn't have one. *Severity: High.*
2. **Licensing is non-functional in the shipped build.** `ToolboxLicenseConfig.organizationId` is literally `"TODO_POLAR_ORG_ID_TOOLBOX_PRO"` (`Sources/ToolboxLicenseCheck.swift:37`) and `purchaseURL` is `"https://TODO-polar-checkout-url-for-toolbox-pro"` (`:40`). Every verify call 404s, so **no one can currently buy or activate Pro** — "Unlock Pro" opens a dead URL. It fails closed correctly (free tools unaffected, Pro tools show the upsell rather than crashing), but this blocks all revenue until fixed. *Severity: Critical for launch readiness, not a code-quality bug.*
3. **~27% of tool views bypass `ToolScaffold`**, producing visibly inconsistent layouts across a single app. `PDFOrganizeView`, `RedactView`, `PDFMetadataView`, `PDFSignView`, `QRCodeView`, `OCRView`, and `YouTubeDownloadView` all hand-roll their own `ScrollView`/header/button-row instead of the shared chrome. Each reuses scaffold sub-components (`DropWell`, `FileList`, `ResultBar`) inconsistently, so run-button placement, cancel affordance, and progress bar presence differ tool to tool. *Severity: Medium-High — a discoverability/trust cost across the whole app, not any one tool.*
4. **No tool search/filter for a 27-tool sidebar.** `App.swift`'s sidebar (`:22-45`) is a flat, collapsible-by-section `List` with no search field — a returning user has to remember which of 6 sections ("PDF", "Images", "Utilities", "Recognition", "Media", "Audio") a tool lives in, or scroll/scan all 27 rows. Every other piece of discoverability (PRO badges before click, specific per-tool upsell pitches) is well executed; search is the one gap. *Severity: Medium.*
5. **Switching sidebar tools silently discards in-progress work with zero warning**, most damagingly for Collage Freeform (a multi-element poster layout) and Organize Pages (a reordered/rotated page sequence) — both are meaningful, time-costly editing sessions with no save/draft state. `App.swift:detail(for:)` (`:122-153`) is a `switch` inside a `@ViewBuilder`; each case is a distinct concrete `View` type, so SwiftUI tears down and reinitializes `@StateObject`/`@State` the instant `selection` changes to a different tool and back. *Severity: Medium — real data loss risk, no code path to reproduce it needs; it's the default behavior.*

---

## Discoverability & Navigation

- **Sidebar structure** (`App.swift:22-45`, `Tool.swift:82-101`): six named sections, each collapsible via a persisted `Set<String>` in `UserDefaults` (`collapsedSectionsKey`). Good: state survives relaunch. Gap: no search field, no recents/favorites, no way to see "which tools have I used" — with 27 tools this is the single biggest gap in an otherwise well-instrumented app (see Top Issue #4).
- **Pro badges are visible before the wall** (`App.swift:31`, `ProBadge` in `ProUpsell.swift:182-192`): a small "PRO" pill sits next to every gated tool's label in the sidebar itself, so a user never gets a surprise paywall after clicking in — they know before they click. This directly satisfies the audit's "is the wall a surprise?" check. Good practice, worth keeping.
- **Section labels are a little inconsistent with mental model**: "Utilities" holds only QR/Barcode (`Tool.swift:86`) — a section of one. Minor, but as more tools are added this section either needs more members or should fold into another.

## Destructive Actions & Safety

- **No `Alert`/confirmation dialog exists anywhere in the codebase.** Confirmed via `grep -rn "confirm\|Alert(\|\.alert(" Sources/Views Sources/Components` → zero hits. This is a deliberate-looking design choice (the app leans on live preview + non-destructive output naming instead of "are you sure?" modals), and it mostly works — but it has one real gap:
  - **Redact** (`RedactView.swift:68-70,125-144`): live preview of the black boxes is genuinely good error prevention (you see exactly what will be destroyed before you click), but "Apply Redaction" still commits immediately with no second step, and the copy on the button gives no indication that this action is irreversible in a way the others aren't. Recommendation: either a one-time `.alert` on first use per session ("This permanently removes the content under these boxes — continue?") or, cheaper, inline copy directly above the button restating "cannot be undone."
- **Original files are never at risk.** Every write path in every audited tool goes through `OutputPath.make(for:dir:suffix:ext:)` (`Support.swift:118-128`), which never overwrites — it appends `-1`, `-2`, … until the candidate path is free, and always writes a *new* file with a distinct suffix (`-compressed`, `-merged`, `-redacted`, `-protected`, etc.) rather than replacing the source. This is the correct default and it's applied uniformly across every tool read in this pass. Good.
- **Batch security/PDF operations** (`PDFSecurityView.swift:73-96`) run per-file with per-file error isolation (`r.failures.append(...)`, loop continues) — a bad password on file 3 of 10 doesn't abort files 4-10 and doesn't corrupt outputs already written. Good failure isolation.
- **PDF Organize's "Save as New PDF"** (`PDFOrganizeView.swift:79-84,184-197`) is correctly named to signal non-destructiveness, and reordering/rotation/removal all stay in-memory (`pages`/`trash` arrays) until that button — genuinely undoable via the "tap to restore" trash tray (`:129-148`) before commit. This is one of the better-designed flows in the app precisely because it treats the edit as a draft. It would be even stronger paired with the ToolScaffold consistency fix (#3) since right now it's also one of the custom, non-scaffolded views.

## Batch / Progress UX

- **Real per-file progress, not a spinner-only "frozen" state**, across every batch tool read: `PDFCompressView.run()` (`:59-81`), `WatermarkView.run()` (`:118-144`), `ImageToolsView.run()` (`:105-122`), `PDFSecurityView.run()` (`:73-96`), and `VideoConvertView.run()` (`:64-82`) all call `report(Double(i+1)/Double(total))` per item, driving `ToolScaffold`'s progress bar + percentage (`ToolScaffold.swift:75-81`). Video conversion goes further and threads *sub-file* progress from `VideoService.convert(onProgress:)` (`VideoConvertView.swift:71-73`) so a single large file mid-encode still moves the bar, not just "0% → 100% per file."
- **Cancellable batches, correctly implemented.** `JobModel.cancel()` (`JobModel.swift:118-120`) cancels the detached `Task`; every batch loop checks `Task.isCancelled` between files (e.g. `PDFCompressView.swift:63`, `WatermarkView.swift:123`) and stops after the current file rather than the current byte — so cancel is responsive within one file's processing time, not instant, which is the right tradeoff over corrupting a partial write.
- **Video Downloader queue** (`YouTubeDownloadView.swift`) is the most sophisticated progress UI in the app: per-URL status enum (`queued`/`downloading(progress,size)`/`done`/`failed`) rendered as a real per-row progress bar + live size (`:160-169`), plus a running summary bar and Cancel (`:96-101`). This is best-in-class for a batch download UI and should be the template other batch tools graduate toward, not the exception.
- **Gap:** none of the audited batch tools show an ETA or per-file elapsed time — for a video re-encode that can run minutes, a percentage with no time estimate still reads as "is this stuck?" past ~30 seconds. Minor relative to the above, but worth a follow-up once the deprecation-warning tech debt (see below) is addressed, since AVFoundation's async replacement APIs would make per-file ETA cheaper to compute than today's synchronous calls.

## Pro / Monetization UX

- **Upsell copy is specific per tool, not generic boilerplate** — verified by reading all 10 `ProTool` cases in `ProUpsell.swift:42-80`. Each has a distinct one-line pitch and 3-4 concrete bullets (e.g. Redact's bullets literally repeat "content is destroyed, not hidden" from its own subtitle — consistent messaging). This is a real strength; most indie apps show one generic "Unlock Pro" screen for every gated feature.
- **`ProGate`** (`ProUpsell.swift:87-99`) always renders the full pitch view in place of the tool rather than hiding/disabling it — correct per the code's own comment ("never hides or silently disables the tool"). Confirmed structurally: every Pro view read wraps its body in `ProGate(tool: .x) { ToolScaffold(...) }`, so the locked state is the *only* thing an unlicensed user sees for that tool, with no broken partial-UI state.
- **Licensing backend is a placeholder today** (Top Issue #2) — `organizationId`/`purchaseURL` TODOs in `ToolboxLicenseCheck.swift:37,40`. Structurally the failure path is handled well: `LicenseChecker.verify` throws on the 404, `ToolboxApp.verifyLicense()` (`App.swift:81-95`) catches and sets `isProLicensed = false`, so a failed verify degrades to "show the upsell" rather than crashing or hanging — but *every* license check will fail this way until the real Polar org ID is filled in, including for a real paying customer who's entered a real key. There is no distinct "verification failed — try again" vs. "you're not licensed" messaging in `ProUpsellView`; both states render identically ("Unlock Pro" / "I already have a license"), so a real customer hitting the placeholder-org 404 today would see no signal that anything is broken, just a paywall that won't clear no matter what key they enter. Once the org ID is fixed this stops mattering; until then it's a silent-failure risk for the first real customer.
- **Settings' own independent license verification** (per `App.swift:14-16`'s comment on `LicenseManagementView`) wasn't read in this pass — flagged as unverified coverage; worth a follow-up read since it's a second, parallel implementation of the same verify flow and is exactly the kind of place two copies drift.

## Accessibility

- **`.appFont` discipline is strong, not just "mechanical-sweep-with-gaps."** Grep for raw `.font(` across `Sources/Views` and `Sources/Components`, excluding `.appFont(` itself, returns only **7 hits app-wide**:
  - `OCRView.swift:71`, `YouTubeDownloadView.swift:34`, `LicenseManagementView.swift:162`, `QRCodeView.swift:48,93` — all `.font(.system(.body, design: .monospaced))` on code/URL/output text. Monospacing isn't expressible via the current `AppFontStyle` vocabulary, so this is a real, narrow gap: those 5 strings won't scale with the user's Text Size setting even though everything around them will.
  - `CollageView.swift:234` — icon glyph sizing (`Image(systemName:).font(.system(size:9,...))`), not body text; arguably out of `appFont`'s scope since it's a fixed-size UI chrome glyph, not user-scalable content.
  - `ToolScaffold.swift:237` — same category, the DropWell icon.
  - **Net: 5 real text-scale gaps out of the whole Views/Components tree**, not the "expect gaps" the brief anticipated from a "mechanical, not exhaustive" original sweep — this is a materially better result than expected. Fix is small: add a `.monospaced` case to `AppFontStyle` (or an `appFont(_:weight:design:)` overload) and repoint those 5 call sites.
- **Text Size mechanism itself is well-reasoned**, not just present: `Support.swift:5-16`'s doc comment explains *why* it reimplements scaling instead of using SwiftUI's `dynamicTypeSize` (verified elsewhere that Dynamic Type has zero visual effect on macOS) — this is the kind of judgment call that's easy to get wrong silently, and it's documented instead of just asserted.
- **Not evaluated in this pass:** VoiceOver labels/traits, keyboard-only operability of the custom drag/resize/rotate gestures in `CollageView`'s Freeform canvas and `RegionSelector` (used by Redact/Blur) — these are bespoke `DragGesture`-driven interactions with no visible `.accessibilityLabel`/`.accessibilityValue` modifiers in the files read, which likely means they're mouse/trackpad-only today. Flagging as a probable gap, not a confirmed one — worth a dedicated accessibility pass with Accessibility Inspector.

## Consistency

- **`ToolScaffold` itself is a well-designed shared chrome**: title/subtitle, `DropWell`, `FileList`, options slot, `OutputPicker`, run/secondary/clear buttons with consistent placement, progress bar, `ResultBar` — all in one 100-line component (`ToolScaffold.swift:8-100`) reused by 19 of 28 tool views. Where it's used, tools genuinely feel like one app.
- **Where it isn't used** (7 tool views — see Top Issue #3), each reimplements a subset by hand: `PDFOrganizeView` and `RedactView` both reuse `DropWell`/`FileList`/`MetadataPanel`/`ResultBar` directly but assemble their own header and button row, meaning e.g. Redact's Cancel/Clear affordances and button styling don't quite match a scaffolded tool's. This isn't broken, but it's the kind of inconsistency a paid-app reviewer would flag on a side-by-side screenshot comparison.
- **Recommendation**: the custom views aren't custom because they need to be — Organize Pages' grid and Redact's region-selector preview could both fit inside `ToolScaffold`'s existing `preview:` slot (as `RemoveBackgroundView` and `BlurView` already do successfully with similarly bespoke preview panes). Worth a follow-up pass to migrate at least `PDFOrganizeView` and `RedactView` onto the scaffold, since those two are the highest-traffic of the seven (Organize Pages is free/high-usage; Redact is a flagship Pro feature).

## Functional Bugs

- **No empty/TODO'd closures or unwired buttons found** in the audited views — grep for `TODO`/`FIXME`/empty-closure patterns across `Sources/` returns hits only in `ToolboxLicenseCheck.swift` (the licensing placeholders already covered under Pro/Monetization), none in any View file. Every button read in this pass has a real action.
- **State loss on tool switch, no warning** (Top Issue #5) — reproducible by inspection, not by running the app: `App.swift`'s `detail(for:)` switch means navigating away from and back to Collage (Freeform mode with placed elements) or Organize Pages (reordered/rotated pages) discards that session's `@State`/`@StateObject` with no prompt. Concretely, `CollageView.items` (`CollageView.swift:14`) and `PDFOrganizeView.pages`/`trash` (`PDFOrganizeView.swift:35-36`) have no persistence beyond the view's lifetime, and nothing intercepts the `selection` change to ask "discard your poster?" This is the same underlying mechanism as the intentional "isPreviewing" reset in `RemoveBackgroundView.onClear()` (`:103-114`) — that one is a deliberate, scoped reset; the tool-switch one is an unintended side effect of the navigation architecture, not a designed behavior.
- **`PDFSplitView`/`PDFMergeView` don't show a progress bar** (`model.run` rather than `model.runWithProgress`) — for a single quick in-memory operation this is fine and arguably correct (a progress bar that jumps 0→100% instantly is worse UX than none), noting it only so it isn't mistaken for a missed pattern given every other tool went with `runWithProgress`.

## Tech Debt Risk

- **~150 AVFoundation deprecation warnings**, per this repo's own prior build audit (`AUDIT.md:61-66`) — `duration`, `tracks(withMediaType:)`, and related synchronous APIs deprecated since macOS 13 in favor of the async `AVAsyncProperty`-based replacements. Confirmed these APIs are in active use in exactly the video/audio service layer this pass also read UI for (`VideoService.swift`, `AudioService.swift`, `TranscriptionService.swift`, `FileInfoService.swift` all `import AVFoundation` per the earlier grep). This is real, if not urgent, UX risk: Apple has a track record of eventually hard-removing synchronous AVFoundation APIs behind a future SDK's minimum deployment target, which would silently break Video Convert, Extract Audio, Trim/Merge/Loop Audio, and Transcribe on some future macOS without any UI change signaling it — the kind of regression that shows up as "it just stopped working" support tickets long after the code that caused it shipped. Recommend scheduling the async migration before it becomes an emergency, not after a WWDC removes the old path.
- **Swift 6 concurrency warnings** (also flagged in the prior audit, not independently re-verified in this pass) compound the above: once the AVFoundation migration happens, it's worth doing under strict concurrency checking rather than twice.

---

## Coverage Note

This app has ~27 user-facing tools across 6 categories; this pass read full source for **14 of 28** View files (the 3 free hero PDF tools plus 5 Pro tools spanning PDF/image categories, plus 3 more read for progress/consistency checks) and grep-verified architectural patterns (font discipline, ToolScaffold usage, confirmation-dialog presence, TODO/empty-closure search) across **all 28**. Per-tool UX findings above should be read as representative of the app's patterns, not as a claim that all 27 tools were individually inspected — Image Editor, Icon Generator, QR/Barcode, OCR, Transcribe, PDF Pages/Crop/Sign/Metadata/Page Numbers, Extract Audio, and the three remaining Audio tools were not read in full and could contain tool-specific issues this report doesn't capture.
