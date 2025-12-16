import Foundation
import UIKit

// MARK: - Media Service
final class MediaService {
    private let baseURL = "https://pingme-messenger.ru"
    
    func uploadMedia(image: UIImage, conversationId: UUID, messageId: UUID? = nil) async throws -> APIResponse<[MediaResponse]> {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            throw AuthError.serverError("Missing access token")
        }
        
        guard let imageData = prepareMediaData(from: image) else {
            throw AuthError.serverError("Failed to convert image to data")
        }
        
        let boundary = UUID().uuidString
        var urlString = "\(baseURL)/api/v1/media/upload?conversation_id=\(conversationId.uuidString)"
        if let messageId = messageId {
            urlString += "&message_id=\(messageId.uuidString)"
        }
        guard let url = URL(string: urlString) else {
            throw AuthError.invalidURL
        }
        
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.appendMultipartData(
            name: "files",
            filename: "media.jpg",
            mimeType: "image/jpeg",
            data: imageData,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body
        
        
        return try await perform(request: request)
    }
    
    // MARK: - Helpers
    /// Resize/compress media to avoid 413 (Request Entity Too Large) - same as avatar compression
    private func prepareMediaData(from image: UIImage) -> Data? {
        let originalSize = image.size
        let originalData = image.jpegData(compressionQuality: 1.0)
        let originalSizeBytes = originalData?.count ?? 0
        let originalSizeKB = originalSizeBytes / 1024
        
        let maxDimension: CGFloat = 512 // Same as avatar to avoid 413 errors
        let aspectWidth = maxDimension / image.size.width
        let aspectHeight = maxDimension / image.size.height
        let scaleFactor = min(1.0, min(aspectWidth, aspectHeight)) // downscale only
        
        let finalImage: UIImage
        if scaleFactor < 1.0 {
            let newSize = CGSize(width: image.size.width * scaleFactor, height: image.size.height * scaleFactor)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            finalImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            finalImage = image
        }
        
        // Use same compression as avatar (0.65) to keep size small
        guard let compressedData = finalImage.jpegData(compressionQuality: 0.65) else {
            return nil
        }
        
        let compressedSizeBytes = compressedData.count
        let compressedSizeKB = compressedSizeBytes / 1024
        let reductionPercent = originalSizeBytes > 0
            ? Int((1.0 - Double(compressedSizeBytes) / Double(originalSizeBytes)) * 100)
            : 0
        
        return compressedData
    }
    
    private func perform<T: Codable>(request: URLRequest) async throws -> APIResponse<T> {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        if let url = request.url?.absoluteString {
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            let dateFormatter = DateFormatter()
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
                "yyyy-MM-dd'T'HH:mm:ss.SSSSSZ",
                "yyyy-MM-dd'T'HH:mm:ss.SSS",
                "yyyy-MM-dd'T'HH:mm:ss",
            ]
            
            for format in formats {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string \(dateString)"
            )
        }
        
        // Log response body for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            let preview = String(responseString.prefix(500))
        }
        
        if httpResponse.statusCode >= 400 {
            if let serverMessage = String(data: data, encoding: .utf8) {
                throw AuthError.serverError(serverMessage)
            }
            throw AuthError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        do {
            // Try decoding standard APIResponse
            let apiResponse = try decoder.decode(APIResponse<T>.self, from: data)
            if let dataValue = apiResponse.data {
            }
            return apiResponse
        } catch {
            throw AuthError.decodingError
        }
    }
}

