import SwiftUI
import UniformTypeIdentifiers

struct RemoveBackgroundView: View {
    @StateObject private var model = JobModel(types: [.image])
    @State private var inputImage: NSImage?
    @State private var cutout: CGImage?
    @State private var cutoutURL: URL?
    @State private var previewImage: NSImage?
    @State private var basePreviewImage: NSImage?  // preview before transforms

    @State private var mode: BgMode = .transparent
    @State private var bgColor: Color = .white
    @State private var bgImageURL: URL?
    @State private var bgImageCG: CGImage?
    @State private var info: [MetadataField] = []

    @State private var isPreviewing: Bool = false
    @State private var rotation: Double = 0
    @State private var scale: Double = 1.0

    // Cmd+Z/Cmd+Shift+Z for the Transform controls — there was previously no
    // UndoManager anywhere in this tool, so Cmd+Z had nothing to act on.
    @State private var priorRotation: Double = 0
    @State private var priorScale: Double = 1.0
    @State private var transformUndoStack: [(rotation: Double, scale: Double)] = []
    @State private var transformRedoStack: [(rotation: Double, scale: Double)] = []
    @State private var isApplyingUndoRedo = false

    /// Normalized (0...1) crop selection in image space, drawn by the user
    /// to help Vision focus on the subject when the full-frame result is poor.
    @State private var selectionRect: CGRect?
    @State private var cutoutSelection: CGRect?

    enum BgMode: String, CaseIterable, Identifiable {
        case transparent = "Transparent", color = "Solid color", image = "Image"
        var id: String { rawValue }
    }

