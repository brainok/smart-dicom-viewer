// WindowAccessor.swift
// OpenDicomViewer
//
// NSViewRepresentable that customizes the hosting NSWindow on appear:
// hides the titlebar, removes traffic light buttons, enables
// window dragging by background, and installs a key interceptor
// for IME-independent keyboard shortcuts.
// Licensed under the MIT License. See LICENSE for details.

import SwiftUI
import AppKit

/// Invisible NSView added directly to the window's content view.
/// Overrides performKeyEquivalent which fires BEFORE the Input Method (Korean/Japanese/Chinese IME)
/// processes the event. This is the only reliable way to handle single-letter shortcuts
/// when a CJK input method is active.
private class KeyInterceptorView: NSView {
    weak var model: DICOMModel?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let model = model else { return super.performKeyEquivalent(with: event) }
        // Only handle unmodified keys
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        guard flags.isEmpty else { return super.performKeyEquivalent(with: event) }
        if model.applyWindowLevelPresetShortcut(keyCode: event.keyCode) {
            return true
        }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return super.performKeyEquivalent(with: event) }

        switch key {
        case "1":
            DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.25)) { model.setLayout(.single) } }
            return true
        case "2":
            DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.25)) { model.setLayout(.twoByTwo) } }
            return true
        case "3":
            DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.25)) { model.setLayout(.threeByThree) } }
            return true
        case "4":
            DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.25)) { model.setLayout(.fourByFour) } }
            return true
        case "r": model.resetViewForPanel(model.activePanel); return true
        case "l": model.synchronizedScrolling.toggle(); return true
        case "x": model.showCrossReference.toggle(); return true
        case "t": model.showTags.toggle(); return true
        case "f": model.fitToWindowForPanel(model.activePanel); return true
        case "a":
            if let panel = model.activePanel { model.autoWindowLevelForPanel(panel) }
            return true
        case "o": model.activeTool = .roiWL; return true
        case "s": model.activeTool = .roiStats; return true
        case "d": model.activeTool = .ruler; return true
        case "n": model.activeTool = .angle; return true
        case "e": model.activeTool = .eraser; return true
        case "w": model.activeTool = .windowLevel; return true
        case "v": model.activeTool = .select; return true
        case "p": model.activeTool = .pan; return true
        case "z": model.activeTool = .zoom; return true
        case " ":
            if let panel = model.activePanel, panel.isMultiFrame && panel.numberOfFrames > 1 {
                model.toggleCinePlayback(panel); return true
            }
            return false
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let model: DICOMModel
    private static let didSetInitialWindowFrameKey = "SmartDICOMViewer.didSetInitialWindowFrame.v1"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)

                window.standardWindowButton(.closeButton)?.isHidden = false
                window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                window.standardWindowButton(.zoomButton)?.isHidden = false

                // Allow moving by dragging background
                window.isMovableByWindowBackground = true
                window.minSize = NSSize(width: 980, height: 640)
                setInitialWindowFrameIfNeeded(window)

                // Install key interceptor for IME-independent shortcuts
                if let contentView = window.contentView {
                    let interceptor = KeyInterceptorView()
                    interceptor.model = model
                    interceptor.frame = .zero
                    interceptor.isHidden = false
                    contentView.addSubview(interceptor)
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
    }

    private func setInitialWindowFrameIfNeeded(_ window: NSWindow) {
        guard !UserDefaults.standard.bool(forKey: Self.didSetInitialWindowFrameKey) else { return }
        let screen = window.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let targetWidth = min(max(visibleFrame.width * 0.78, 1180), 1480)
        let targetHeight = min(max(visibleFrame.height * 0.78, 760), 980)
        let width = min(targetWidth, visibleFrame.width - 48)
        let height = min(targetHeight, visibleFrame.height - 48)
        let originX = visibleFrame.midX - width / 2
        let originY = visibleFrame.midY - height / 2
        let frame = NSRect(x: originX, y: originY, width: width, height: height)

        window.setFrame(frame, display: true)
        UserDefaults.standard.set(true, forKey: Self.didSetInitialWindowFrameKey)
    }
}
