import SwiftUI

// MARK: - Media Viewer View
struct MediaViewerView: View {
    let mediaId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 1.0 {
                                    withAnimation {
                                        scale = 1.0
                                        lastScale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                } else if scale > 3.0 {
                                    withAnimation {
                                        scale = 3.0
                                        lastScale = 3.0
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo")
                        .font(.system(size: 50))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Не удалось загрузить изображение")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        isLoading = true
        
        if let loadedImage = await ImageCacheService.shared.getMediaImage(mediaId: mediaId) {
            await MainActor.run {
                image = loadedImage
                isLoading = false
            }
        } else {
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

