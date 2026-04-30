import Foundation

/// Manages favorite photos persistence and querying.
class FavoriteManager {
    // MARK: - Properties
    var favoritePaths: Set<String> = [] {
        didSet {
            saveFavorites()
        }
    }
    
    // MARK: - Favorite Management
    
    /// Toggles the favorite status of a photo.
    /// - Parameter photoPath: The file path of the photo.
    func toggleFavorite(photoPath: String) {
        if favoritePaths.contains(photoPath) {
            favoritePaths.remove(photoPath)
        } else {
            favoritePaths.insert(photoPath)
        }
    }
    
    /// Checks if a photo is marked as favorite.
    /// - Parameter photoPath: The file path of the photo.
    /// - Returns: True if the photo is a favorite, false otherwise.
    func isFavorite(photoPath: String) -> Bool {
        return favoritePaths.contains(photoPath)
    }
    
    /// Adds a photo to favorites.
    /// - Parameter photoPath: The file path of the photo.
    func addFavorite(photoPath: String) {
        favoritePaths.insert(photoPath)
    }
    
    /// Removes a photo from favorites.
    /// - Parameter photoPath: The file path of the photo.
    func removeFavorite(photoPath: String) {
        favoritePaths.remove(photoPath)
    }
    
    /// Clears all favorites.
    func clearFavorites() {
        favoritePaths = []
    }
    
    /// Loads favorites from persistent storage.
    func loadFavorites() {
        let defaults = UserDefaults.standard
        let key = AppConstants.UserDefaultsKeys.favoritePhotoPaths
        
        if let saved = defaults.stringArray(forKey: key) {
            favoritePaths = Set(saved)
        }
    }
    
    /// Saves favorites to persistent storage.
    private func saveFavorites() {
        let defaults = UserDefaults.standard
        let key = AppConstants.UserDefaultsKeys.favoritePhotoPaths
        defaults.set(Array(favoritePaths), forKey: key)
    }
}
