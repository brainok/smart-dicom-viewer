// DICOMDerivedObject.swift
// OpenDicomViewer
//
// Lightweight classification for non-image DICOM-derived objects discovered
// during directory scanning. Selected GSPS, RTSTRUCT, and simple binary SEG
// objects can be rendered; other derived objects are exposed for inspection.
// Licensed under the MIT License. See LICENSE for details.

import Foundation

enum DICOMDerivedObjectKind: String, CaseIterable, Identifiable {
    case grayscaleSoftcopyPresentationState = "GSPS"
    case colorSoftcopyPresentationState = "Color PR"
    case blendingSoftcopyPresentationState = "Blending PR"
    case rtStructureSet = "RTSTRUCT"
    case dicomSegmentation = "DICOM SEG"
    case surfaceSegmentation = "Surface SEG"
    case structuredReport = "DICOM SR"
    case keyObjectSelection = "Key Object"
    case encapsulatedDocument = "Encapsulated Document"
    case other = "Other DICOM Object"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .grayscaleSoftcopyPresentationState, .colorSoftcopyPresentationState, .blendingSoftcopyPresentationState:
            return "paintbrush.pointed"
        case .rtStructureSet:
            return "point.3.connected.trianglepath.dotted"
        case .dicomSegmentation, .surfaceSegmentation:
            return "square.3.layers.3d"
        case .structuredReport:
            return "doc.text"
        case .keyObjectSelection:
            return "key"
        case .encapsulatedDocument:
            return "doc.richtext"
        case .other:
            return "doc.badge.gearshape"
        }
    }

    var supportSummary: String {
        switch self {
        case .grayscaleSoftcopyPresentationState, .colorSoftcopyPresentationState, .blendingSoftcopyPresentationState:
            return "Detected; vector and text annotations render on matching images when selected."
        case .rtStructureSet:
            return "Detected; planar contours render on matching image slices when selected."
        case .dicomSegmentation:
            return "Detected; native binary segmentation masks render on matching images when selected. Fractional, labelmap, tiled, and exported SEG are not yet implemented."
        case .surfaceSegmentation:
            return "Detected and available for tag inspection; surface mesh rendering is not yet implemented."
        case .structuredReport:
            return "Detected and available for tag inspection; SR content-tree rendering is not yet implemented."
        case .keyObjectSelection:
            return "Detected and available for tag inspection; key-image linking is not yet implemented."
        case .encapsulatedDocument:
            return "Detected and available for tag inspection; document preview is not yet implemented."
        case .other:
            return "Detected and available for tag inspection."
        }
    }
}

struct DICOMDerivedObjectSummary: Identifiable {
    let url: URL
    let kind: DICOMDerivedObjectKind
    let sopClassUID: String
    let modality: String
    let seriesUID: String?
    let seriesDescription: String?
    let studyInstanceUID: String?
    let frameOfReferenceUID: String?
    let instanceNumber: Int?
    let label: String?
    let tags: [DicomElement]

    var id: URL { url }

    var displayTitle: String {
        if let label, !label.isEmpty { return label }
        if let seriesDescription, !seriesDescription.isEmpty { return seriesDescription }
        return url.deletingPathExtension().lastPathComponent
    }

    var detailText: String {
        var parts: [String] = [kind.rawValue]
        if !modality.isEmpty { parts.append(modality) }
        if let instanceNumber { parts.append("Instance \(instanceNumber)") }
        return parts.joined(separator: " | ")
    }

    var supportSummary: String { kind.supportSummary }
}

enum DICOMDerivedObjectParser {
    private static let gspsSOP = "1.2.840.10008.5.1.4.1.1.11.1"
    private static let colorPR = "1.2.840.10008.5.1.4.1.1.11.2"
    private static let pseudoColorPR = "1.2.840.10008.5.1.4.1.1.11.3"
    private static let blendingPR = "1.2.840.10008.5.1.4.1.1.11.4"
    private static let rtStructureSet = "1.2.840.10008.5.1.4.1.1.481.3"
    private static let segmentation = "1.2.840.10008.5.1.4.1.1.66.4"
    private static let surfaceSegmentation = "1.2.840.10008.5.1.4.1.1.66.5"
    private static let tractography = "1.2.840.10008.5.1.4.1.1.66.6"
    private static let keyObjectSelection = "1.2.840.10008.5.1.4.1.1.88.59"
    private static let encapsulatedPDF = "1.2.840.10008.5.1.4.1.1.104.1"
    private static let encapsulatedCDA = "1.2.840.10008.5.1.4.1.1.104.2"

