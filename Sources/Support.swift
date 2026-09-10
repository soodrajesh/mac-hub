import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// MacHub's identity color — amber/orange, matching the app icon's gradient
/// start. See DESIGN-SYSTEM.md's v2 "modern & colorful" refresh: each app in
/// the mac-apps line now carries its own accent color instead of defaulting
/// to the system accent everywhere. Used on primary actions, tinted sidebar
/// icon tiles, selection highlights, and progress indicators — `Color
/// .accentColor` (the system accent) is still used for the handful of spots
/// that should genuinely follow the user's own macOS accent color choice.
extension Color {
    static let appAccent = Color(red: 0.95, green: 0.55, blue: 0.10)

    /// A distinct warm-but-not-amber tone for the "PRO" badge/upsell accents
    /// only, so Pro branding doesn't visually merge into the app's own
    /// amber accent color used everywhere else.
    static let proAccent = Color(red: 0.83, green: 0.22, blue: 0.48)
}

/// Shared card container for grouping related content — see
/// DESIGN-SYSTEM.md point 3 ("Card-based content, real depth"). Rounded
/// corners, a subtle shadow, a hairline separator stroke, and 16pt padding,
/// replacing the flat panels this app used before v2.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(.separatorColor).opacity(0.5), lineWidth: 1)
            )
    }
}

extension View {
    /// Wraps content in a rounded, softly-shadowed card — see `CardBackground`.
    func cardStyle() -> some View {
        modifier(CardBackground())
    }
}

/// A small tinted rounded-square icon tile — wraps a bare SF Symbol the way
/// System Settings' own sidebar does, instead of leaving it sitting directly
/// on the background. See DESIGN-SYSTEM.md point 1; this is the single
/// highest-impact change for MacHub's long, previously-plain sidebar list.
struct IconTile: View {
    let symbol: String
    var tint: Color = .appAccent
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(tint.opacity(0.15))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .medium))
                    .foregroundStyle(tint)
            )
    }
}

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

/// License status: whether the user has a valid MacHub Pro license.
/// Set by `MacHubApp` after `.task(id: storedLicenseKey)` verifies against
/// Polar (see `MacHubLicenseCheck.swift`) and read by every Pro-gated tool
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
    static let openFiles = Notification.Name("machub.openFiles")
    /// Posted by ⌘R — the visible batch tool runs.
    static let runTool = Notification.Name("machub.runTool")
}
