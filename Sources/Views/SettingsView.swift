import AppKit
import SwiftUI

/// System/Light/Dark, independent of the Mac's own appearance setting —
/// stored via `@AppStorage` and applied at the app's `WindowGroup` via
/// `.preferredColorScheme`. Mirrors mac-cleanup's `SettingsView.swift`
/// (DESIGN-SYSTEM.md's Settings pane section).
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Small/Medium/Large/Extra Large, backed by `@AppStorage` exactly like
/// `AppearanceMode`, read via `Support.swift`'s `\.textScale` environment
/// key and applied by every view's `.appFont(_:weight:)` call.
enum TextSizeSetting: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small:      return "Small"
        case .medium:     return "Medium"
        case .large:      return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var scaleFactor: CGFloat {
        switch self {
        case .small:      return 0.9
        case .medium:     return 1.0
        case .large:      return 1.15
        case .extraLarge: return 1.3
        }
    }
}

/// The app's one Settings pane (⌘,). Tabbed, native `TabView`, matching
/// mac-cleanup's pattern: Appearance (incl. Text Size), License, About.
struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            LicenseTab()
                .tabItem { Label("License", systemImage: "checkmark.seal") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 420)
    }
}

private struct AppearanceTab: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("textSize") private var textSize = TextSizeSetting.medium

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .appFont(.headline)
                Picker("", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Text Size")
                    .appFont(.headline)
                Picker("", selection: $textSize) {
                    ForEach(TextSizeSetting.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Spacer()
        }
        .padding(20)
    }
}

private struct LicenseTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LicenseManagementView()
            Spacer()
        }
        .padding(20)
    }
}

private struct AboutTab: View {
    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        VStack(alignment: .leading, spacing: 10) {
            Text("Toolbox")
                .appFont(.headline)
            Text("Version \(version)")
                .appFont(.callout)
                .foregroundStyle(.secondary)
            Text("Native macOS PDF & image toolkit. Offline and private — nothing leaves your Mac, except the Video Downloader tool.")
                .appFont(.callout)
                .foregroundStyle(.secondary)

            Button("Report a Bug or Request a Feature…") {
                NSWorkspace.shared.open(URL(string: "https://github.com/soodrajesh")!)
            }
            .buttonStyle(.link)

            Spacer()
        }
        .padding(20)
    }
}
