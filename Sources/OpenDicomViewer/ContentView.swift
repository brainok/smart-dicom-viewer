// ContentView.swift
// OpenDicomViewer
//
// Root view of the application. Implements a NavigationSplitView with:
//   - Sidebar: file open button, series list with thumbnails and panel indicators
//   - Detail: multi-panel DICOM viewer with floating layout toolbar
//
// Also handles all keyboard shortcuts and file drag-and-drop.
//
// Key types:
//   ContentView       — Top-level split view + keyboard routing
//   SidebarView       — Open button + series list
//   SeriesListView    — Scrollable list of series with panel assignment indicators
//   SeriesRow         — Single series row: thumbnail, description, panel grid icon
//   PanelPositionIndicator — Miniature grid showing which panels display a series
//   DetailView        — Legacy single-panel detail (used as fallback)
// Licensed under the MIT License. See LICENSE for details.

import SwiftUI
import UniformTypeIdentifiers
import QuartzCore
import AppKit

private func makeSeriesDragProvider(index: Int, suggestedName: String? = nil) -> NSItemProvider {
    let text = "\(index)"
    let provider = NSItemProvider(object: text as NSString)
    provider.suggestedName = suggestedName
    provider.registerDataRepresentation(forTypeIdentifier: DragPasteboardTypes.seriesIndexIdentifier, visibility: .all) { completion in
        completion(Data(text.utf8), nil)
        return nil
    }
    provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
        completion(Data(text.utf8), nil)
        return nil
    }
    return provider
}



struct ContentView: View {
    @ObservedObject var model: DICOMModel
    @ObservedObject var licenseManager: LicenseManager
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model, columnVisibility: $columnVisibility)
            .navigationSplitViewColumnWidth(min: 220, ideal: 330, max: 520)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            HStack(spacing: 0) {
                // Fixed tool palette column
                ToolPalette(model: model)
                    .padding(.vertical, 8)

                // Main viewer area
                ZStack(alignment: .topLeading) {
                    // Multi-panel container replaces old single DetailView
                    MultiPanelContainer(model: model, isFocused: $isFocused)
                        .onDrop(of: DropItemResolver.acceptedTypes, isTargeted: nil) { providers in
                            handleDrop(providers: providers)
                        }
                        .onTapGesture {
                            isFocused = true
                        }

                    PatientTopBanner(model: model)
                        .padding(.leading, 82)
                        .padding(.top, 9)
                        .zIndex(70)

                    // Floating controls overlay
                    VStack {
                        HStack(alignment: .top) {
                            // Sidebar toggle (when hidden)
                            if columnVisibility == .detailOnly {
                                Button(action: { columnVisibility = .all }) {
                                    Image(systemName: "sidebar.right")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                        .padding(8)
                                        .background(.ultraThinMaterial)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .help("Show Sidebar")
                                .padding(.leading, 70)
                            }

                            Spacer()

                            // Layout toolbar + Tag toggle
                            HStack(spacing: 8) {
                                LayoutToolbar(model: model)

                                Button(action: { model.showTags.toggle() }) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Image(systemName: "tag")
                                            .font(.system(size: 16))
                                            .foregroundStyle(model.showTags ? .white : .secondary)
                                            .padding(8)

                                        Text("T")
                                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.secondary)
                                            .offset(x: -2, y: -2)
                                    }
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .help("Toggle Tags (T)")
                            }
                        }
                        .padding()

                        Spacer()
                    }
                }
                .onDrop(of: DropItemResolver.acceptedTypes, isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        // Keyboard Handlers — route through active panel
        .disabled(licenseManager.requiresActivation)
        .overlay {
            if licenseManager.requiresActivation {
                trialExpiredOverlay
            }
        }
        .focusable()
        .focused($isFocused)
        .onAppear {
            isFocused = true
            licenseManager.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .licenseStateDidChange)) { _ in
            isFocused = true
        }
        .onKeyPress(.leftArrow) {
            if let panel = model.activePanel {
                model.navigatePanelByOffset(panel, offset: -1)
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if let panel = model.activePanel {
                model.navigatePanelByOffset(panel, offset: 1)
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if let panel = model.activePanel {
                model.navigatePanel(panel, direction: .prevSeries)
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if let panel = model.activePanel {
                model.navigatePanel(panel, direction: .nextSeries)
            }
            return .handled
        }
        .onKeyPress(.tab) {
            cyclePanelForward()
            return .handled
        }
        .onKeyPress(.pageUp) {
            if let panel = model.activePanel {
                model.navigatePanelByOffset(panel, offset: -10)
            }
            return .handled
        }
        .onKeyPress(.pageDown) {
            if let panel = model.activePanel {
                model.navigatePanelByOffset(panel, offset: 10)
            }
            return .handled
        }
        .onKeyPress(.home) {
            if let panel = model.activePanel {
                model.navigatePanelToEdge(panel, toFirst: true)
            }
            return .handled
        }
        .onKeyPress(.end) {
            if let panel = model.activePanel {
                model.navigatePanelToEdge(panel, toFirst: false)
            }
            return .handled
        }
        .onKeyPress(phases: .down) { press in
            // Letter/number shortcuts are handled by NSEvent keyDown monitor in DICOMModel
            // (works regardless of input method). This handler covers special keys only.

            // Space = Toggle cine playback
            if press.key == .space {
                if let panel = model.activePanel, panel.isMultiFrame && panel.numberOfFrames > 1 {
                    model.toggleCinePlayback(panel)
                    return .handled
                }
            }

            // Escape = Clear group selection
            if press.key == .escape {
                if model.groupSelectedPanels.count > 0 {
                    model.clearGroupSelection()
                    return .handled
                }
            }

            return .ignored
        }
        .inspector(isPresented: $model.showTags) {
            Group {
                let activeTags = model.selectedDerivedObjectID == nil ? (model.activePanel?.tags ?? []) : model.tags
                if activeTags.isEmpty {
                    ContentUnavailableView("No Tags", systemImage: "tag.slash")
                } else {
                    TagView(tags: activeTags)
                }
            }
            .id(model.selectedDerivedObjectID?.absoluteString ?? model.activePanelID.uuidString)
        }
        .sheet(isPresented: $model.showHelp) {
            HelpView()
        }
        .sheet(isPresented: $model.showAbout) {
            AboutView()
        }
        .sheet(isPresented: $licenseManager.showActivation) {
            ActivationView(
                licenseManager: licenseManager,
                canDismiss: !licenseManager.requiresActivation
            )
            .interactiveDismissDisabled(licenseManager.requiresActivation)
        }
        .sheet(isPresented: $model.showAnonymizeSheet) {
            AnonymizeFolderDialog(model: model)
        }
        .sheet(isPresented: $model.showPresetEditor) {
            WindowLevelPresetEditor(model: model)
        }
        .preferredColorScheme(.dark)
        .background(WindowAccessor(model: model))
    }

    // MARK: - Handlers

    private var trialExpiredOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.circle")
                .font(.system(size: 42))
                .foregroundStyle(.orange)

            Text("Activation Required")
                .font(.title2.bold())

            Text("The 30-day trial has ended. Activate with a Brainok license to keep using Smart DICOM Viewer.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            Button("Activate License") {
                licenseManager.showActivation = true
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 24)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        DropItemResolver.handle(
            providers: providers,
            onSeriesIndex: { index in assignDroppedSeries(index) },
            onURL: { url in model.load(url: url) }
        )
    }

    private func assignDroppedSeries(_ index: Int) {
        guard index >= 0, index < model.allSeries.count else { return }
        model.clearSelectedDerivedObject()
        if let panel = model.activePanel {
            model.assignSeriesToPanel(panel, seriesIndex: index)
        } else if let first = model.allSeries[index].images.first {
            model.currentSeriesIndex = index
            model.currentImageIndex = 0
            model.loadSingleFile(first.url)
        }
    }

    private func cyclePanelForward() {
        guard model.panels.count > 1 else { return }
        if let currentIndex = model.panels.firstIndex(where: { $0.id == model.activePanelID }) {
            let nextIndex = (currentIndex + 1) % model.panels.count
            model.activePanelID = model.panels[nextIndex].id
        }
    }
}

