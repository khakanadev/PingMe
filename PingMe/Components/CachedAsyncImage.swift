import SwiftUI

// MARK: - Cached Async Image
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let urlString: String?
    let mediaId: UUID?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    init(
        urlString: String?,
        mediaId: UUID? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.urlString = urlString
        self.mediaId = mediaId
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task {
            await loadImage()
        }
        .onChange(of: urlString) { _, _ in
            Task {
                await loadImage()
            }
        }
        .onChange(of: mediaId) { _, _ in
            Task {
                await loadImage()
            }
        }
    }
    
    private func loadImage() async {
        // If we have mediaId, use API endpoint (for authenticated access)
        if let mediaId = mediaId {
            isLoading = true
            defer { isLoading = false }
            
            if let loadedImage = await ImageCacheService.shared.getMediaImage(mediaId: mediaId) {
                await MainActor.run {
                    image = loadedImage
                }
            } else {
                await MainActor.run {
                    image = nil
                }
            }
            return
        }
        
        // Otherwise, try direct URL (for public images like avatars)
        guard let urlString = urlString, !urlString.isEmpty else {
            await MainActor.run {
                image = nil
            }
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // getImage will load from cache or network
        if let loadedImage = await ImageCacheService.shared.getImage(from: urlString) {
            await MainActor.run {
                image = loadedImage
            }
        } else {
            await MainActor.run {
                image = nil
            }
        }
    }
}

// MARK: - Convenience Initializer
extension CachedAsyncImage where Placeholder == AnyView {
    init(
        urlString: String?,
        mediaId: UUID? = nil,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.urlString = urlString
        self.mediaId = mediaId
        self.content = content
        self.placeholder = {
            AnyView(ProgressView())
        }
    }
}
