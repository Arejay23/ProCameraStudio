import AVKit
import CoreImage
import SwiftUI

struct MediaDetailView: View {
    @ObservedObject var libraryStore: LibraryStore
    let item: LibraryItemRecord
    @Environment(\.dismiss) private var dismiss
    @State private var showingOriginal = false
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false

    private var currentItem: LibraryItemRecord {
        libraryStore.items.first(where: { $0.id == item.id }) ?? item
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                mediaView
                metadataPanel
            }
            .background(Color.black)
            .navigationTitle(currentItem.kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if currentItem.hasOriginalsToCompare || currentItem.hasEdit {
                        Button(showingOriginal ? "Edited" : "Original") {
                            showingOriginal.toggle()
                        }
                        .font(.caption)
                    }
                    ShareLink(item: libraryStore.mediaURL(for: currentItem))
                    if !currentItem.kind.isVideo {
                        Button("Edit") { isEditing = true }
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    libraryStore.delete(currentItem)
                    dismiss()
                }
            }
            .sheet(isPresented: $isEditing) {
                PhotoEditView(libraryStore: libraryStore, item: currentItem)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var mediaView: some View {
        if currentItem.kind.isVideo {
            VideoPlayer(player: AVPlayer(url: libraryStore.mediaURL(for: currentItem)))
        } else if let image = Self.loadDisplayImage(url: displayURL) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Color.gray.opacity(0.3)
        }
    }

    private var displayURL: URL {
        if showingOriginal {
            return libraryStore.originalMediaURLs(for: currentItem).first ?? libraryStore.mediaURL(for: currentItem)
        }
        return libraryStore.editedMediaURL(for: currentItem) ?? libraryStore.mediaURL(for: currentItem)
    }

    /// UIImage can't reliably decode RAW/DNG; CIImage can, via ImageIO under
    /// the hood, so it's the fallback for that case.
    private static func loadDisplayImage(url: URL) -> UIImage? {
        if let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        if let ciImage = CIImage(contentsOf: url) {
            return UIImage(ciImage: ciImage)
        }
        return nil
    }

    private var metadataPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(currentItem.width)×\(currentItem.height) · \(currentItem.formatLabel)")
            if let duration = currentItem.durationSeconds {
                Text(String(format: "%.1fs", duration))
            }
            Text(String(format: "%.1f MB", Double(currentItem.fileSizeBytes) / 1_000_000))
            HStack(spacing: 12) {
                if let iso = currentItem.iso {
                    Text("ISO \(Int(iso))")
                }
                if let exposure = currentItem.exposureTimeSeconds, exposure > 0 {
                    Text(exposure >= 1 ? String(format: "%.1fs", exposure) : "1/\(Int((1 / exposure).rounded()))")
                }
                if let fNumber = currentItem.fNumber {
                    Text(String(format: "f/%.1f", fNumber))
                }
            }
            Text(currentItem.captureDate.formatted(date: .abbreviated, time: .shortened))
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.8))
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
