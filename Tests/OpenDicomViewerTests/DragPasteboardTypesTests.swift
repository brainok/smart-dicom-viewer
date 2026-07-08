import Foundation
import Testing
@testable import OpenDicomViewer

@Test
func fileURLFromFileURLString() {
    let url = DragPasteboardTypes.fileURL(from: "file:///tmp/example.dcm")
    #expect(url?.path == "/tmp/example.dcm")
}

@Test
func fileURLFromPlainPathString() {
    let url = DragPasteboardTypes.fileURL(from: " /tmp/example.dicom ")
    #expect(url?.path == "/tmp/example.dicom")
}

@Test
func fileURLFromNullTerminatedPasteboardData() {
    let data = Data("file:///tmp/example.ima\0".utf8)
    let url = DragPasteboardTypes.fileURL(from: data)
    #expect(url?.path == "/tmp/example.ima")
}

@Test
func fileURLFromURLDataRepresentation() {
    let source = URL(fileURLWithPath: "/tmp/example-folder")
    let url = DragPasteboardTypes.fileURL(from: source.dataRepresentation)
    #expect(url?.path == "/tmp/example-folder")
}

@Test
func fileURLFromFilenamesPropertyListData() throws {
    let data = try PropertyListSerialization.data(
        fromPropertyList: ["/tmp/example-folder"],
        format: .binary,
        options: 0
    )
    let url = DragPasteboardTypes.fileURL(from: data)
    #expect(url?.path == "/tmp/example-folder")
}
