import AppKit
import SwiftUI

/// One entry per Pro-gated tool. Carries what a locked view needs to show a
/// real upsell (title, one-line pitch, and 2-4 concrete capabilities) — the
/// point is that someone who opens a Pro tool while unlicensed should
/// *discover* what it does and want it, not just see a generic paywall.
enum ProTool {
    case convertCompress, watermark, cropTrim, redact, removeBackground
    case collage, iconGenerator, pdfSecurity, pageNumbers, blur

    var title: String {
        switch self {
        case .convertCompress: return "Convert & Compress"
        case .watermark:       return "Watermark"
        case .cropTrim:        return "Crop / Trim Margins"
        case .redact:          return "Redact"
        case .removeBackground: return "Remove Background"
        case .collage:          return "Collage"
        case .iconGenerator:    return "Icon Generator"
        case .pdfSecurity:      return "PDF Security"
        case .pageNumbers:      return "Page Numbers"
        case .blur:             return "Blur / Pixelate"
        }
    }

    var symbol: String {
        switch self {
        case .convertCompress: return "photo"
        case .watermark:        return "seal"
        case .cropTrim:         return "crop"
        case .redact:           return "rectangle.fill.badge.xmark"
        case .removeBackground: return "wand.and.stars"
        case .collage:           return "square.grid.2x2"
        case .iconGenerator:     return "app.badge"
        case .pdfSecurity:       return "lock.doc"
        case .pageNumbers:       return "list.number"
        case .blur:              return "eye.slash"
        }
    }

    var pitch: String {
        switch self {
        case .convertCompress: return "Batch-convert and compress a whole folder of images at once — HEIC → JPEG, format swaps, size caps, all in one run."
        case .watermark:        return "Stamp a text or logo watermark across many images in a single batch, instead of one at a time."
        case .cropTrim:         return "Trim whitespace margins from every page of many PDFs at once, losslessly."
        case .redact:           return "Permanently black out sensitive regions in a PDF or image before you share it — content underneath is destroyed, not just covered."
        case .removeBackground: return "One-click subject cutout, with a live preview and a transparent, solid-color, or custom-image background."
        case .collage:           return "Combine images into a grid, or build a fully freeform poster — drag, resize, rotate, and add text."
        case .iconGenerator:     return "Turn one image into a complete favicon.ico + PNG set + AppIcon.icns in one step."
        case .pdfSecurity:       return "Password-protect, unlock, or watermark PDFs before sending them out."
        case .pageNumbers:       return "Stamp page numbers or a custom label onto every page of a PDF."
        case .blur:              return "Hide faces, addresses, or numbers with blur or pixelation — including automatic face detection."
        }
    }

    var bullets: [String] {
        switch self {
        case .convertCompress:
            return ["Batch process an entire folder", "Format conversion incl. HEIC → JPEG", "Quality + max-size controls", "EXIF/GPS always stripped"]
        case .watermark:
            return ["Text or logo watermark", "Any corner, center, or tiled", "Batch — apply to many images at once", "Adjustable size & opacity"]
        case .cropTrim:
            return ["Batch trims many PDFs at once", "Uniform or per-side margins", "Lossless — sets the PDF crop box"]
        case .redact:
            return ["Works on PDFs and images", "Multi-page PDF support", "Live preview before you commit", "Content is destroyed, not hidden"]
        case .removeBackground:
            return ["On-device subject cutout (Vision)", "Transparent, solid, or image background", "Live preview + rotate/scale"]
        case .collage:
            return ["Grid, horizontal, or vertical layouts", "Freeform: drag/resize/rotate + text", "Exports full-resolution PNG"]
        case .iconGenerator:
            return ["favicon.ico (multi-resolution)", "Full PNG set, 16–1024px", "AppIcon.icns for macOS apps"]
        case .pdfSecurity:
            return ["Add or remove a password", "Diagonal watermark stamping", "Batch — apply to many PDFs at once"]
        case .pageNumbers:
            return ["Custom format ({n} / {total})", "Any corner or edge position", "Custom start number & font size"]
        case .blur:
            return ["Drag to blur or pixelate regions", "Auto-detect faces (Vision)", "Live preview before saving"]
        }
    }
}

/// Wraps a Pro-gated tool's content: shows it when licensed, otherwise
/// shows `ProUpsellView` for that tool instead — never hides or silently
/// disables the tool, so someone browsing the sidebar still discovers it
/// exists and sees exactly what it does.
struct ProGate<Content: View>: View {
    @Environment(\.isProLicensed) private var isProLicensed
    let tool: ProTool
    @ViewBuilder var content: () -> Content

    var body: some View {
        if isProLicensed {
            content()
        } else {
            ProUpsellView(tool: tool)
        }
    }
}

/// The upsell shown in place of a locked Pro tool's own view.
struct ProUpsellView: View {
    let tool: ProTool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        IconTile(symbol: tool.symbol, tint: .appAccent, size: 30)
                        Text(tool.title)
                            .appFont(.title2, weight: .bold)
                        ProBadge()
                    }
                    Text(tool.pitch)
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tool.bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .appFont(.callout)
                            Text(bullet)
                                .appFont(.callout)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: 460, alignment: .leading)
                .cardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Unlock \(tool.title) with MacHub Pro")
                        .appFont(.headline)
                    Text("MacHub Pro unlocks every batch tool plus Redact, Remove Background, Collage, Icon Generator, PDF Security, Page Numbers, and Blur/Pixelate with auto-detect faces.")
                        .appFont(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 460, alignment: .leading)

                    if MacHubLicenseConfig.isConfigured {
                        HStack(spacing: 10) {
                            Button(action: openPurchasePage) {
                                Text("Unlock Pro")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.proAccent)

                            Button(action: openLicenseSettings) {
                                Text("I already have a license")
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        // Placeholder Polar org/checkout URL — see
                        // MacHubLicenseConfig's TODOs. Say so plainly
                        // instead of showing a button to a dead checkout
                        // link or letting a real key 404 and read as
                        // "invalid."
                        Label("MacHub Pro isn't available for purchase yet — check back soon.", systemImage: "clock")
                            .appFont(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.proAccent.opacity(0.08))
                .cornerRadius(10)

                Spacer()
            }
            .padding(20)
        }
    }

    private func openPurchasePage() {
        guard let url = URL(string: MacHubLicenseConfig.purchaseURL) else { return }
        NSWorkspace.shared.open(url)
    }

    /// macOS 13-compatible way to open Settings (⌘,) from a normal view —
    /// `@Environment(\.openSettings)` needs macOS 14, and this app's
    /// `LSMinimumSystemVersion` is 13.0.
    private func openLicenseSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

/// Small "PRO" pill used next to a gated tool's title and in the sidebar.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .appFont(.caption2, weight: .bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.proAccent.opacity(0.18))
            .foregroundStyle(Color.proAccent)
            .clipShape(Capsule())
    }
}
