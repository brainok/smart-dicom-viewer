// AboutView.swift
// OpenDicomViewer
//
// In-app About window with author contact links.
// Licensed under the MIT License. See LICENSE for details.

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let emailURL = URL(string: "mailto:Brainok777@gmail.com")!
    private let websiteURL = URL(string: "https://store.brainok.net")!

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(spacing: 6) {
                Text("Smart DICOM Viewer")
                    .font(.title2.bold())
                Text("Made by Hyo Suk Nam")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Link(destination: emailURL) {
                    Label("Brainok777@gmail.com", systemImage: "envelope")
                }

                Link(destination: websiteURL) {
                    Label("https://store.brainok.net", systemImage: "globe")
                }
            }
            .font(.callout)
            .buttonStyle(.link)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 360, height: 300)
        .preferredColorScheme(.dark)
    }
}