struct PatientTopBanner: View {
    @ObservedObject var model: DICOMModel

    private var patientLine: String? {
        guard let panel = model.activePanel,
              panel.seriesIndex >= 0,
              panel.seriesIndex < model.allSeries.count else { return nil }
        let series = model.allSeries[panel.seriesIndex]
        var parts: [String] = []
        if let id = clean(series.patientID) { parts.append("ID \(id)") }
        if let name = clean(series.patientName) { parts.append(name) }
        if let sex = clean(series.patientSex) { parts.append(sex.uppercased()) }
        if let age = formattedAge(series.patientAge) { parts.append(age) }
        return parts.isEmpty ? nil : parts.joined(separator: "  |  ")
    }

    var body: some View {
        if let patientLine {
            Text(patientLine)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.36))
                .cornerRadius(6)
                .allowsHitTesting(false)
        }
    }

    private func clean(_ value: String?) -> String? {
        let cleaned = value?
            .replacingOccurrences(of: "^", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleaned, !cleaned.isEmpty else { return nil }
        return cleaned
    }

    private func formattedAge(_ value: String?) -> String? {
        guard let cleaned = clean(value) else { return nil }
        let suffix = cleaned.suffix(1).uppercased()
        let digits = cleaned.dropLast().filter(\.isNumber)
        if let number = Int(digits), ["Y", "M", "W", "D"].contains(suffix) {
            return "\(number)\(suffix)"
        }
        return cleaned
    }
}

struct SidebarView: View {
    @ObservedObject var model: DICOMModel
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var selectedStudyID: String? = nil
    @State private var isStudyColumnCollapsed = false
    @AppStorage("seriesThumbnailSize") private var seriesThumbnailSize: Double = 136
    @AppStorage("seriesColumnCount") private var seriesColumnCount: Int = 1

    private var seriesColumnWidth: CGFloat {
        let columns = max(1, min(2, seriesColumnCount))
        let padding: CGFloat = 34
        let gap: CGFloat = columns == 2 ? 10 : 0
        return max(150, CGFloat(columns) * (CGFloat(seriesThumbnailSize) + padding) + gap)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Toolbar / Header
            HStack {
                Button(action: { columnVisibility = .detailOnly }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Hide Sidebar")

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isStudyColumnCollapsed.toggle() } }) {
                    Image(systemName: isStudyColumnCollapsed ? "rectangle.leftthird.inset.filled" : "rectangle.leadinghalf.inset.filled")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isStudyColumnCollapsed ? "Show Study Column" : "Collapse Study Column")
                
                Spacer()

