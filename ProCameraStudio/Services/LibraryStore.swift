import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
protocol LibraryStoring: AnyObject {
    var items: [LibraryItemRecord] { get }

    @discardableResult
    func addPhoto(
        data: Data,
        kind: LibraryItemKind,
        width: Int,
        height: Int,
        formatLabel: String,
        iso: Double?,
        exposureTimeSeconds: Double?,
        fNumber: Double?,
        originals: [Data]
    ) -> LibraryItemRecord?

    @discardableResult
    func addVideo(fileURL: URL, width: Int, height: Int, durationSeconds: Double, formatLabel: String) -> LibraryItemRecord?

    func mediaURL(for item: LibraryItemRecord) -> URL
    func originalMediaURLs(for item: LibraryItemRecord) -> [URL]
    func thumbnailURL(for item: LibraryItemRecord) -> URL
    func editedMediaURL(for item: LibraryItemRecord) -> URL?

    @discardableResult
    func saveEdit(for item: LibraryItemRecord, editedData: Data) -> LibraryItemRecord?
    @discardableResult
    func revertEdit(for item: LibraryItemRecord) -> LibraryItemRecord?

    func delete(_ item: LibraryItemRecord)
}

/// The app's own private media library — lives entirely in the app sandbox
/// (Documents/MediaLibrary), independent of the Photos library. This is what
/// lets the gallery exist without upgrading past add-only Photos permission:
/// every capture path also writes a copy here, and the gallery reads only
/// from here, never from Photos.
@MainActor
final class LibraryStore: ObservableObject, LibraryStoring {
    @Published private(set) var items: [LibraryItemRecord] = []

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let mediaDirURL: URL
    private let thumbsDirURL: URL
    private let originalsDirURL: URL
    private let editsDirURL: URL
    private let indexURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootURL = documents.appendingPathComponent("MediaLibrary", isDirectory: true)
        mediaDirURL = rootURL.appendingPathComponent("media", isDirectory: true)
        thumbsDirURL = rootURL.appendingPathComponent("thumbs", isDirectory: true)
        originalsDirURL = rootURL.appendingPathComponent("originals", isDirectory: true)
        editsDirURL = rootURL.appendingPathComponent("edits", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("index.json")

        for url in [rootURL, mediaDirURL, thumbsDirURL, originalsDirURL, editsDirURL] {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        loadIndex()
    }

    @discardableResult
    func addPhoto(
        data: Data,
        kind: LibraryItemKind,
        width: Int,
        height: Int,
        formatLabel: String,
        iso: Double?,
        exposureTimeSeconds: Double?,
        fNumber: Double?,
        originals: [Data]
    ) -> LibraryItemRecord? {
        let id = UUID()
        let fileName = "\(id.uuidString).\(fileExtension(for: formatLabel))"
        guard (try? data.write(to: mediaDirURL.appendingPathComponent(fileName))) != nil else { return nil }

        let thumbName = "\(id.uuidString).jpg"
        if let thumbData = Self.makeImageThumbnail(from: data) {
            try? thumbData.write(to: thumbsDirURL.appendingPathComponent(thumbName))
        }

        var originalNames: [String] = []
        if !originals.isEmpty {
            let itemOriginalsDir = originalsDirURL.appendingPathComponent(id.uuidString, isDirectory: true)
            try? fileManager.createDirectory(at: itemOriginalsDir, withIntermediateDirectories: true)
            for (index, originalData) in originals.enumerated() {
                let originalName = "\(index).heic"
                if (try? originalData.write(to: itemOriginalsDir.appendingPathComponent(originalName))) != nil {
                    originalNames.append(originalName)
                }
            }
        }

        let record = LibraryItemRecord(
            id: id,
            kind: kind,
            captureDate: Date(),
            mediaFileName: fileName,
            thumbnailFileName: thumbName,
            width: width,
            height: height,
            fileSizeBytes: data.count,
            formatLabel: formatLabel,
            iso: iso,
            exposureTimeSeconds: exposureTimeSeconds,
            fNumber: fNumber,
            durationSeconds: nil,
            originalFileNames: originalNames,
            editFileName: nil
        )
        items.insert(record, at: 0)
        saveIndex()
        return record
    }

    @discardableResult
    func addVideo(fileURL: URL, width: Int, height: Int, durationSeconds: Double, formatLabel: String) -> LibraryItemRecord? {
        let id = UUID()
        let fileName = "\(id.uuidString).mov"
        let destination = mediaDirURL.appendingPathComponent(fileName)
        do {
            try fileManager.copyItem(at: fileURL, to: destination)
        } catch {
            return nil
        }

        let thumbName = "\(id.uuidString).jpg"
        if let thumbData = Self.makeVideoThumbnail(from: destination) {
            try? thumbData.write(to: thumbsDirURL.appendingPathComponent(thumbName))
        }

        let fileSize = (try? fileManager.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
        let record = LibraryItemRecord(
            id: id,
            kind: .video,
            captureDate: Date(),
            mediaFileName: fileName,
            thumbnailFileName: thumbName,
            width: width,
            height: height,
            fileSizeBytes: fileSize,
            formatLabel: formatLabel,
            iso: nil,
            exposureTimeSeconds: nil,
            fNumber: nil,
            durationSeconds: durationSeconds,
            originalFileNames: [],
            editFileName: nil
        )
        items.insert(record, at: 0)
        saveIndex()
        return record
    }

    func mediaURL(for item: LibraryItemRecord) -> URL {
        mediaDirURL.appendingPathComponent(item.mediaFileName)
    }

    func originalMediaURLs(for item: LibraryItemRecord) -> [URL] {
        guard !item.originalFileNames.isEmpty else { return [] }
        let dir = originalsDirURL.appendingPathComponent(item.id.uuidString, isDirectory: true)
        return item.originalFileNames.map { dir.appendingPathComponent($0) }
    }

    func thumbnailURL(for item: LibraryItemRecord) -> URL {
        thumbsDirURL.appendingPathComponent(item.thumbnailFileName)
    }

    func editedMediaURL(for item: LibraryItemRecord) -> URL? {
        guard let editFileName = item.editFileName else { return nil }
        return editsDirURL.appendingPathComponent(editFileName)
    }

    @discardableResult
    func saveEdit(for item: LibraryItemRecord, editedData: Data) -> LibraryItemRecord? {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        let editFileName = "\(item.id.uuidString).heic"
        guard (try? editedData.write(to: editsDirURL.appendingPathComponent(editFileName))) != nil else { return nil }
        items[index].editFileName = editFileName
        saveIndex()
        return items[index]
    }

    @discardableResult
    func revertEdit(for item: LibraryItemRecord) -> LibraryItemRecord? {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        if let editFileName = items[index].editFileName {
            try? fileManager.removeItem(at: editsDirURL.appendingPathComponent(editFileName))
        }
        items[index].editFileName = nil
        saveIndex()
        return items[index]
    }

    func delete(_ item: LibraryItemRecord) {
        items.removeAll { $0.id == item.id }
        try? fileManager.removeItem(at: mediaURL(for: item))
        try? fileManager.removeItem(at: thumbsDirURL.appendingPathComponent(item.thumbnailFileName))
        if let editFileName = item.editFileName {
            try? fileManager.removeItem(at: editsDirURL.appendingPathComponent(editFileName))
        }
        if !item.originalFileNames.isEmpty {
            try? fileManager.removeItem(at: originalsDirURL.appendingPathComponent(item.id.uuidString))
        }
        saveIndex()
    }

    // MARK: - Persistence

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([LibraryItemRecord].self, from: data)) ?? []
    }

    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL)
    }

    private func fileExtension(for formatLabel: String) -> String {
        formatLabel.contains("RAW") ? "dng" : "heic"
    }

    private static func makeImageThumbnail(from data: Data, maxPixelSize: CGFloat = 400) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return encodeJPEG(cgImage)
    }

    private static func makeVideoThumbnail(from url: URL) -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return encodeJPEG(cgImage)
    }

    private static func encodeJPEG(_ cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
