// DICOMAnonymizer.swift
// OpenDicomViewer
//
// Folder-level, copy-on-write anonymization for top-level PatientName and PatientID.

import Foundation

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

        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return DICOMAnonymizerResult(totalFiles: 0, dicomFiles: 0, anonymizedFiles: 0, copiedFiles: 0)
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            let relativePath = String(fileURL.path.dropFirst(source.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let outputURL = destination.appendingPathComponent(relativePath)

            if values.isDirectory == true {
                try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
                continue
            }

            totalFiles += 1
            try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            var data = try Data(contentsOf: fileURL)
            let anonymized = anonymizePart10Data(&data, patientName: patientName, patientID: patientID)
            if anonymized.isDICOM {
                dicomFiles += 1
            }
            if anonymized.changed {
                anonymizedFiles += 1
                try data.write(to: outputURL, options: .atomic)
            } else {
                copiedFiles += 1
                if fileManager.fileExists(atPath: outputURL.path) {
                    try fileManager.removeItem(at: outputURL)
                }
                try fileManager.copyItem(at: fileURL, to: outputURL)
            }
        }

        return DICOMAnonymizerResult(
            totalFiles: totalFiles,
            dicomFiles: dicomFiles,
            anonymizedFiles: anonymizedFiles,
            copiedFiles: copiedFiles
        )
    }

    private static func anonymizePart10Data(_ data: inout Data, patientName: String, patientID: String) -> (isDICOM: Bool, changed: Bool) {
        guard data.count > 132,
              data[128] == 0x44, data[129] == 0x49, data[130] == 0x43, data[131] == 0x4D else {
            return (false, false)
        }

        var offset = 132
        var changed = false
        var transferSyntax = "1.2.840.10008.1.2.1"
        var explicitVR = true
        var littleEndian = true

        while offset + 8 <= data.count {
            let metaGroup = readUInt16(data, offset, littleEndian: true)
            let isMetaElement = metaGroup == 0x0002
            let useExplicit = isMetaElement ? true : explicitVR
            let useLittleEndian = isMetaElement ? true : littleEndian
            let group = readUInt16(data, offset, littleEndian: useLittleEndian)
            let element = readUInt16(data, offset + 2, littleEndian: useLittleEndian)

            if group == 0x7FE0 && element == 0x0010 { break }

            var valueOffset: Int
            var valueLength: Int
            var vr = ""

            if useExplicit {
                guard offset + 8 <= data.count else { break }
                vr = String(bytes: [data[offset + 4], data[offset + 5]], encoding: .ascii) ?? ""
                let lengthLittleEndian = group == 0x0002 ? true : useLittleEndian
                if usesLongLengthVR(vr) {
                    guard offset + 12 <= data.count else { break }
                    valueLength = Int(readUInt32(data, offset + 8, littleEndian: lengthLittleEndian))
                    valueOffset = offset + 12
                } else {
                    valueLength = Int(readUInt16(data, offset + 6, littleEndian: lengthLittleEndian))
                    valueOffset = offset + 8
                }
            } else {
                valueLength = Int(readUInt32(data, offset + 4, littleEndian: useLittleEndian))
                valueOffset = offset + 8
            }

            if valueLength == Int(UInt32.max) || valueLength < 0 { break }
            guard valueOffset >= 0, valueOffset + valueLength <= data.count else { break }

            if group == 0x0002 && element == 0x0010,
               let value = String(data: Data(data[valueOffset..<valueOffset + valueLength]), encoding: .ascii) {
                transferSyntax = value.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
                switch transferSyntax {
                case "1.2.840.10008.1.2":
                    explicitVR = false
                    littleEndian = true
                case "1.2.840.10008.1.2.2":
                    explicitVR = true
                    littleEndian = false
                default:
                    explicitVR = true
                    littleEndian = true
                }
            }

            if group == 0x0010 && element == 0x0010 {
                overwriteString(&data, offset: valueOffset, length: valueLength, replacement: patientName.isEmpty ? "ANONYMIZED" : patientName)
                changed = true
            } else if group == 0x0010 && element == 0x0020 {
                overwriteString(&data, offset: valueOffset, length: valueLength, replacement: patientID.isEmpty ? "000000" : patientID)
                changed = true
            }

            offset = valueOffset + valueLength
            if offset % 2 == 1 { offset += 1 }
        }

        return (true, changed)
    }

    private static func overwriteString(_ data: inout Data, offset: Int, length: Int, replacement: String) {
        guard length > 0, offset + length <= data.count else { return }
        let replacementBytes = Array(replacement.utf8)
        for i in 0..<length {
            data[offset + i] = i < replacementBytes.count ? replacementBytes[i] : 0x20
        }
    }

    private static func usesLongLengthVR(_ vr: String) -> Bool {
        ["OB", "OD", "OF", "OL", "OV", "OW", "SQ", "UC", "UR", "UT", "UN"].contains(vr)
    }

    private static func readUInt16(_ data: Data, _ offset: Int, littleEndian: Bool) -> UInt16 {
        guard offset + 1 < data.count else { return 0 }
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1])
        return littleEndian ? (b0 | (b1 << 8)) : ((b0 << 8) | b1)
    }

    private static func readUInt32(_ data: Data, _ offset: Int, littleEndian: Bool) -> UInt32 {
        guard offset + 3 < data.count else { return 0 }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        if littleEndian {
            return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        }
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }
}