                Button(action: { model.anonymizeFolder() }) {
                    Image(systemName: "person.crop.circle.badge.minus")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Anonymize Folder")
                
                Button(action: openFile) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("Open")
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Linked DICOM Folder")
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
            // Remove background or make it very subtle
            // .background(Color.black.opacity(0.4))
            
            HStack(spacing: 0) {
                if isStudyColumnCollapsed {
                    CollapsedStudyColumn(
                        selectedStudyID: $selectedStudyID,
                        isCollapsed: $isStudyColumnCollapsed
                    )
                    .frame(width: 38)
                } else {
                    StudyListView(
                        model: model,
                        selectedStudyID: $selectedStudyID,
                        isCollapsed: $isStudyColumnCollapsed
                    )
                    .frame(width: 158)
                    Divider()
                }

                SeriesListView(model: model, selectedStudyID: $selectedStudyID)
                    .frame(width: seriesColumnWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
    
    private func openFile() {
        model.openFolder()
    }
}

struct AnonymizeFolderDialog: View {
    @ObservedObject var model: DICOMModel
    @State private var sourceURL: URL?
    @State private var destinationURL: URL?
    @State private var initial = "YSH"
    @State private var studyNo = ""

    private var canAnonymize: Bool {
        sourceURL != nil && destinationURL != nil && !initial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isAnonymizing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 18) {
                HStack(spacing: 12) {
                    Circle().fill(Color.red).frame(width: 18, height: 18)
                    Circle().fill(Color.yellow).frame(width: 18, height: 18)
                    Circle().fill(Color.green).frame(width: 18, height: 18)
                }

                Text("Anonymize Folder")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 16) {
                pathRow(title: "Source", url: sourceURL, action: chooseSource)
                pathRow(title: "Destination", url: destinationURL, action: chooseDestination)

                HStack(spacing: 16) {
                    Text("Initial")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)

                    TextField("YSH", text: $initial)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 18, weight: .semibold))
                }

                HStack(spacing: 16) {
                    Text("Study No.")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)

                    TextField("Study number", text: $studyNo)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 18, weight: .semibold))
                }
            }

            if let message = model.anonymizeResultMessage {
                Text(message)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(message.hasPrefix("Failed") ? .red : .secondary)
                    .lineLimit(2)
            }

            HStack {
                Button("Cancel") {
                    model.showAnonymizeSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if model.isAnonymizing {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Anonymize") {
                    guard let sourceURL, let destinationURL else { return }
                    model.runAnonymize(
                        sourceURL: sourceURL,
                        destinationURL: destinationURL,
                        patientName: initial.trimmingCharacters(in: .whitespacesAndNewlines),
                        patientID: studyNo.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAnonymize)
            }
        }
        .padding(28)
        .frame(width: 860)
        .background(Color(white: 0.11))
    }

    private func pathRow(title: String, url: URL?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(url?.path ?? "Not selected")
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.10))
                .cornerRadius(7)

            Button("Choose...", action: action)
                .font(.system(size: 16, weight: .semibold))
        }
    }

    private func chooseSource() {
        let panel = NSOpenPanel()
        panel.title = "Choose DICOM Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            sourceURL = url
            if destinationURL == nil {
                destinationURL = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent)_anonymized")
            }
        }
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.title = "Choose Output Folder"
        panel.prompt = "Choose"
        panel.canCreateDirectories = true
        if let sourceURL {
            panel.directoryURL = sourceURL.deletingLastPathComponent()
            panel.nameFieldStringValue = "\(sourceURL.lastPathComponent)_anonymized"
        }
        if panel.runModal() == .OK {
            destinationURL = panel.url
        }
    }
}

struct WindowLevelPresetEditor: View {
    @ObservedObject var model: DICOMModel
    @Environment(\.dismiss) private var dismiss
    @State private var presets: [WindowLevelPreset]

    init(model: DICOMModel) {
        self.model = model
        _presets = State(initialValue: model.windowLevelPresets)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Circle().fill(Color.red).frame(width: 14, height: 14)
                Circle().fill(Color.yellow).frame(width: 14, height: 14)
                Circle().fill(Color.green).frame(width: 14, height: 14)
                Text("Window / Level Presets")
                    .font(.system(size: 22, weight: .bold))
            }

