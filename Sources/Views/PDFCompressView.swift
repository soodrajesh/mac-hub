import SwiftUI
import UniformTypeIdentifiers

struct PDFCompressView: View {
    @StateObject private var model = JobModel(types: [.pdf])
    @State private var dpi = 150.0
    @State private var quality = 0.6
    @State private var info: [MetadataField] = []

    var body: some View {
        ToolScaffold(
            title: "Compress PDF",
            subtitle: "Shrink PDF file size. Great for scanned documents.",
            model: model,
            runLabel: "Compress",
            onRun: run
        ) {
            VStack(alignment: .leading, spacing: 12) {
                MetadataPanel(fields: info)
                HStack {
                    Text("Resolution: \(Int(dpi)) dpi")
                    Slider(value: $dpi, in: 72...300, step: 12).frame(width: 180)
                }
                HStack {
                    Text("JPEG quality: \(Int(quality * 100))%")
                    Slider(value: $quality, in: 0.2...0.9).frame(width: 180)
                }
                Text("Pages with real selectable text are left untouched — only scanned/photo pages are recompressed at the settings above.")
                    .appFont(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.files) { _ in info = model.focused.map { FileInfoService.pdfFields($0) } ?? [] }
        .onChange(of: model.selected) { _ in info = model.focused.map { FileInfoService.pdfFields($0) } ?? [] }
    }

    private func run() {
        let d = dpi, q = quality
        let dir = model.outputDir
        model.runWithProgress { files, report in
            var result = JobResult()
            let total = files.count
            for (i, url) in files.enumerated() {
                if Task.isCancelled { break }
                let out = OutputPath.make(for: url, dir: dir, suffix: "-compressed", ext: "pdf")
                do {
                    try PDFService.compressNative(url, dpi: d, quality: q, to: out)
                    let before = url.fileSize, after = out.fileSize
                    let pct = before > 0 ? Int((1 - Double(after) / Double(before)) * 100) : 0
                    result.outputs.append(out)
                    result.messages.append("\(url.lastPathComponent): \(before.humanBytes) → \(after.humanBytes) (−\(pct)%)")
                } catch {
                    result.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
                report(Double(i + 1) / Double(total))
            }
            return result
        }
    }
}
