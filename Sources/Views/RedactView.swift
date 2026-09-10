import SwiftUI
import UniformTypeIdentifiers

/// Whether the user has already clicked through Redact's irreversibility
/// warning at least once during this app launch. Deliberately a static,
/// in-memory flag (not `@AppStorage`/persisted) — a one-time-per-*session*
/// confirmation, not a permanent "never ask again" preference — so it
/// resets on every relaunch, but survives navigating away from and back to
/// Redact within the same run even though `RedactView` itself is torn down
/// and rebuilt each time (see `App.swift`'s `detail(for:)`).
private enum RedactConfirmationState {
    static var hasConfirmedThisSession = false
}

struct RedactView: View {
    @StateObject private var model = JobModel(types: [.pdf, .image], multiple: false)
    @State private var isPDF = false
    @State private var pageIndex = 0
    @State private var pageCount = 1
    @State private var baseCG: CGImage?          // unredacted current page/image
    @State private var displayImage: NSImage?    // live preview (black boxes composited)
    @State private var rectsByPage: [Int: [CGRect]] = [:]
    @State private var fillColor: Color = .black
    @State private var info: [MetadataField] = []
    @State private var showConfirm = false

    private var currentRects: Binding<[CGRect]> {
        Binding(get: { rectsByPage[pageIndex] ?? [] },
                set: { rectsByPage[pageIndex] = $0 })
    }

    var body: some View {
        ProGate(tool: .redact) {
            ToolScaffold(
                title: "Redact",
                subtitle: "Permanently black out regions in a PDF or image — the content underneath is destroyed, not just hidden.",
                model: model,
                runLabel: "Apply Redaction",
                onRun: attemptApply,
                onClear: resetAll,
                preview: { previewPane },
                options: { optionsPane }
            )
        }
        .onChange(of: model.files) { _ in load() }
        .alert("This can't be undone", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Redact Permanently", role: .destructive) {
                RedactConfirmationState.hasConfirmedThisSession = true
                apply()
            }
        } message: {
            Text("The content under the \(totalRects) box\(totalRects == 1 ? "" : "es") you've drawn is permanently removed from the saved file, not just covered up. This can't be undone.")
        }
    }

    private var totalRects: Int { rectsByPage.values.reduce(0) { $0 + $1.count } }

    // MARK: - Panes

    @ViewBuilder
    private var optionsPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetadataPanel(fields: info)
            if displayImage != nil {
                HStack(spacing: 14) {
                    ColorPicker("Fill color", selection: $fillColor, supportsOpacity: false)
                        .fixedSize()
                        .onChange(of: fillColor) { _ in updatePreview() }
                    ForEach(Array([Color.black, .white, .gray].enumerated()), id: \.offset) { _, c in
                        Button { fillColor = c } label: {
                            Circle().fill(c).frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(.gray.opacity(0.5)))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    Button("Clear page") { rectsByPage[pageIndex] = [] }
                        .disabled(currentRects.wrappedValue.isEmpty)
                    if totalRects > 0 { Text("\(totalRects) box\(totalRects == 1 ? "" : "es") total").appFont(.caption).foregroundStyle(.secondary) }
                }
                Text("This permanently removes the content under every box — it can't be undone.")
                    .appFont(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if let displayImage {
            VStack(alignment: .leading, spacing: 10) {
                if isPDF && pageCount > 1 {
                    HStack {
                        Button { step(-1) } label: { Image(systemName: "chevron.left") }.disabled(pageIndex == 0)
                        Text("Page \(pageIndex + 1) of \(pageCount)")
                        Button { step(1) } label: { Image(systemName: "chevron.right") }.disabled(pageIndex >= pageCount - 1)
                        Spacer()
                        Text("Boxes on this page: \(currentRects.wrappedValue.count)").appFont(.caption).foregroundStyle(.secondary)
                    }
                }

                RegionSelector(image: displayImage, rects: currentRects)
                    .frame(minHeight: 300, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.25)))
                    .onChange(of: rectsByPage) { _ in updatePreview() }

                Text("Live preview — the filled areas are what gets permanently removed.")
                    .appFont(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("Add a PDF or image to begin.").foregroundStyle(.secondary)
        }
    }

    // MARK: - Loading

    private func load() {
        rectsByPage = [:]; pageIndex = 0
        guard let url = model.files.first else { baseCG = nil; displayImage = nil; info = []; return }
        isPDF = url.conformsTo(.pdf)
        if isPDF {
            pageCount = max(1, PDFService.pageCount(url))
            baseCG = PDFService.renderPageCGImage(url, page: 0)
            info = FileInfoService.pdfFields(url)
        } else {
            pageCount = 1
            baseCG = try? ImageService.loadCGImage(url)
            info = FileInfoService.imageFields(url)
        }
        updatePreview()
    }

    private func step(_ d: Int) {
        guard let url = model.files.first else { return }
        pageIndex = min(max(0, pageIndex + d), pageCount - 1)
        baseCG = PDFService.renderPageCGImage(url, page: pageIndex)
        updatePreview()
    }

    /// Composites the current page's black redaction boxes onto the base image.
    private func updatePreview() {
        guard let base = baseCG else { displayImage = nil; return }
        let rects = rectsByPage[pageIndex] ?? []
        let cg = rects.isEmpty ? base : (ImageEditService.redact(base, rects: rects, color: NSColor(fillColor)) ?? base)
        displayImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func resetAll() {
        rectsByPage = [:]; pageIndex = 0; baseCG = nil; displayImage = nil; info = []
        model.clear()
    }

    // MARK: - Apply

    /// Gate in front of `apply()`: refuses to run with no boxes drawn, and —
    /// since this action is explicitly irreversible (destroys, not hides,
    /// the content underneath) — requires a real confirm step the first
    /// time it's used this session rather than committing straight to disk
    /// on a single click.
    private func attemptApply() {
        guard totalRects > 0 else {
            model.error = "Draw at least one box to redact first."
            return
        }
        model.error = nil
        if RedactConfirmationState.hasConfirmedThisSession {
            apply()
        } else {
            showConfirm = true
        }
    }

    private func apply() {
        guard let url = model.files.first else { return }
        model.error = nil; model.result = nil
        do {
            let nsColor = NSColor(fillColor)
            if isPDF {
                let out = OutputPath.make(for: url, dir: model.outputDir, suffix: "-redacted", ext: "pdf")
                try PDFService.redact(url, rectsByPage: rectsByPage, to: out, color: nsColor)
                var r = JobResult(); r.outputs.append(out); r.messages.append("Redacted → \(out.lastPathComponent)")
                model.result = r
            } else {
                let cg = try ImageService.loadCGImage(url)
                guard let out = ImageEditService.redact(cg, rects: rectsByPage[0] ?? [], color: nsColor) else {
                    throw JobError.failed("Could not redact")
                }
                let dst = OutputPath.make(for: url, dir: model.outputDir, suffix: "-redacted", ext: "png")
                try ImageService.write(out, to: dst, format: .png, quality: 1)
                var r = JobResult(); r.outputs.append(dst); r.messages.append("Redacted → \(dst.lastPathComponent)")
                model.result = r
            }
        } catch { model.error = error.localizedDescription }
    }
}
