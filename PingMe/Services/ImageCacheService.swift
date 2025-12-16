import Foundation
import UIKit

// MARK: - Image Cache Service
final class ImageCacheService {
    static let shared = ImageCacheService()
    
    private let cache = NSCache<NSString, UIImage>()
    private let urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
    
    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }
    
    func getImage(from urlString: String) async -> UIImage? {
        // Check memory cache first
        if let cachedImage = cache.object(forKey: urlString as NSString) {
            return cachedImage
        }
        
        // Check disk cache
        guard let url = URL(string: urlString) else { return nil }
        
        if let cachedResponse = urlCache.cachedResponse(for: URLRequest(url: url)),
           let image = UIImage(data: cachedResponse.data) {
            // Store in memory cache for faster access
            cache.setObject(image, forKey: urlString as NSString)
            return image
        }
        
        // Load from network
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                return nil
            }
            
            guard let image = UIImage(data: data) else {
                return nil
            }
            
            
            // Store in both caches
            let cachedResponse = CachedURLResponse(response: httpResponse, data: data)
            urlCache.storeCachedResponse(cachedResponse, for: request)
            cache.setObject(image, forKey: urlString as NSString)
            
            return image
        } catch {
            return nil
        }
    }
    
    /// Load media file through API endpoint (for authenticated access)
    func getMediaImage(mediaId: UUID) async -> UIImage? {
        let cacheKey = "media_\(mediaId.uuidString)"
        
        // Check memory cache first
        if let cachedImage = cache.object(forKey: cacheKey as NSString) {
            return cachedImage
        }
        
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            return nil
        }
        
        let baseURL = "https://pingme-messenger.ru"
        guard let url = URL(string: "\(baseURL)/api/v1/media/\(mediaId.uuidString)") else {
            return nil
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.cachePolicy = .returnCacheDataElseLoad
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                return nil
            }
            
            guard let image = UIImage(data: data) else {
                return nil
            }
            
            
            // Store in cache
            cache.setObject(image, forKey: cacheKey as NSString)
            let cachedResponse = CachedURLResponse(response: httpResponse, data: data)
            urlCache.storeCachedResponse(cachedResponse, for: request)
            
            return image
        } catch {
            return nil
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
        urlCache.removeAllCachedResponses()
    }
}
