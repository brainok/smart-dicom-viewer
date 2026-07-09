import XCTest
@testable import OpenDicomViewer

final class DICOMAnonymizerTests: XCTestCase {
    func testAnonymizeFolderRewritesImageDICOMWithDCMTK() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenDicomViewerAnonymizerTests-\(UUID().uuidString)", isDirectory: true)
        let source = tempRoot.appendingPathComponent("source", isDirectory: true)
        let destination = tempRoot.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/PublicDICOMAnnotations/OFFIS_GSPS/image_256x256_16x16_1.0x1.0.dcm")
        let input = source.appendingPathComponent("image.dcm")
        try FileManager.default.copyItem(at: fixture, to: input)

        let result = try DICOMAnonymizer.anonymizeFolder(
            source: source,
            destination: destination,
            patientName: "YSH",
            patientID: "ID-777"
        )

        XCTAssertEqual(result.totalFiles, 1)
        XCTAssertEqual(result.dicomFiles, 1)
        XCTAssertEqual(result.anonymizedFiles, 1)

        let output = destination.appendingPathComponent("image.dcm")
        let data = try Data(contentsOf: output)
        let parser = SimpleDicomParser(data: data)
        let (elements, _, _) = try parser.parse(stopAtPixelData: true)
        XCTAssertEqual(
            elements.first { $0.tag == DicomTag(group: 0x0010, element: 0x0010) }?.stringValue,
            "YSH"
        )
        XCTAssertEqual(
            elements.first { $0.tag == DicomTag(group: 0x0010, element: 0x0020) }?.stringValue,
            "ID-777"
        )
    }
}
