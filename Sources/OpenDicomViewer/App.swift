// App.swift
// OpenDicomViewer
//
// Application entry point. Configures the main window with a hidden titlebar
// and registers menu bar commands for layout switching, view operations
// (window/level, transforms, overlays), MPR mode, and synchronized scrolling.
// Licensed under the MIT License. See LICENSE for details.

import SwiftUI
import AppKit

final class OpenDicomViewerAppDelegate: NSObject, NSApplicationDelegate {
    var openURLsHandler: (([URL]) -> Void)? {
        didSet { flushPendingOpenURLs() }
    }

    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureWindowExistsIfNeeded()
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        handleOpenURLs(urls)
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handleOpenURLs(urls)
    }

    private func handleOpenURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        ensureWindowExistsIfNeeded()
        if let openURLsHandler {
            DispatchQueue.main.async {
                openURLsHandler(urls)
            }
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
    }

    private func flushPendingOpenURLs() {
        guard let openURLsHandler, !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        DispatchQueue.main.async {
            openURLsHandler(urls)
        }
    }

    private func ensureWindowExistsIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let hasVisibleWindow = NSApp.windows.contains { $0.isVisible }
            guard !hasVisibleWindow else { return }
            NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct OpenDicomViewerApp: App {
    @NSApplicationDelegateAdaptor(OpenDicomViewerAppDelegate.self) private var appDelegate
    @StateObject private var model = DICOMModel()
    @StateObject private var updateChecker = UpdateChecker()
    @StateObject private var licenseManager = LicenseManager()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, licenseManager: licenseManager)
                .onAppear {
                    appDelegate.openURLsHandler = { [weak model] urls in
                        guard let url = urls.first else { return }
                        model?.load(url: url)
                    }
                }
                .onOpenURL { url in
                    model.load(url: url)
                }
                .task {
                    // Auto-open directory if passed via --benchmark /path
                    if let benchIdx = CommandLine.arguments.firstIndex(of: "--benchmark"),
                       benchIdx + 1 < CommandLine.arguments.count {
                        let path = CommandLine.arguments[benchIdx + 1]
                        let url = URL(fileURLWithPath: path)
                        model.load(url: url)
                    } else {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await updateChecker.checkForUpdates()
                    }
                }
                .alert(
                    updateAlertTitle,
                    isPresented: $updateChecker.showUpdateAlert
                ) {
                    updateAlertButtons
                } message: {
                    Text(updateAlertMessage)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Smart DICOM Viewer") {
                    model.showAbout = true
                }
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    Task { await updateChecker.checkForUpdates(userInitiated: true) }
                }

                Button("Activate License...") {
                    licenseManager.showActivation = true
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    model.openFolder()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Anonymize Folder...") {
                    model.anonymizeFolder()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                // ─ Window/Level ─
                Button("Auto Window/Level (A)") {
                    if let panel = model.activePanel {
                        model.autoWindowLevelForPanel(panel)
                    }
                }

                // ─ Transform ─
                Button("Fit to Window (F)") {
                    model.fitToWindowForPanel(model.activePanel)
                }

                Button("Reset View (R)") {
                    model.resetViewForPanel(model.activePanel)
                }

                Divider()

                // ─ Overlays ─
                Toggle("Cross-Reference Lines (X)", isOn: $model.showCrossReference)

                Toggle("DICOM Tags Inspector (T)", isOn: $model.showTags)
            }

            CommandMenu("Layout") {
                Button("Single Panel") {
                    withAnimation(.easeInOut(duration: 0.25)) { model.setLayout(.single) }
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("2×2 Tiles") {
                    withAnimation(.easeInOut(duration: 0.25)) { model.setLayout(.twoByTwo) }
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("3×3 Tiles") {
                    withAnimation(.easeInOut(duration: 0.25)) { model.setLayout(.threeByThree) }
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("4×4 Tiles") {
                    withAnimation(.easeInOut(duration: 0.25)) { model.setLayout(.fourByFour) }
                }
                .keyboardShortcut("4", modifiers: .command)

                Divider()

                Button("MPR Layout") {
                    withAnimation(.easeInOut(duration: 0.25)) { model.setupMPRLayout() }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()

                Toggle("Synchronized Scrolling", isOn: $model.synchronizedScrolling)
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            CommandMenu("Tools") {
                Button("Select (V)") { model.activeTool = .select }
                Button("Pan (P)") { model.activeTool = .pan }
                Button("Window/Level (W)") { model.activeTool = .windowLevel }
                Button("Zoom (Z)") { model.activeTool = .zoom }

                Divider()

                Button("ROI W/L (O)") { model.activeTool = .roiWL }
                Button("ROI Stats (S)") { model.activeTool = .roiStats }

                Divider()

                Button("Ruler (D)") { model.activeTool = .ruler }
                Button("Angle (N)") { model.activeTool = .angle }

                Divider()

                Button("Eraser (E)") { model.activeTool = .eraser }
            }

            CommandGroup(replacing: .help) {
                Button("Smart DICOM Viewer Help") {
                    model.showHelp = true
                }
            }
        }
    }

    private var updateAlertTitle: String {
        switch updateChecker.state {
        case .updateAvailable:
            return "Update Available"
        case .upToDate:
            return "You're Up to Date"
        default:
            return ""
        }
    }

    private var updateAlertMessage: String {
        switch updateChecker.state {
        case .updateAvailable(let version, let notes, _):
            return "Version \(version) is available (current: \(updateChecker.currentVersion)).\n\n\(String(notes.prefix(300)))"
        case .upToDate:
            return "Smart DICOM Viewer \(updateChecker.currentVersion) is the latest version."
        default:
            return ""
        }
    }

    @ViewBuilder
    private var updateAlertButtons: some View {
        switch updateChecker.state {
        case .updateAvailable(let version, _, let url):
            Button("Download") { updateChecker.openDownload(url) }
            Button("Skip This Version") { updateChecker.skipVersion(version) }
            Button("Later", role: .cancel) { }
        case .upToDate:
            Button("OK", role: .cancel) { }
        default:
            Button("OK", role: .cancel) { }
        }
    }
}
