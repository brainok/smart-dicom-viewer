import Foundation
import UniformTypeIdentifiers

enum DropItemResolver {
    static let acceptedTypes: [UTType] = [
        DragPasteboardTypes.seriesIndexUTType,
        .fileURL,
        .url,
        .folder,
        .plainText,
        .text,
        .item
    ]

    private final class OneShotURLReceiver {
        private let lock = NSLock()
        private var didSend = false

        func send(_ url: URL, onURL: @escaping (URL) -> Void) {
            lock.lock()
            guard !didSend else {
                lock.unlock()
                return
            }
            didSend = true
            lock.unlock()
            DispatchQueue.main.async { onURL(url) }
        }
    }

    static func handle(
        providers: [NSItemProvider],
        onSeriesIndex: @escaping (Int) -> Void,
        onURL: @escaping (URL) -> Void
    ) -> Bool {
        if loadCustomSeriesIndex(from: providers, onSeriesIndex: onSeriesIndex) {
            return true
        }
        if loadURL(from: providers, onURL: onURL) {
            return true
        }
        if loadTextSeriesIndex(from: providers, onSeriesIndex: onSeriesIndex) {
            return true
        }
        return false
    }

    private static func loadCustomSeriesIndex(
        from providers: [NSItemProvider],
        onSeriesIndex: @escaping (Int) -> Void
    ) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(DragPasteboardTypes.seriesIndexIdentifier) {
                provider.loadDataRepresentation(forTypeIdentifier: DragPasteboardTypes.seriesIndexIdentifier) { data, _ in
                    guard let index = data.flatMap(seriesIndex(from:)) else { return }
                    DispatchQueue.main.async { onSeriesIndex(index) }
                }
                return true
            }
        }

        return false
    }

    private static func loadTextSeriesIndex(
        from providers: [NSItemProvider],
        onSeriesIndex: @escaping (Int) -> Void
    ) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                    guard let index = data.flatMap(seriesIndex(from:)) else { return }
                    DispatchQueue.main.async { onSeriesIndex(index) }
                }
                return true
            }
        }

        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                    guard let text = value as? String,
                          let index = seriesIndex(from: text) else { return }
                    DispatchQueue.main.async { onSeriesIndex(index) }
                }
                return true
            }
        }

        return false
    }

    private static func loadURL(
        from providers: [NSItemProvider],
        onURL: @escaping (URL) -> Void
    ) -> Bool {
        let receiver = OneShotURLReceiver()
        var attemptedURLLoad = false

        for provider in providers {
            for identifier in DragPasteboardTypes.fileURLTypeIdentifiers {
                if provider.hasItemConformingToTypeIdentifier(identifier) {
                    attemptedURLLoad = true
                    provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                        guard let url = data.flatMap(DragPasteboardTypes.fileURL(from:)) else { return }
                        receiver.send(url, onURL: onURL)
                    }
                }
            }
        }

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                attemptedURLLoad = true
                _ = provider.loadObject(ofClass: URL.self) { value, _ in
                    guard let url = value else { return }
                    receiver.send(url, onURL: onURL)
                }
            }
        }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                attemptedURLLoad = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
                    guard let url = data.flatMap(DragPasteboardTypes.fileURL(from:)) else { return }
                    receiver.send(url, onURL: onURL)
                }
            }
        }

        for provider in providers {
            for identifier in DragPasteboardTypes.fileRepresentationTypeIdentifiers {
                guard provider.hasItemConformingToTypeIdentifier(identifier) else { continue }
                attemptedURLLoad = true
                provider.loadInPlaceFileRepresentation(forTypeIdentifier: identifier) { url, _, _ in
                    guard let url else { return }
                    receiver.send(url, onURL: onURL)
                }
            }
        }

        return attemptedURLLoad
    }

    private static func seriesIndex(from data: Data) -> Int? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return seriesIndex(from: text)
    }

    private static func seriesIndex(from text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
