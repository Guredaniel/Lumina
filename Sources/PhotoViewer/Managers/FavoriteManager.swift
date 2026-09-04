import Foundation

/// Manages favorite photos persistence and querying.
class FavoriteManager {
    // MARK: - Properties
    var favoritePaths: Set<String> = []
    
    // MARK: - Favorite Management
    
    /// Toggles the favorite status of a photo.
    /// - Parameter photoPath: The file path of the photo.
    func toggleFavorite(photoPath: String) {
        if favoritePaths.contains(photoPath) {
            favoritePaths.remove(photoPath)
            SQLiteDatabase.shared.setFavorite(urlPath: photoPath, isFavorite: false)
        } else {
            favoritePaths.insert(photoPath)
            SQLiteDatabase.shared.setFavorite(urlPath: photoPath, isFavorite: true)
        }
        saveUserDefaultsBackup()
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
        SQLiteDatabase.shared.setFavorite(urlPath: photoPath, isFavorite: true)
        saveUserDefaultsBackup()
    }
    
    /// Removes a photo from favorites.
    /// - Parameter photoPath: The file path of the photo.
    func removeFavorite(photoPath: String) {
        favoritePaths.remove(photoPath)
        SQLiteDatabase.shared.setFavorite(urlPath: photoPath, isFavorite: false)
        saveUserDefaultsBackup()
    }
    
    /// Clears all favorites.
    func clearFavorites() {
        for path in favoritePaths {
            SQLiteDatabase.shared.setFavorite(urlPath: path, isFavorite: false)
        }
        favoritePaths.removeAll()
        saveUserDefaultsBackup()
    }
    
    /// Loads favorites from persistent storage (SQLite, falling back to legacy UserDefaults).
    func loadFavorites() {
        let dbFavorites = SQLiteDatabase.shared.fetchFavoritePaths()
        if !dbFavorites.isEmpty {
            favoritePaths = dbFavorites
        } else {
            // Check for legacy favorites in UserDefaults and migrate them to SQLite
            let defaults = UserDefaults.standard
            let key = AppConstants.UserDefaultsKeys.favoritePhotoPaths
            if let saved = defaults.stringArray(forKey: key), !saved.isEmpty {
                favoritePaths = Set(saved)
                SQLiteDatabase.shared.syncFavorites(favoritePaths)
            }
        }
    }
    
    /// Saves favorites backup to UserDefaults.
    private func saveUserDefaultsBackup() {
        let defaults = UserDefaults.standard
        let key = AppConstants.UserDefaultsKeys.favoritePhotoPaths
        defaults.set(Array(favoritePaths), forKey: key)
    }
}