            VStack(spacing: 8) {
                HStack {
                    Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                    Text("WL").frame(width: 90)
                    Text("WW").frame(width: 90)
                    Spacer().frame(width: 34)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

                ForEach(presets.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        TextField("Preset", text: $presets[index].name)
                            .textFieldStyle(.roundedBorder)
                        TextField("WL", value: $presets[index].center, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        TextField("WW", value: $presets[index].width, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Button {
                            presets.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Button {
                    presets.append(WindowLevelPreset(name: "New Preset", width: 80, center: 40))
                } label: {
                    Label("Add", systemImage: "plus")
                }

                Button("Defaults") {
                    presets = WindowLevelPreset.defaultPresets
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    model.saveWindowLevelPresets(presets)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 620)
        .background(Color(white: 0.11))
    }
}

struct StudyListItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let seriesIndices: [Int]
}

enum StudyBrowserBuilder {
    static func studies(for allSeries: [DicomSeries]) -> [StudyListItem] {
        var orderedKeys: [String] = []
        var grouped: [String: [Int]] = [:]

        for (index, series) in allSeries.enumerated() {
            let uid = series.studyInstanceUID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = uid?.isEmpty == false ? uid! : "unknown-study-\(orderedKeys.count)"
            if grouped[key] == nil {
                orderedKeys.append(key)
            }
            grouped[key, default: []].append(index)
        }

        return orderedKeys.enumerated().compactMap { offset, key in
            guard let indices = grouped[key], let firstIndex = indices.first else { return nil }
            let series = allSeries[firstIndex]
            return StudyListItem(
                id: key,
                title: studyTitle(series: series, offset: offset, total: orderedKeys.count),
                subtitle: studySubtitle(series: series, seriesCount: indices.count),
                seriesIndices: indices
            )
        }
    }

    private static func studyTitle(series: DicomSeries, offset: Int, total: Int) -> String {
        var parts: [String] = ["Study \(offset + 1)"]
        if let desc = cleaned(series.studyDescription) {
            parts.append(desc)
        } else if total == 1 {
            parts = ["Study"]
        }
        return parts.joined(separator: "  ")
    }

    private static func studySubtitle(series: DicomSeries, seriesCount: Int) -> String {
        var parts: [String] = []
        if let dateTime = formattedStudyDateTime(date: series.studyDate, time: series.studyTime) {
            parts.append(dateTime)
        }
        if let patient = cleaned(series.patientName) { parts.append(patient) }
        if let id = cleaned(series.patientID) { parts.append("ID \(id)") }
        parts.append("\(seriesCount) Series")
        return parts.joined(separator: "  |  ")
    }

    static func cleaned(_ value: String?) -> String? {
        let trimmed = value?
            .replacingOccurrences(of: "^", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func formatStudyDate(_ value: String) -> String {
        guard value.count == 8 else { return value }
        let y = value.prefix(4)
        let m = value.dropFirst(4).prefix(2)
        let d = value.suffix(2)
        return "\(y)-\(m)-\(d)"
    }

    static func formattedStudyDateTime(date: String?, time: String?) -> String? {
        var parts: [String] = []
        if let date = cleaned(date) {
            parts.append(formatStudyDate(date))
        }
        if let time = cleaned(time), let formattedTime = formatStudyTime(time) {
            parts.append(formattedTime)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func formatStudyTime(_ value: String) -> String? {
        let digits = value.filter(\.isNumber)
        guard digits.count >= 2 else { return nil }
        let hour = String(digits.prefix(2))
        let minuteStart = digits.index(digits.startIndex, offsetBy: min(2, digits.count))
        let minute = digits.count >= 4 ? String(digits[minuteStart..<digits.index(minuteStart, offsetBy: 2)]) : "00"
        return "\(hour):\(minute)"
    }
}

struct CollapsedStudyColumn: View {
    @Binding var selectedStudyID: String?
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(spacing: 10) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isCollapsed = false } }) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Show Study Column")

            if selectedStudyID != nil {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }

            Spacer()
        }
        .padding(.top, 8)
        .background(Color(white: 0.11))
    }
}

struct StudyListView: View {
    @ObservedObject var model: DICOMModel
    @Binding var selectedStudyID: String?
    @Binding var isCollapsed: Bool

    private var studies: [StudyListItem] {
        StudyBrowserBuilder.studies(for: model.allSeries)
    }

    private var activeStudyID: String? {
        let activeSeries = model.activePanel?.seriesIndex ?? model.currentSeriesIndex
        guard activeSeries >= 0 else { return nil }
        return studies.first(where: { $0.seriesIndices.contains(activeSeries) })?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Studies")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isCollapsed = true } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Collapse Study Column")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: 4) {
                    StudyListRow(
                        title: "All Studies",
                        subtitle: "\(studies.count) Studies",
                        isSelected: selectedStudyID == nil,
                        isActive: activeStudyID != nil
                    )
                    .onTapGesture { selectedStudyID = nil }

                    ForEach(studies) { study in
                        StudyListRow(
                            title: study.title,
                            subtitle: study.subtitle,
                            isSelected: selectedStudyID == study.id,
                            isActive: activeStudyID == study.id
                        )
                        .onTapGesture { selectedStudyID = study.id }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            }
        }
        .background(Color(white: 0.12))
        .onChange(of: model.allSeries.count) { _, _ in
            if let selectedStudyID, !studies.contains(where: { $0.id == selectedStudyID }) {
                self.selectedStudyID = nil
            }
        }
    }
}

struct StudyListRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.24) : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected || isActive {
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.65))
                    .frame(width: isSelected ? 3 : 2)
            }
        }
        .cornerRadius(6)
    }
}

struct SeriesListView: View {
    @ObservedObject var model: DICOMModel
    @Binding var selectedStudyID: String?
    @AppStorage("seriesThumbnailSize") private var seriesThumbnailSize: Double = 136
    @AppStorage("seriesColumnCount") private var seriesColumnCount: Int = 1

    /// The series index shown by the active panel (for highlight)
    private var activeSeriesIndex: Int {
        model.activePanel?.seriesIndex ?? model.currentSeriesIndex
    }

    private var studySections: [StudySection] {
        let sections = StudyBrowserBuilder.studies(for: model.allSeries)
        guard let selectedStudyID else { return sections }
        return sections.filter { $0.id == selectedStudyID }
    }

    private typealias StudySection = StudyListItem

    private var seriesHeaderTitle: String {
        guard let selectedStudyID,
              let study = studySections.first(where: { $0.id == selectedStudyID }) else {
            return "Series"
        }
        return study.title
    }

    private var gridColumns: [GridItem] {
        let count = max(1, min(2, seriesColumnCount))
        return Array(
            repeating: GridItem(
                .flexible(minimum: CGFloat(seriesThumbnailSize), maximum: max(CGFloat(seriesThumbnailSize), 280)),
                spacing: 10,
                alignment: .top
            ),
            count: count
        )
    }

