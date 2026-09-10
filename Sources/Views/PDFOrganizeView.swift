import SwiftUI
import UniformTypeIdentifiers

/// One page in the working order: which page of the source it came from, an
/// additional rotation on top of whatever rotation it already had, and a
/// lazily-loaded thumbnail.
private struct PageItem: Identifiable {
    let id = UUID()
    let originalIndex: Int
    var rotation: Int = 0
    var thumbnail: NSImage?
}

/// Drag-to-reorder support for the thumbnail grid: dropping onto another cell
/// moves the dragged page to that position.
private struct PageDropDelegate: DropDelegate {
    let target: PageItem
    @Binding var pages: [PageItem]
    @Binding var draggingID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != target.id,
              let from = pages.firstIndex(where: { $0.id == draggingID }),
              let to = pages.firstIndex(where: { $0.id == target.id }) else { return }
        withAnimation {
            pages.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { draggingID = nil; return true }
}

struct PDFOrganizeView: View {
    @EnvironmentObject private var unsavedWork: UnsavedWorkTracker
    @StateObject private var model = JobModel(types: [.pdf], multiple: false)
    @State private var pages: [PageItem] = []
    @State private var trash: [PageItem] = []
    @State private var draggingID: UUID?
    @State private var info: [MetadataField] = []
    /// True once the working order has been touched (reorder/rotate/
    /// remove/restore) since the last load or save — see
    /// `UnsavedWorkTracker`'s doc comment.
    @State private var isDirty = false

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 160), spacing: 14)]

    var body: some View {
        ToolScaffold(
            title: "Organize Pages",
            subtitle: "Visually reorder, rotate, or remove pages, then save as a new PDF. Drag a thumbnail to move it.",
            model: model,
            runLabel: "Save as New PDF",
            onRun: run,
            previewVisible: !pages.isEmpty || !trash.isEmpty,
            secondaryLabel: (!pages.isEmpty || !trash.isEmpty) ? "Reset" : nil,
            onSecondary: (!pages.isEmpty || !trash.isEmpty) ? loadPages : nil,
            onClear: clearAll,
            preview: { pagesPane },
            options: { MetadataPanel(fields: info) }
        )
        .onChange(of: model.files) { _ in
            loadPages()
            info = model.files.first.map { FileInfoService.pdfFields($0) } ?? []
        }
        .onChange(of: isDirty) { dirty in
            unsavedWork.hasUnsavedWork = dirty
            if dirty { unsavedWork.description = "your in-progress page order" }
        }
    }

    // MARK: Preview pane (page grid + trash tray)

    @ViewBuilder
    private var pagesPane: some View {
        if pages.isEmpty && trash.isEmpty {
            Text("Add a PDF to begin.").foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if !pages.isEmpty {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(pages) { item in
                            cell(item)
                                .onDrag { draggingID = item.id; return NSItemProvider(object: item.id.uuidString as NSString) }
                                .onDrop(of: [.text], delegate: PageDropDelegate(target: item, pages: $pages, draggingID: $draggingID))
                        }
                    }
                    .onChange(of: pages.map(\.id)) { _ in isDirty = true }
                }

                if !trash.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Removed (\(trash.count)) — tap to restore")
                            .appFont(.caption).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(trash) { item in
                                    trashThumb(item)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Cells

    private func cell(_ item: PageItem) -> some View {
        let idx = pages.firstIndex(where: { $0.id == item.id })
        return VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.12))
                if let thumb = item.thumbnail {
                    Image(nsImage: thumb).resizable().scaledToFit()
                        .rotationEffect(.degrees(Double(item.rotation)))
                        .padding(4)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 128, height: 165)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.gray.opacity(0.3)))
            .overlay(alignment: .topLeading) {
                Button { rotate(item) } label: { Image(systemName: "rotate.right") }
                    .buttonStyle(.borderless).controlSize(.mini)
                    .padding(4).background(.thinMaterial, in: Circle()).padding(3)
            }
            .overlay(alignment: .topTrailing) {
                Button { remove(item) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).controlSize(.mini).foregroundStyle(.red)
                    .padding(4).background(.thinMaterial, in: Circle()).padding(3)
            }
            Text("Page \(item.originalIndex + 1)\(idx != nil ? "  ·  #\(idx! + 1)" : "")")
                .appFont(.caption2).foregroundStyle(.secondary)
        }
    }

    private func trashThumb(_ item: PageItem) -> some View {
        Button { restore(item) } label: {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(Color.gray.opacity(0.1))
                    if let thumb = item.thumbnail {
                        Image(nsImage: thumb).resizable().scaledToFit()
                            .rotationEffect(.degrees(Double(item.rotation))).padding(3)
                            .opacity(0.5)
                    }
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .appFont(.title3).foregroundStyle(.secondary)
                }
                .frame(width: 64, height: 82)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.gray.opacity(0.25)))
                Text("Page \(item.originalIndex + 1)").appFont(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func rotate(_ item: PageItem) {
        guard let i = pages.firstIndex(where: { $0.id == item.id }) else { return }
        pages[i].rotation = (pages[i].rotation + 90) % 360
        isDirty = true
    }

    private func remove(_ item: PageItem) {
        guard let i = pages.firstIndex(where: { $0.id == item.id }) else { return }
        trash.append(pages.remove(at: i))
        isDirty = true
    }

    private func restore(_ item: PageItem) {
        guard let i = trash.firstIndex(where: { $0.id == item.id }) else { return }
        pages.append(trash.remove(at: i))
        isDirty = true
    }

    private func loadPages() {
        pages = []; trash = []; isDirty = false
        guard let url = model.files.first else { return }
        let count = PDFService.pageCount(url)
        pages = (0..<count).map { PageItem(originalIndex: $0) }
        for i in 0..<count {
            Task.detached(priority: .userInitiated) {
                let thumb = PDFService.renderPageImage(url, page: i, dpi: 45)
                await MainActor.run {
                    guard model.files.first == url else { return }
                    if let idx = pages.firstIndex(where: { $0.originalIndex == i }) { pages[idx].thumbnail = thumb }
                    else if let idx = trash.firstIndex(where: { $0.originalIndex == i }) { trash[idx].thumbnail = thumb }
                }
            }
        }
    }

    private func clearAll() {
        pages = []; trash = []; isDirty = false
        model.clear()
    }

    private func run() {
        guard let src = model.files.first else { return }
        guard !pages.isEmpty else { model.error = "No pages left to save — restore at least one from Removed."; return }
        let dir = model.outputDir
        let order = pages.map { (originalIndex: $0.originalIndex, rotation: $0.rotation) }
        let count = order.count
        model.run { _ in
            var r = JobResult()
            let out = OutputPath.make(for: src, dir: dir, suffix: "-organized", ext: "pdf")
            try PDFService.organize(src, order: order, to: out)
            r.outputs.append(out)
            r.messages.append("\(count) page\(count == 1 ? "" : "s") → \(out.lastPathComponent)")
            return r
        }
        isDirty = false
    }
}
