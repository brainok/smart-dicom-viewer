// ActivationView.swift
// OpenDicomViewer
//
// Brainok license activation sheet.
// Licensed under the MIT License. See LICENSE for details.

import AppKit
import SwiftUI

struct ActivationView: View {
    @ObservedObject var licenseManager: LicenseManager
    let canDismiss: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var activationCode = ""
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 8) {
                Text(LicenseManager.appName)
                    .font(.title2.bold())
                Text(licenseManager.statusText)
                    .font(.callout)
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Activation Code")
                    .font(.headline)

                TextField("BRAINOK-PERSONAL-XXXX-XXXX", text: $activationCode)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.primary)
                    .tint(.white)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.36))
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .focused($codeFieldFocused)

                Button("Paste from Clipboard") {
                    activationCode = NSPasteboard.general.string(forType: .string) ?? ""
                    codeFieldFocused = true
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Device ID")
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(licenseManager.deviceId)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.28))
                        )

                    Button("Copy") {
                        licenseManager.copyDeviceIdToPasteboard()
                    }
                }
            }

            if let error = licenseManager.activationError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Support") {
                    licenseManager.openSupportEmail()
                }

                Spacer()

                if canDismiss {
                    Button("Later") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                Button(licenseManager.isActivating ? "Activating..." : "Activate") {
                    Task { await licenseManager.activate(code: activationCode) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(licenseManager.isActivating || activationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .preferredColorScheme(.dark)
        .onAppear {
            codeFieldFocused = true
        }
    }

    private var header: some View {
        HStack {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("Brainok Activation")
                .font(.title3.bold())

            Spacer()

            if canDismiss {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statusColor: Color {
        switch licenseManager.status {
        case .activated:
            return .green
        case .trial:
            return .secondary
        case .expired:
            return .orange
        }
    }
}