    /// Row background color for a given series index
    private func rowBackground(for index: Int) -> Color? {
        if index == activeSeriesIndex {
            return Color.blue.opacity(0.15)
        }
        if model.panels.contains(where: { $0.seriesIndex == index }) {
            return Color.blue.opacity(0.05)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(seriesHeaderTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        seriesColumnCount = seriesColumnCount == 1 ? 2 : 1
                    } label: {
                        Image(systemName: seriesColumnCount == 1 ? "rectangle.grid.1x2" : "rectangle.grid.2x2")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help(seriesColumnCount == 1 ? "Show Series in 2 Columns" : "Show Series in 1 Column")

                    Button {
                        seriesThumbnailSize = max(88, seriesThumbnailSize - 16)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("Shrink Thumbnails")

                    Button {
                        seriesThumbnailSize = min(220, seriesThumbnailSize + 16)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("Enlarge Thumbnails")
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                    if !model.allSeries.isEmpty {
                        ForEach(studySections) { study in
                            Section {
                                LazyVGrid(
                                    columns: gridColumns,
                                    alignment: .center,
                                    spacing: 10
                                ) {
                                    ForEach(study.seriesIndices, id: \.self) { index in
                                        seriesCell(for: index)
                                    }
                                }
                                .padding(.horizontal, 10)
                            } header: {
                                StudyHeaderView(title: study.title, subtitle: study.subtitle)
                            }
                        }
                    }

                    if model.isScanning && (!model.allSeries.isEmpty || !model.derivedObjects.isEmpty) {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .overlay {
            if model.allSeries.isEmpty && model.derivedObjects.isEmpty {
                if model.isScanning {
                    VStack {
                        ProgressView("Scanning Directory...")
                            .controlSize(.regular)
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Series Found", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text("Drag a FOLDER to this window to scan for all series.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func seriesCell(for index: Int) -> some View {
        if let series = model.allSeries[safe: index] {
            SeriesRow(
                model: model,
                series: series,
                isSelected: index == activeSeriesIndex,
                seriesIndex: index,
                thumbnailSize: CGFloat(seriesThumbnailSize)
            )
            .contentShape(Rectangle())
            .onDrag { makeSeriesDragProvider(index: index, suggestedName: series.seriesDescription) }
            .onTapGesture {
                selectSeries(index)
            }
        } else {
            EmptyView()
        }
    }

    private func selectSeries(_ index: Int) {
        guard let series = model.allSeries[safe: index] else { return }
        model.currentImageIndex = 0
        model.currentSeriesIndex = index
        model.clearSelectedDerivedObject()
        if let panel = model.activePanel {
            model.assignSeriesToPanel(panel, seriesIndex: index)
        } else if let first = series.images.first {
            model.loadSingleFile(first.url)
        }
    }
}

struct StudyHeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(white: 0.16))
    }
}

struct DerivedObjectRow: View {
    let object: DICOMDerivedObjectSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: object.kind.iconName)
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? .orange : .secondary)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(object.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(object.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(object.supportSummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .help("Inspect \(object.kind.rawValue) DICOM tags")
    }
}

struct SeriesRow: View {
    @ObservedObject var model: DICOMModel
    let series: DicomSeries
    let isSelected: Bool
    let seriesIndex: Int
    let thumbnailSize: CGFloat

    /// Whether any panel is displaying this series
    private var isInAnyPanel: Bool {
        model.panels.contains { $0.seriesIndex == seriesIndex }
    }

    private var seriesCountLabel: String {
        if series.images.count == 1, let nf = series.images.first?.numberOfFrames, nf > 1 {
            return "\(nf) Frames"
        }
        return "\(series.images.count) Instances"
    }

    private var seriesTitle: String {
        let title = series.seriesDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Series \(series.seriesNumber)" : title
    }

    private var seriesNumberLabel: String? {
        series.seriesDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "Series \(series.seriesNumber)"
    }

    var body: some View {
        VStack(spacing: 7) {
            VStack(spacing: 2) {
                Text(seriesTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let seriesNumberLabel {
                    Text(seriesNumberLabel)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(seriesCountLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            ZStack(alignment: .topTrailing) {
                thumbnailView

                if isInAnyPanel {
                    PanelPositionIndicator(model: model, seriesIndex: seriesIndex)
                        .padding(5)
                        .background(.black.opacity(0.55))
                        .cornerRadius(5)
                        .padding(5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
        .onAppear {
            model.requestSeriesThumbnail(for: series)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
	        if let thumb = model.seriesThumbnails[series.id] {
	            Image(nsImage: thumb)
	                .resizable()
	                .aspectRatio(contentMode: .fit)
	                .frame(width: thumbnailSize, height: thumbnailSize)
	                .background(Color.black)
	                .clipped()
	                .contentShape(Rectangle())
	                .onDrag { seriesDragProvider(seriesIndex) }
	        } else {
	            ZStack {
	                Color.black
	                ProgressView()
	                    .controlSize(.small)
	                    .tint(.white)
	            }
	            .frame(width: thumbnailSize, height: thumbnailSize)
	            .contentShape(Rectangle())
	            .onDrag { seriesDragProvider(seriesIndex) }
	        }
	    }

	    private func seriesDragProvider(_ index: Int) -> NSItemProvider {
	        makeSeriesDragProvider(index: index, suggestedName: seriesTitle)
	    }
	}

/// Miniature grid icon showing which panel(s) display a given series.
/// Each cell is a tiny rounded rectangle: filled blue if the panel shows this series, border-only otherwise.
struct PanelPositionIndicator: View {
    @ObservedObject var model: DICOMModel
    let seriesIndex: Int

    private let cellSize: CGFloat = 7
    private let spacing: CGFloat = 2

    var body: some View {
        let rows = model.isSplitComparisonMode ? 1 : model.layout.rows
        let cols = model.isSplitComparisonMode ? 2 : model.layout.columns

        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<cols, id: \.self) { col in
                        let panelIdx = row * cols + col
                        let isFilled = panelIdx < model.panels.count && model.panels[panelIdx].seriesIndex == seriesIndex
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(isFilled ? Color.blue : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 1.5)
                                    .strokeBorder(Color.blue.opacity(isFilled ? 1 : 0.4), lineWidth: 1)
                            )
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }
}

struct DetailView: View {
    @ObservedObject var model: DICOMModel
    @FocusState.Binding var isFocused: Bool
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Image View (Always Present if configured, barely visible if no image?)
            // We want to keep it in the hierarchy to preserve state/focus if possible.
            // If image is nil, maybe show nothing or keep previous?
            if let image = model.image {
                 InteractiveDICOMView(model: model, image: image)
                     .frame(maxWidth: .infinity, maxHeight: .infinity)
                     .zIndex(0)
            } else if model.errorMessage == nil && !model.isLoading {
                ContentUnavailableView("No Image Selected", systemImage: "photo")
            }

            // Error Overlay
            if let error = model.errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                     Text(error).font(.caption)
                }
                .background(Color.black.opacity(0.8))
                .zIndex(200)
            }
            
            // Exclusive Loading Overlay - REMOVED for non-obstructive UX
            // if model.isLoading { ... }
            
            // Info Overlay (Only show if image exists)
            if model.image != nil {
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading) {
                            if !model.currentSeriesInfo.isEmpty {
                                Text(model.currentSeriesInfo).padding(4)
                            }
                            if model.windowWidth != 0 {
                                Text(String(format: "WL: %.0f WW: %.0f", model.windowCenter, model.windowWidth))
                                    .padding(4)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                        .background(.thinMaterial)
                        .cornerRadius(8)
                        
                        Spacer()
                        
                        if !model.currentImageInfo.isEmpty {
                            HStack {
                                if model.cacheProgress < 1.0 && model.cacheProgress > 0 {
                                    Text(String(format: "Loading: %.0f%%", model.cacheProgress * 100))
                                        .font(.caption)
                                        .padding(6)
                                        .background(.thinMaterial)
                                        .cornerRadius(8)
                                        .transition(.opacity)
                                }
                                Text(model.currentImageInfo)
                                    .padding(8)
                                    .background(.thinMaterial)
                                    .cornerRadius(8)
                            }
                            .animation(.easeInOut, value: model.cacheProgress < 1.0)
                        }
                    }
                    .padding()
                }
                .zIndex(50)
            }
            
            // Advanced Controls Overlay (Bottom)
             if model.image != nil && !model.isLoading {
                 VStack {
                     Spacer()
                     AdjustmentToolbar(model: model)
                         .padding(.bottom, 20)
                 }
                 .zIndex(60)
                 
                 // Right Side Scroller
                 HStack {
                     Spacer()
                     DICOMScroller(model: model)
                         .frame(width: 40)
                         .padding(.trailing, 4)
                         .padding(.vertical, 20)
                 }
                 .frame(maxHeight: .infinity) // Ensure full height
                 .zIndex(70)
             }
            
            // Keyboard Handling (Backup for SwiftUI Focus)
            ZStack { Color.clear }
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onKeyPress(.leftArrow) {
                model.prevSeries()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                model.nextSeries()
                return .handled
            }
            .onKeyPress(.upArrow) {
                model.prevSeries()
                return .handled
            }
            .onKeyPress(.downArrow) {
                model.nextSeries()
                return .handled
            }
        }
    }
}

// NSView for High-Performance Interaction
struct InteractiveDICOMView: NSViewRepresentable {
    @ObservedObject var model: DICOMModel
    var image: NSImage
    
    func makeNSView(context: Context) -> DICOMInteractView {
        let view = DICOMInteractView()
        view.model = model
        return view
    }
    
    func updateNSView(_ nsView: DICOMInteractView, context: Context) {
        nsView.model = model
        nsView.setImage(image)
        // Apply W/L filters for compressed images
        nsView.applyFilters()
    }
    
    class DICOMInteractView: NSView {
        weak var model: DICOMModel?
        private var imageView = NSImageView()
        
        // Interaction State
        private var lastDragLocation: NSPoint?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            setup()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }
        
        override func layout() {
            super.layout()
            
            // CRITICAL: Ensure Anchor Point is strictly Center (0.5, 0.5)
            // macOS AutoLayout with Layers can sometimes reset this or imply (0,0).
            // We force it here to ensure Zoom (Scale) happens around the center.
            if let layer = imageView.layer {
                layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                
                // When modifying anchor point, position must be updated to maintain frame.
                // Since this is AutoLayout, we ensure position matches the view center.
                // Constraints usually handle this, but explicit setting ensures the layer model matches.
                let midX = self.bounds.width / 2.0
                let midY = self.bounds.height / 2.0
                layer.position = CGPoint(x: midX, y: midY)
            }
        }

        private func setup() {
            self.wantsLayer = true
            self.layer?.backgroundColor = NSColor.black.cgColor
            
            // imageView Setup
            imageView.imageScaling = .scaleProportionallyUpOrDown
            self.addSubview(imageView)
            
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                imageView.widthAnchor.constraint(equalTo: self.widthAnchor),
                imageView.heightAnchor.constraint(equalTo: self.heightAnchor)
            ])
            
            imageView.wantsLayer = true
            // Initial setting (reinforced in layout)
            imageView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        }
        
        func setImage(_ img: NSImage) {
            if imageView.image != img {
                imageView.image = img
                // Defer restoration to ensure NSImageView doesn't reset the layer transform immediately after setting image
                DispatchQueue.main.async {
                    self.restoreState()
                }
            }
        }
        
        private func restoreState() {
            guard let model = model, let layer = imageView.layer else { return }
            let (scale, translation) = model.getViewState()
            
            // Debug
            // print("[RestoreState] s:\(scale) t:\(translation)")
            
            var t = CATransform3DIdentity
            t.m11 = scale
            t.m22 = scale
            t.m41 = translation.x
            t.m42 = translation.y
            
            layer.transform = t
        }
        
        
        
        func applyFilters() {
            guard let model = model else { return } // Removed layer guard for safety, though mostly needed for CALayer
            
            // CRITICAL FIX: If Model has Raw Data, it manually re-renders the NSImage with the new W/L baked in.
            // We MUST NOT apply CIColorControls filters on top of that, or it effectively applies W/L twice.
            if model.isRawDataAvailable {
                imageView.contentFilters = []
                return
            }
            
            let currentWW = model.windowWidth
            let currentWC = model.windowCenter
            let initialWW = model.initialWindowWidth
            let initialWC = model.initialWindowCenter
            
            if initialWW == 0 { return }
            
            // Prevent divide by zero
            let safeWW = currentWW == 0 ? 1 : currentWW
            let contrast = CGFloat(initialWW / safeWW)
            let brightness = CGFloat((initialWC - currentWC) / 255.0)
            
            guard let filter = CIFilter(name: "CIColorControls") else { return }
            
            filter.setDefaults()
            filter.setValue(contrast, forKey: "inputContrast")
            filter.setValue(brightness, forKey: "inputBrightness")
            
            imageView.contentFilters = [filter]
        }
        
        private func saveState() {
            guard let model = model, let layer = imageView.layer else { return }
            let scale = layer.transform.m11
            let tx = layer.transform.m41
            let ty = layer.transform.m42
            
            model.saveViewState(scale: scale, translation: CGPoint(x: tx, y: ty))
        }
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            guard let model = model else {
                super.keyDown(with: event)
                return
            }
            
            // Interpret Arrow Keys
            let code = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .control, .option])
            if flags.isEmpty, model.applyWindowLevelPresetShortcut(keyCode: code) {
                return
            }
            // 123: Left, 124: Right, 125: Down, 126: Up
            
            switch code {
            case 123: // Left
                 model.prevSeries()
            case 124: // Right
                 model.nextSeries()
            case 126: // Up
                 model.prevSeries()
            case 125: // Down
                 model.nextSeries()
            default:
                super.keyDown(with: event)
            }
        }
        
        override func scrollWheel(with event: NSEvent) {
            // Check for Option key -> Zoom
            if event.modifierFlags.contains(.option) {
                 guard let layer = imageView.layer else { return }
                 let dy = event.deltaY
                 if dy == 0 { return }
                 
                 // Zoom Factor
                 let zoomSpeed: CGFloat = 0.05
                 let delta = dy * zoomSpeed
                 
                 let oldScale = layer.transform.m11
                 var newScale = oldScale + convertToCGFloat(delta)
                 
                 // Clamp Scale
                 newScale = max(0.1, min(10.0, newScale))
                 
                 // User Request: Zoom around Image Center (Fixed Center)
                 // Do NOT adjust translation (m41/m42).
                 // layer.anchorPoint is (0.5, 0.5), so scaling m11/m22 zooms around the image center.
                 
                 layer.transform.m11 = newScale
                 layer.transform.m22 = newScale
                 
                 saveState()
                 return
            }
            
            // Normal Scroll -> Navigation
            // Threshold for scrolling
            if abs(event.deltaY) > 0.5 {
                if event.deltaY > 0 {
                    model?.prevImage()
                } else {
                    model?.nextImage()
                }
            }
        }
        
        private func convertToCGFloat(_ val: Double) -> CGFloat {
            return CGFloat(val)
        }

        override func rightMouseDown(with event: NSEvent) {
            lastDragLocation = event.locationInWindow
        }
        
        override func rightMouseDragged(with event: NSEvent) {
            guard let start = lastDragLocation else { return }
            let current = event.locationInWindow
            
            let dx = Double(current.x - start.x)
            let dy = Double(current.y - start.y)
            
            // Dynamic Sensitivity
            // If Window Width is huge (e.g. 2000), we need larger steps.
            // If Window Width is tiny (e.g. 50), we need fine control.
            // Base sensitivity 1.0 corresponds to roughly 1 unit per pixel?
            // Usually we want full screen drag to cover a significant portion.
            
            let currentWW = model?.windowWidth ?? 256
            let dynamicFactor = max(0.1, currentWW / 500.0) // 500 pixels drag = full width change if factor 1
            let sensitivity: Double = 1.0 * dynamicFactor
            
            model?.adjustWindowLevel(deltaWidth: dx * sensitivity, deltaCenter: dy * sensitivity)
            applyFilters()
            lastDragLocation = current
        }
        
        override func mouseDragged(with event: NSEvent) {
             // Left-click drag = pan (standard clinical convention)
             guard let layer = imageView.layer else { return }
             let dx = event.deltaX
             let dy = -event.deltaY

             layer.transform.m41 += CGFloat(dx)
             layer.transform.m42 += CGFloat(dy)

             saveState()
        }
    }
}

// MARK: - Advanced Controls
struct AdjustmentToolbar: View {
    @ObservedObject var model: DICOMModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Histogram
            if !model.histogramData.isEmpty {
                 HistogramView(
                    data: model.histogramData,
                    minVal: model.minPixelValue,
                    maxVal: model.maxPixelValue,
                    windowWidth: model.windowWidth,
                    windowCenter: model.windowCenter
                 )
                 .frame(width: 100, height: 40)
                 .background(Color.black.opacity(0.5))
                 .border(Color.white.opacity(0.2), width: 1)
            }
            
            // Presets
            Group {
                Button("Auto") { model.autoWindowLevel() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.white)
        }
        .padding(8)
        .background(.thinMaterial)
        .cornerRadius(12)
    }
}

struct HistogramView: View {
    let data: [Double]
    let minVal: Double
    let maxVal: Double
    let windowWidth: Double
    let windowCenter: Double
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 1. Histogram Path
                Path { path in
                    let width = geo.size.width
                    let height = geo.size.height
                    let step = width / CGFloat(data.count)
                    
                    path.move(to: CGPoint(x: 0, y: height))
                    for (i, val) in data.enumerated() {
                        let x = CGFloat(i) * step
                        let y = height - (CGFloat(val) * height)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                
                // 2. Window/Level Indicator
                // Map W/L range to 0-1 coordinate space relative to minVal...maxVal
                let totalRange = maxVal - minVal
                if totalRange > 0 {
                    let windowStart = (windowCenter - (windowWidth / 2.0))
                    let windowEnd = (windowCenter + (windowWidth / 2.0))
                    
                    let startRatio = max(0.0, min(1.0, (windowStart - minVal) / totalRange))
                    let endRatio = max(0.0, min(1.0, (windowEnd - minVal) / totalRange))
                    
                    let startX = CGFloat(startRatio) * geo.size.width
                    let widthPx = CGFloat(endRatio - startRatio) * geo.size.width
                    
                    // Draw Window Range (Yellow box overlay)
                    Rectangle()
                        .fill(Color.yellow.opacity(0.2))
                        .frame(width: max(2, widthPx), height: geo.size.height) // Min 2px
                        .position(x: startX + (widthPx / 2.0), y: geo.size.height / 2.0)
                        
                    // Draw Center Line (White)
                    let centerRatio = max(0.0, min(1.0, (windowCenter - minVal) / totalRange))
                    let centerX = CGFloat(centerRatio) * geo.size.width
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 1, height: geo.size.height)
                        .position(x: centerX, y: geo.size.height / 2.0)
                }
            }
        }
    }
}

struct DICOMScroller: View {
    @ObservedObject var model: DICOMModel
    @State private var isHovering = false
    @State private var hoverLocation: CGPoint = .zero
    @State private var dragLocation: CGPoint? = nil
    
