import SwiftUI

struct GalleryView: View {
    @ObservedObject var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: LibraryItemRecord?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if libraryStore.items.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(libraryStore.items) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                GalleryThumbnail(libraryStore: libraryStore, item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedItem) { item in
                MediaDetailView(libraryStore: libraryStore, item: item)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.4))
            Text("No captures yet")
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

private struct GalleryThumbnail: View {
    @ObservedObject var libraryStore: LibraryStore
    let item: LibraryItemRecord

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = UIImage(contentsOfFile: libraryStore.thumbnailURL(for: item).path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
            } else {
                Color.gray.opacity(0.3)
                    .aspectRatio(1, contentMode: .fill)
            }
            if item.kind.isVideo {
                Image(systemName: "video.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(4)
            } else if item.hasOriginalsToCompare {
                Image(systemName: "square.stack")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
        .frame(minHeight: 100)
        .contentShape(Rectangle())
    }
}
