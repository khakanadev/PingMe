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
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = UIImage(data: data) else {
                return nil
            }
            
            // Store in both caches
            let cachedResponse = CachedURLResponse(response: httpResponse, data: data)
            urlCache.storeCachedResponse(cachedResponse, for: URLRequest(url: url))
            cache.setObject(image, forKey: urlString as NSString)
            
            return image
        } catch {
            print("Failed to load image: \(error)")
            return nil
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
        urlCache.removeAllCachedResponses()
    }
}