    var body: some View {
        GeometryReader { geo in
            let total = model.allSeries.indices.contains(model.currentSeriesIndex) ? model.allSeries[model.currentSeriesIndex].images.count : 0
            
            ZStack(alignment: .top) {
                // Track
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.2)) // Increased visibility
                    .frame(width: 6, height: geo.size.height)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                // Handle
                if total > 0 {
                    let thumbHeight = max(20.0, geo.size.height / CGFloat(total) * 4.0) // Minimal height
                    let progress = Double(model.currentImageIndex) / Double(max(1, total - 1))
                    let availHeight = geo.size.height - thumbHeight
                    let offset = CGFloat(progress) * availHeight
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.8)) // High visibility
                        .frame(width: 6, height: thumbHeight)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .offset(y: offset)
                }
            }
            .contentShape(Rectangle())
            // Mouse Tracking for Hover
            .contentShape(Rectangle())
            // Interaction Overlay (Captures Clicks & Drags)
            .overlay {
                ScrollerInteractionView(
                    onDrag: { loc in
                        dragLocation = loc
                        calculateIndex(y: loc.y, height: geo.size.height, total: total, commit: true)
                    },
                    onHover: { loc in
                        hoverLocation = loc
                    },
                    onEnter: { isHovering = true },
                    onExit: {
                        isHovering = false
                        dragLocation = nil // Reset drag on exit if needed, or keep it
                    }
                )
            }
            .overlay(alignment: .topTrailing) {
                 if total > 0, let pY = activeY() {
                     let idx = getIndex(y: pY, height: geo.size.height, total: total)
                     ThumbnailPopup(model: model, index: idx, total: total)
                         .offset(x: -20, y: min(max(0, pY - 45), geo.size.height - 90))
                         .allowsHitTesting(false)
                 }
            }
        }
    }
    
    private func activeY() -> CGFloat? {
        if let d = dragLocation { return d.y }
        if isHovering { return hoverLocation.y }
        return nil
    }
    
    func calculateIndex(y: CGFloat, height: CGFloat, total: Int, commit: Bool) {
        if total <= 1 { return }
        let idx = getIndex(y: y, height: height, total: total)
        if commit && idx != model.currentImageIndex {
            // Update index immediately for UI feedback
            model.currentImageIndex = idx
            
            // Trigger proper load logic
            if model.currentSeriesIndex >= 0 && model.currentSeriesIndex < model.allSeries.count {
               let series = model.allSeries[model.currentSeriesIndex]
               if idx >= 0 && idx < series.images.count {
                   model.loadSingleFile(series.images[idx].url)
               }
            }
        }
    }
    
    func getIndex(y: CGFloat, height: CGFloat, total: Int) -> Int {
        let pct = max(0, min(1, y / height))
        return Int(pct * Double(total - 1))
    }
}