    var body: some View {
        ProGate(tool: .removeBackground) {
        ToolScaffold(
            title: "Remove Background",
            subtitle: "Generate preview, adjust as needed, then save.",
            model: model,
            runLabel: isPreviewing ? "Regenerate" : "Generate Preview",
            onRun: generatePreview,
            secondaryLabel: isPreviewing ? "Save" : nil,
            onSecondary: isPreviewing ? save : nil,
            clearLabel: isPreviewing ? "Back" : (selectionRect != nil ? "Clear Selection" : "Clear"),
            onClear: onClear,
            preview: { previewPane }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if !BackgroundService.isAvailable {
                    Label("Requires macOS 14 or later.", systemImage: "exclamationmark.triangle")
                        .appFont(.caption).foregroundStyle(.orange)
                }
                Picker("Background", selection: $mode) {
                    ForEach(BgMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 320)
                .onChange(of: mode) { _ in recomposite() }
                .disabled(isPreviewing)

                switch mode {
                case .transparent:
                    Label("Subject on a transparent PNG.", systemImage: "checkerboard.rectangle")
                        .appFont(.caption).foregroundStyle(.secondary)
                case .color:
                    HStack {
                        ColorPicker("Color", selection: $bgColor, supportsOpacity: false).fixedSize()
                            .onChange(of: bgColor) { _ in recomposite() }
                        ForEach(Array([Color.white, .black, .blue, .green, .red].enumerated()), id: \.offset) { _, c in
                            Button { bgColor = c; recomposite() } label: {
                                Circle().fill(c).frame(width: 16, height: 16).overlay(Circle().strokeBorder(.gray.opacity(0.5)))
                            }.buttonStyle(.plain)
                        }
                    }
                case .image:
                    HStack {
                        Button("Choose background image…") { chooseBg() }
                        if let u = bgImageURL { Text(u.lastPathComponent).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary) }
                    }
                }

                if isPreviewing {
                    Divider()
                    ImageTransformView(
                        rotation: $rotation,
                        scale: $scale,
                        onReset: resetTransforms
                    )
                    .onChange(of: rotation) { _ in recordTransformChange() }
                    .onChange(of: scale) { _ in recordTransformChange() }
                }
            }
        }
        }
        .onChange(of: model.files) { _ in reload() }
        .onChange(of: model.selected) { _ in reload() }
        .background(
            Group {
                Button("Undo", action: undoTransform)
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!isPreviewing || transformUndoStack.isEmpty)
                Button("Redo", action: redoTransform)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!isPreviewing || transformRedoStack.isEmpty)
            }
            .hidden()
        )
    }

    private func reload() {
        cutout = nil; cutoutURL = nil; cutoutSelection = nil
        previewImage = nil; basePreviewImage = nil
        isPreviewing = false; selectionRect = nil
        transformUndoStack.removeAll(); transformRedoStack.removeAll()
        resetTransforms()
        inputImage = model.focused.flatMap { NSImage(contentsOf: $0) }
        info = model.focused.map { FileInfoService.imageFields($0) } ?? []
    }

    /// "Clear" never removes the loaded file (use the file list's own remove
    /// button for that) — it only backs out of preview, or drops the selection.
    private func onClear() {
        if isPreviewing {
            isPreviewing = false
            previewImage = nil; basePreviewImage = nil
            cutout = nil; cutoutURL = nil; cutoutSelection = nil
            transformUndoStack.removeAll(); transformRedoStack.removeAll()
            resetTransforms()
        } else {
            selectionRect = nil
        }
    }

    private var previewPane: some View {
        VStack(spacing: 12) {
            if isPreviewing {
                ImagePreview(image: previewImage, caption: "Result")
            } else if let img = inputImage {
                VStack(spacing: 4) {
                    Text("Drag to select the subject — helps when the full-frame result misses edges")
                        .appFont(.caption).foregroundStyle(.secondary)
                    SelectableImagePreview(
                        image: img,
                        selection: $selectionRect,
                        caption: model.focused?.lastPathComponent
                    )
                }
            } else {
                ImagePreview(image: nil, caption: "Drop an image")
            }

            if !info.isEmpty {
                MetadataPanel(fields: info)
            }
            Spacer(minLength: 0)
        }
    }

    private func background() -> BackgroundService.Background {
        switch mode {
        case .transparent: return .transparent
        case .color: return .color(NSColor(bgColor))
        case .image: return bgImageCG.map { .image($0) } ?? .transparent
        }
    }

    /// Recomposites the cached cutout with the current background (no Vision re-run).
    private func recomposite() {
        guard let cut = cutout else { return }
        let out = BackgroundService.composite(cut, background: background())
        previewImage = NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
    }

    private func chooseBg() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            bgImageURL = url
            bgImageCG = try? ImageService.loadCGImage(url)
            recomposite()
        }
    }

    private func generatePreview() {
        guard let url = model.focused else { model.error = "No image"; return }
        let bg = background()
        let selection = selectionRect
        let reuse = (cutoutURL == url && cutoutSelection == selection) ? cutout : nil
        model.isRunning = true; model.error = nil
        Task.detached(priority: .userInitiated) {
            do {
                let cut: CGImage
                if let reuse {
                    cut = reuse
                } else {
                    let full = try ImageService.loadCGImage(url)
                    var source = full
                    if let norm = selection {
                        let w = CGFloat(full.width), h = CGFloat(full.height)
                        let pixelRect = CGRect(x: norm.minX * w, y: norm.minY * h,
                                                width: norm.width * w, height: norm.height * h).integral
                        source = full.cropping(to: pixelRect) ?? full
                    }
                    cut = try BackgroundService.cutout(source)
                }
                let composed = BackgroundService.composite(cut, background: bg)
                await MainActor.run {
                    cutout = cut; cutoutURL = url; cutoutSelection = selection
                    let img = NSImage(cgImage: composed, size: NSSize(width: composed.width, height: composed.height))
                    basePreviewImage = img
                    previewImage = img
                    isPreviewing = true
                    transformUndoStack.removeAll(); transformRedoStack.removeAll()
                    resetTransforms()
                    model.isRunning = false
                }
            } catch {
                await MainActor.run { model.error = error.localizedDescription; model.isRunning = false }
            }
        }
    }

    private func save() {
        guard let url = model.focused else { model.error = "No image"; return }
        guard let preview = previewImage, let cgImg = preview.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            model.error = "No preview generated"
            return
        }

        let dir = model.outputDir
        model.isRunning = true; model.error = nil; model.result = nil
        Task.detached(priority: .userInitiated) {
            do {
                let out = OutputPath.make(for: url, dir: dir, suffix: "-nobg", ext: "png")
                try ImageService.write(cgImg, to: out, format: .png, quality: 1)
                await MainActor.run {
                    var r = JobResult(); r.outputs.append(out); model.result = r
                    model.isRunning = false
                    isPreviewing = false
                    resetTransforms()
                }
            } catch {
                await MainActor.run { model.error = error.localizedDescription; model.isRunning = false }
            }
        }
    }

    private func resetTransforms() {
        rotation = 0
        scale = 1.0
        priorRotation = 0
        priorScale = 1.0
        // Don't rely solely on the .onChange(of: rotation/scale) modifiers to
        // repaint — if either value was already at its default, setting it
        // again fires no onChange and the preview silently keeps showing the
        // old transformed image. Force the repaint directly so Reset always
        // has a visible effect.
        applyTransforms()
    }

    /// Fires on every rotate/scale change. Snapshots the value it was at
    /// *before* this change onto the undo stack, then applies the new one —
    /// this is what makes Cmd+Z/Cmd+Shift+Z actually do something.
    private func recordTransformChange() {
        guard !isApplyingUndoRedo else { return }
        transformUndoStack.append((priorRotation, priorScale))
        if transformUndoStack.count > 50 { transformUndoStack.removeFirst() }
        transformRedoStack.removeAll()
        priorRotation = rotation
        priorScale = scale
        applyTransforms()
    }

    private func undoTransform() {
        guard let last = transformUndoStack.popLast() else { return }
        transformRedoStack.append((rotation, scale))
        isApplyingUndoRedo = true
        rotation = last.rotation
        scale = last.scale
        isApplyingUndoRedo = false
        priorRotation = rotation
        priorScale = scale
        applyTransforms()
    }

    private func redoTransform() {
        guard let next = transformRedoStack.popLast() else { return }
        transformUndoStack.append((rotation, scale))
        isApplyingUndoRedo = true
        rotation = next.rotation
        scale = next.scale
        isApplyingUndoRedo = false
        priorRotation = rotation
        priorScale = scale
        applyTransforms()
    }

    private func applyTransforms() {
        guard let base = basePreviewImage, let cgImg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        var transformed = cgImg
        if rotation != 0 || scale != 1.0 {
            if let result = ImageTransformer.apply(rotation: rotation, scale: scale, to: transformed) {
                transformed = result
            }
        }

        previewImage = NSImage(cgImage: transformed, size: NSSize(width: transformed.width, height: transformed.height))
    }
}
