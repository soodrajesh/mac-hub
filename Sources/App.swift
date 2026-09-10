import SwiftUI

@main
struct ToolboxApp: App {
    private static let collapsedSectionsKey = "collapsedSidebarSections"

    @State private var selection: Tool = .pdfCompress
    @State private var collapsedSections: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: ToolboxApp.collapsedSectionsKey) ?? [])

    // Tool-switch discard confirmation (Collage Freeform / Organize Pages) —
    // see UnsavedWorkTracker's doc comment.
    @StateObject private var unsavedWork = UnsavedWorkTracker()
    @State private var pendingSelection: Tool?
    @State private var showDiscardConfirm = false

    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("textSize") private var textSize = TextSizeSetting.medium

    // License verification for the main window. Settings verifies
    // independently (it's its own Scene, doesn't inherit this environment)
    // — see LicenseManagementView.
    @AppStorage(ToolboxLicenseConfig.licenseKeyStorageKey) private var storedLicenseKey = ""
    @State private var isProLicensed = false

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List(selection: selectionBinding) {
                    ForEach(Tool.sections, id: \.name) { section in
                        Section {
                            if !collapsedSections.contains(section.name) {
                                ForEach(section.tools) { tool in
                                    Label {
                                        HStack(spacing: 6) {
                                            Text(tool.rawValue)
                                            if tool.isPro { ProBadge() }
                                        }
                                    } icon: {
                                        Image(systemName: tool.symbol)
                                    }
                                    .tag(tool)
                                }
                            }
                        } header: {
                            sectionHeader(section.name)
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
                .listStyle(.sidebar)
            } detail: {
                detail(for: selection)
                    .frame(minWidth: 560, minHeight: 460)
            }
            .navigationTitle("Toolbox")
            .preferredColorScheme(appearanceMode.colorScheme)
            .environment(\.textScale, textSize.scaleFactor)
            .environment(\.isProLicensed, isProLicensed)
            .environmentObject(unsavedWork)
            .alert("Discard \(unsavedWork.description)?", isPresented: $showDiscardConfirm) {
                Button("Cancel", role: .cancel) { pendingSelection = nil }
                Button("Discard", role: .destructive) { confirmDiscardAndSwitch() }
            } message: {
                Text("Switching tools now will discard it — it hasn't been saved.")
            }
            // `.task(id:)`, not `.onAppear` — `onAppear` can refire when a
            // system permission dialog interrupts and restores the window,
            // silently re-triggering verification each time. `.task(id:)`
            // also re-runs whenever the stored key changes (entered,
            // updated, or cleared) — no separate trigger needed for that.
            .task(id: storedLicenseKey) {
                await verifyLicense()
            }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { NotificationCenter.default.post(name: .openFiles, object: nil) }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Tool") {
                Button("Run / Process") { NotificationCenter.default.post(name: .runTool, object: nil) }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(appearanceMode.colorScheme)
        }
    }

    /// Tools whose in-progress state is worth protecting with a discard
    /// prompt — see `UnsavedWorkTracker`.
    private static let discardWarningTools: Set<Tool> = [.collage, .pdfOrganize]

    /// Wraps `selection` so a switch away from a tool with unsaved,
    /// meaningful in-progress work (Collage Freeform, Organize Pages) asks
    /// for confirmation instead of silently discarding it.
    private var selectionBinding: Binding<Tool> {
        Binding(
            get: { selection },
            set: { newValue in
                guard newValue != selection else { return }
                if unsavedWork.hasUnsavedWork, Self.discardWarningTools.contains(selection) {
                    pendingSelection = newValue
                    showDiscardConfirm = true
                } else {
                    selection = newValue
                    unsavedWork.hasUnsavedWork = false
                }
            }
        )
    }

    private func confirmDiscardAndSwitch() {
        if let pending = pendingSelection { selection = pending }
        unsavedWork.hasUnsavedWork = false
        pendingSelection = nil
    }

    private func verifyLicense() async {
        guard !storedLicenseKey.isEmpty else {
            // Don't skip this — clearing the key must actually revoke Pro
            // access immediately, not leave isProLicensed stuck at
            // whatever it was before until relaunch.
            isProLicensed = false
            return
        }
        do {
            let license = try await LicenseChecker().verify(licenseKey: storedLicenseKey)
            isProLicensed = license.isValid
        } catch {
            isProLicensed = false
        }
    }

    @ViewBuilder
    private func sectionHeader(_ name: String) -> some View {
        let isCollapsed = collapsedSections.contains(name)
        Button {
            toggleSection(name)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .appFont(.caption2, weight: .bold)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 10)
                Text(name)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleSection(_ name: String) {
        if collapsedSections.contains(name) { collapsedSections.remove(name) }
        else { collapsedSections.insert(name) }
        UserDefaults.standard.set(Array(collapsedSections), forKey: Self.collapsedSectionsKey)
    }

    @ViewBuilder
    private func detail(for tool: Tool) -> some View {
        switch tool {
        case .pdfCompress: PDFCompressView()
        case .pdfMerge:    PDFMergeView()
        case .pdfSplit:    PDFSplitView()
        case .pdfPages:    PDFPagesView()
        case .pdfOrganize: PDFOrganizeView()
        case .pdfSecurity: PDFSecurityView()
        case .pdfSign:     PDFSignView()
        case .pdfNumbers:  PDFPageNumbersView()
        case .pdfMeta:     PDFMetadataView()
        case .pdfCrop:     PDFCropView()
        case .imageTools:  ImageToolsView()
        case .imageEdit:   ImageEditView()
        case .blur:        BlurView()
        case .redact:      RedactView()
        case .collage:     CollageView()
        case .iconGen:     IconGeneratorView()
        case .removeBG:    RemoveBackgroundView()
        case .watermark:   WatermarkView()
        case .qr:          QRCodeView()
        case .ocr:         OCRView()
        case .transcribe:  TranscriptionView()
        case .videoDownload: YouTubeDownloadView()
        case .videoConvert:  VideoConvertView()
        case .videoExtractAudio: VideoExtractAudioView()
        case .audioTrim:   AudioTrimView()
        case .audioMerge:  AudioMergeView()
        case .audioLoop:   AudioLoopView()
        }
    }
}