struct ThumbnailPopup: View {
    @ObservedObject var model: DICOMModel
    let index: Int
    let total: Int
    
    var body: some View {
        HStack {
            Text("\(index + 1)")
                .font(.caption)
                .padding(4)
                .background(.black.opacity(0.7))
                .cornerRadius(4)
            
            if let img = model.getCachedImage(at: index) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .background(Color.black)
                    .cornerRadius(4)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .shadow(radius: 4)
    }
}

struct ScrollerInteractionView: NSViewRepresentable {
    var onDrag: (CGPoint) -> Void
    var onHover: (CGPoint) -> Void
    var onEnter: () -> Void
    var onExit: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let v = InteractionView()
        v.onDrag = onDrag
        v.onHover = onHover
        v.onEnter = onEnter
        v.onExit = onExit
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let v = nsView as? InteractionView {
            v.onDrag = onDrag
            v.onHover = onHover
            v.onEnter = onEnter
            v.onExit = onExit
        }
    }
    
    class InteractionView: NSView {
        var onDrag: ((CGPoint) -> Void)?
        var onHover: ((CGPoint) -> Void)?
        var onEnter: (() -> Void)?
        var onExit: (() -> Void)?
        
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach { removeTrackingArea($0) }
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .activeAlways], owner: self, userInfo: nil))
        }
        
        // MARK: - Mouse Events
        override func mouseDown(with event: NSEvent) {
            handleDrag(event)
        }
        
        override func mouseDragged(with event: NSEvent) {
            handleDrag(event)
        }
        
        private func handleDrag(_ event: NSEvent) {
            let loc = convert(event.locationInWindow, from: nil)
            // Flip Y for SwiftUI
            let flippedY = bounds.height - loc.y
            onDrag?(CGPoint(x: loc.x, y: flippedY))
        }
        
        override func mouseEntered(with event: NSEvent) { onEnter?() }
        override func mouseExited(with event: NSEvent) { onExit?() }
        override func mouseMoved(with event: NSEvent) {
            let loc = convert(event.locationInWindow, from: nil)
            let flippedY = bounds.height - loc.y
            onHover?(CGPoint(x: loc.x, y: flippedY))
        }
    }
}