    private static let structuredReportSOPs: Set<String> = [
        "1.2.840.10008.5.1.4.1.1.88.11",
        "1.2.840.10008.5.1.4.1.1.88.22",
        "1.2.840.10008.5.1.4.1.1.88.33",
        "1.2.840.10008.5.1.4.1.1.88.34",
        "1.2.840.10008.5.1.4.1.1.88.35",
        "1.2.840.10008.5.1.4.1.1.88.40",
        "1.2.840.10008.5.1.4.1.1.88.50",
        "1.2.840.10008.5.1.4.1.1.88.65",
        "1.2.840.10008.5.1.4.1.1.88.67",
        "1.2.840.10008.5.1.4.1.1.88.68",
        "1.2.840.10008.5.1.4.1.1.88.69",
        "1.2.840.10008.5.1.4.1.1.88.70",
        "1.2.840.10008.5.1.4.1.1.88.71",
        "1.2.840.10008.5.1.4.1.1.88.72",
        "1.2.840.10008.5.1.4.1.1.88.73",
    ]

    static func classify(sopClassUID: String, modality: String) -> DICOMDerivedObjectKind? {
        let sop = sopClassUID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModality = modality.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if sop == gspsSOP { return .grayscaleSoftcopyPresentationState }
        if sop == colorPR || sop == pseudoColorPR { return .colorSoftcopyPresentationState }
        if sop == blendingPR { return .blendingSoftcopyPresentationState }
        if sop == rtStructureSet || normalizedModality == "RTSTRUCT" { return .rtStructureSet }
        if sop == segmentation || normalizedModality == "SEG" { return .dicomSegmentation }
        if sop == surfaceSegmentation || sop == tractography { return .surfaceSegmentation }
        if structuredReportSOPs.contains(sop) || normalizedModality == "SR" { return .structuredReport }
        if sop == keyObjectSelection || normalizedModality == "KO" { return .keyObjectSelection }
        if sop == encapsulatedPDF || sop == encapsulatedCDA { return .encapsulatedDocument }
        if normalizedModality == "PR" { return .grayscaleSoftcopyPresentationState }
        return nil
    }

    static func parse(url: URL, headerByteLimit: Int = 1_048_576) -> DICOMDerivedObjectSummary? {
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { fileHandle.closeFile() }
            let data = fileHandle.readData(ofLength: headerByteLimit)
            let parser = SimpleDicomParser(data: data)
            let (elements, _, _) = try parser.parse(stopAtPixelData: true)

            func getStr(_ group: UInt16, _ element: UInt16) -> String? {
                elements.first(where: { $0.tag == DicomTag(group: group, element: element) })?
                    .stringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            func getInt(_ group: UInt16, _ element: UInt16) -> Int? {
                if let str = getStr(group, element), let value = Int(str) { return value }
                return elements.first(where: { $0.tag == DicomTag(group: group, element: element) })?.intValue
            }

            let sopClassUID = getStr(0x0008, 0x0016) ?? ""
            let modality = getStr(0x0008, 0x0060) ?? ""
            guard let kind = classify(sopClassUID: sopClassUID, modality: modality) else { return nil }

            let label =
                getStr(0x0070, 0x0080) ?? // Content Label for presentation states
                getStr(0x3006, 0x0002) ?? // Structure Set Label
                getStr(0x0062, 0x0002) ?? // Segment Sequence may not be string, but harmless
                getStr(0x0008, 0x103E)    // Series Description

            return DICOMDerivedObjectSummary(
                url: url,
                kind: kind,
                sopClassUID: sopClassUID,
                modality: modality,
                seriesUID: getStr(0x0020, 0x000E),
                seriesDescription: getStr(0x0008, 0x103E),
                studyInstanceUID: getStr(0x0020, 0x000D),
                frameOfReferenceUID: getStr(0x0020, 0x0052),
                instanceNumber: getInt(0x0020, 0x0013),
                label: label,
                tags: elements
            )
        } catch {
            return nil
        }
    }
}
