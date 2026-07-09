// DICOMAnonymizer.swift
// OpenDicomViewer
//
// Folder-level, copy-on-write anonymization for top-level PatientName and PatientID.

import Foundation
import DCMTKWrapper

struct DICOMAnonymizerResult {
    let totalFiles: Int
    let dicomFiles: Int
    let anonymizedFiles: Int
    let copiedFiles: Int
}

enum DICOMAnonymizer {
    static func anonymizeFolder(
        source: URL,
        destination: URL,
        patientName: String = "ANONYMIZED",
        patientID: String = "000000"
    ) throws -> DICOMAnonymizerResult {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(domain: "DICOMAnonymizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Source folder is not accessible."])
        }
        guard source.standardizedFileURL.path != destination.standardizedFileURL.path else {
            throw NSError(domain: "DICOMAnonymizer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Choose an output folder different from the source folder."])
        }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        var totalFiles = 0
        var dicomFiles = 0
        var anonymizedFiles = 0
        var copiedFiles = 0

        guard let enumerator = fileManager.enumerator(atPath: source.path) else {
            return DICOMAnonymizerResult(totalFiles: 0, dicomFiles: 0, anonymizedFiles: 0, copiedFiles: 0)
        }

        for case let relativePath as String in enumerator {
            let pathComponents = relativePath.split(separator: "/")
            if pathComponents.contains(where: { $0.hasPrefix(".") }) {
                continue
            }
            let fileURL = source.appendingPathComponent(relativePath)
            let outputURL = destination.appendingPathComponent(relativePath)

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
                continue
            }

            totalFiles += 1
            try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            try removeExistingOutputIfNeeded(outputURL, fileManager: fileManager)
            let anonymized = DCMTKHelper.anonymizeDICOM(
                atPath: fileURL.path,
                toPath: outputURL.path,
                patientName: patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ANONYMIZED" : patientName,
                patientID: patientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "000000" : patientID
            )

            if anonymized == 1 {
                dicomFiles += 1
                anonymizedFiles += 1
            } else if anonymized == 0 {
                copiedFiles += 1
                try fileManager.copyItem(at: fileURL, to: outputURL)
            } else {
                throw NSError(
                    domain: "DICOMAnonymizer",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to anonymize \(fileURL.lastPathComponent)."]
                )
            }
        }

        return DICOMAnonymizerResult(
            totalFiles: totalFiles,
            dicomFiles: dicomFiles,
            anonymizedFiles: anonymizedFiles,
            copiedFiles: copiedFiles
        )
    }

    private static func removeExistingOutputIfNeeded(_ outputURL: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
    }
}
