import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The app's Text Size setting, in points-per-style plus a per-view
/// `.appFont(_:weight:)` modifier — deliberately *not* SwiftUI's
/// `.dynamicTypeSize`/`Font.TextStyle`, because Dynamic Type is an iOS/
/// iPadOS/tvOS/watchOS mechanism with no effect on macOS (verified in
/// mac-cleanup: setting it and comparing screenshots at Medium vs. Extra
/// Large showed zero visual difference — `Font.TextStyle` sizes on macOS
/// are fixed AppKit control sizes that don't respond to the environment's
/// dynamicTypeSize at all). This reimplements the same idea with a real
/// effect: a scale factor read from the environment, applied to a fixed
/// base point size per semantic role, computed fresh at render time so
/// Settings changes apply live. Mirrors mac-cleanup's Support.swift —
/// see DESIGN-SYSTEM.md.
private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

/// License status: whether the user has a valid MacPress Pro license.
/// Set by `MacPressApp` after `.task(id: storedLicenseKey)` verifies against
/// Polar (see `MacPressLicenseCheck.swift`) and read by every Pro-gated tool
/// view via `ProGate` (Components/ProUpsell.swift). Settings has its own
/// independent verification (Settings is its own Scene, doesn't inherit
/// this environment) — see `LicenseManagementView`.
private struct IsProLicensedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isProLicensed: Bool {
        get { self[IsProLicensedKey.self] }
        set { self[IsProLicensedKey.self] = newValue }
    }
}

/// One semantic role → one base point size, matching macOS's own
/// approximate `NSFont.preferredFont(forTextStyle:)` values — the same
/// roles this app used as raw SwiftUI `Font.TextStyle`s before, so this is
/// a drop-in replacement for `.font(.caption)` etc., not a new vocabulary.
enum AppFontStyle {
    case largeTitle, title, title2, title3
    case headline, body, callout, subheadline, footnote, caption, caption2

    var basePointSize: CGFloat {
        switch self {
        case .largeTitle:  return 26
        case .title:       return 22
        case .title2:      return 17
        case .title3:      return 15
        case .headline:    return 13
        case .body:        return 13
        case .callout:     return 12
        case .subheadline: return 11
        case .footnote:    return 10
        case .caption:     return 10
        case .caption2:    return 10
        }
    }

    /// SwiftUI's real `.headline` renders semibold, not regular — every
    /// other style here defaults to regular (see mac-cleanup's own note on
    /// this — a font-sweep conversion that dropped it silently was a real
    /// regression there, so this app's helper carries the fix from day one).
    var defaultWeight: Font.Weight {
        self == .headline ? .semibold : .regular
    }
}

private struct ScaledFontModifier: ViewModifier {
    @Environment(\.textScale) private var scale
    let style: AppFontStyle
    let weight: Font.Weight?
    var design: Font.Design = .default

    func body(content: Content) -> some View {
        content.font(.system(size: style.basePointSize * scale, weight: weight ?? style.defaultWeight, design: design))
    }
}

extension View {
    /// Replaces `.font(.caption)`, `.font(.headline)`, `.font(.title2).bold()`,
    /// etc. throughout the app — every call site needs this instead of a raw
    /// `Font.TextStyle` for Settings' Text Size to have any real effect.
    func appFont(_ style: AppFontStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ScaledFontModifier(style: style, weight: weight))
    }

    /// Same as `appFont`, but monospaced — for code/URL/output text that
    /// still needs to respond to the Text Size setting. Covers the cases
    /// that used to fall back to raw `.font(.system(.body, design:
    /// .monospaced))`, which doesn't scale with `textScale`.
    func appFont(_ style: AppFontStyle, weight: Font.Weight? = nil, design: Font.Design) -> some View {
        modifier(ScaledFontModifier(style: style, weight: weight, design: design))
    }
}

/// GUI apps launch with a stripped-down PATH that omits /opt/homebrew/bin and
/// /usr/local/bin, so subprocesses (and their own internal `which`-style
/// lookups, e.g. yt-dlp searching for `deno`) can fail to find Homebrew-
/// installed tools that are actually present. Use `extendedEnvironment()` for
/// any `Process` that shells out to, or itself shells out to, such a tool.
enum PathHelper {
    static func extendedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let existingComponents = Set(existingPath.split(separator: ":").map(String.init))
        let prefix = extraPaths.filter { !existingComponents.contains($0) }
        env["PATH"] = (prefix + [existingPath]).joined(separator: ":")
        return env
    }
}

/// Shared filesystem helpers for building output paths.
enum OutputPath {
    /// Returns a URL next to `source` (or in `dir` if given) named
    /// `<base><suffix>.<ext>`, bumping `-1`, `-2`… until it doesn't collide.
    static func make(for source: URL, dir: URL?, suffix: String, ext: String) -> URL {
        let folder = dir ?? source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = folder.appendingPathComponent("\(base)\(suffix).\(ext)")
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)\(suffix)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }

    /// A fresh temp file with the given extension.
    static func temp(ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
    }

    /// Swaps a URL's extension (e.g. when a chosen output format turns out to
    /// need a different container than originally planned).
    static func retype(_ url: URL, ext: String) -> URL {
        url.deletingPathExtension().appendingPathExtension(ext)
    }
}

extension Int64 {
    var humanBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension URL {
    var fileSize: Int64 {
        (try? resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }
}

/// Reveal outputs in Finder.
func revealInFinder(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
}

extension Notification.Name {
    /// Posted by ⌘O — the visible tool's drop well opens a file panel.
    static let openFiles = Notification.Name("macpress.openFiles")
    /// Posted by ⌘R — the visible batch tool runs.
    static let runTool = Notification.Name("macpress.runTool")
}
