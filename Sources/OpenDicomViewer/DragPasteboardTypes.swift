import UniformTypeIdentifiers
import AppKit

enum DragPasteboardTypes {
    static let seriesIndexIdentifier = "com.smartdicomviewer.series-index"
    static let seriesIndexUTType = UTType(exportedAs: seriesIndexIdentifier)
    static let seriesIndexPasteboardType = NSPasteboard.PasteboardType(seriesIndexIdentifier)

    static let fileURLPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .init("public.file-url"),
        .init("public.url"),
        .init("NSFilenamesPboardType"),
        .init("com.apple.pasteboard.promised-file-url")
    ]

    static let fileURLTypeIdentifiers: [String] = [
        UTType.fileURL.identifier,
        "public.file-url",
        "com.apple.pasteboard.promised-file-url",
        UTType.url.identifier,
        "public.url"
    ]

    static let fileRepresentationTypeIdentifiers: [String] = [
        UTType.fileURL.identifier,
        UTType.folder.identifier,
        UTType.item.identifier,
        UTType.data.identifier,
        "public.file-url",
        "public.folder",
        "public.item",
        "public.data"
    ]

    static func fileURL(from pasteboard: NSPasteboard) -> URL? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
           let url = urls.first {
            return url
        }

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL],
           let url = urls.first as URL? {
            return url
        }

        if let fileNames = pasteboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String],
           let first = fileNames.first {
            return URL(fileURLWithPath: first)
        }

        for type in fileURLPasteboardTypes {
            if let text = pasteboard.string(forType: type),
               let url = fileURL(from: text) {
                return url
            }
            if let data = pasteboard.data(forType: type),
               let url = fileURL(from: data) {
                return url
            }
        }

        return nil
    }

    static func fileURL(from data: Data) -> URL? {
        if data.contains(0),
           let text = String(data: data, encoding: .utf8),
           let url = fileURL(from: text) {
            return url
        }
        if let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
            return url
        }
        if let url = fileURLFromPropertyListData(data) {
            return url
        }
        if let text = String(data: data, encoding: .utf8),
           let url = fileURL(from: text) {
            return url
        }
        if let text = String(data: data, encoding: .utf16),
           let url = fileURL(from: text) {
            return url
        }
        return nil
    }

    static func fileURL(from text: String) -> URL? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        guard !cleaned.isEmpty else { return nil }

        if let url = URL(string: cleaned), url.isFileURL {
            return url
        }
        if cleaned.hasPrefix("/") || cleaned.hasPrefix("~") {
            return URL(fileURLWithPath: (cleaned as NSString).expandingTildeInPath)
        }
        return nil
    }

    private static func fileURLFromPropertyListData(_ data: Data) -> URL? {
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) else {
            return nil
        }
        return fileURL(fromPropertyList: plist)
    }

    private static func fileURL(fromPropertyList plist: Any) -> URL? {
        if let url = plist as? URL, url.isFileURL {
            return url
        }
        if let string = plist as? String {
            return fileURL(from: string)
        }
        if let strings = plist as? [String] {
            return strings.compactMap(fileURL(from:)).first
        }
        if let values = plist as? [Any] {
            return values.compactMap(fileURL(fromPropertyList:)).first
        }
        if let dict = plist as? [String: Any] {
            for key in ["NSURL", "URL", "fileURL", "path", "NSFilenames"] {
                if let value = dict[key], let url = fileURL(fromPropertyList: value) {
                    return url
                }
            }
        }
        return nil
    }
}
