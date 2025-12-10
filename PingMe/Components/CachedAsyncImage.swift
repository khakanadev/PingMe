import SwiftUI

// MARK: - Cached Async Image
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let urlString: String?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    init(
        urlString: String?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.urlString = urlString
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
    }
    
    private func loadImage() async {
        guard let urlString = urlString, !urlString.isEmpty else {
            image = nil
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        if let cachedImage = await ImageCacheService.shared.getImage(from: urlString) {
            await MainActor.run {
                image = cachedImage
            }
        }
    }
}

// MARK: - Convenience Initializer
extension CachedAsyncImage where Placeholder == AnyView {
    init(
        urlString: String?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.urlString = urlString
        self.content = content
        self.placeholder = {
            AnyView(ProgressView())
        }
    }
}
