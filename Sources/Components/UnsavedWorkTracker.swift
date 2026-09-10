import SwiftUI

/// Lets the currently-displayed tool tell the sidebar "I have meaningful
/// in-progress work that would be silently discarded if you switch tools
/// right now." `App.swift`'s `detail(for:)` is a `switch` inside a
/// `@ViewBuilder` — each case is a distinct concrete `View` type, so
/// SwiftUI tears down and reinitializes a tool's `@State`/`@StateObject`
/// the instant `selection` changes away from it. Most tools have nothing
/// worth warning about (a file picker with no edits yet), but Collage
/// (Freeform mode) and Organize Pages are meaningful, time-costly editing
/// sessions with no save/draft state — this is the minimal mechanism to
/// intercept a tool switch for just those two, without a full save/draft
/// system.
///
/// Only one tool is displayed at a time, so a single shared flag (set by
/// whichever tool is currently mounted, read by the sidebar before it lets
/// a switch through) is enough — no need to track per-tool state.
@MainActor
final class UnsavedWorkTracker: ObservableObject {
    @Published var hasUnsavedWork = false
    /// Shown in the discard-confirmation alert; each tool that opts in sets
    /// this to something specific ("your in-progress poster", "your page
    /// order") when it marks itself dirty.
    @Published var description = "your in-progress work"
}
