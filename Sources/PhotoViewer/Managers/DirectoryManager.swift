import Foundation

/// Manages directory selection, persistence, and validation for photo scanning.
class DirectoryManager {
    // MARK: - Properties
    var selectedDirectories: [URL] = [] {
        didSet {
            saveDirectories()
        }
    }
    
    private let fileManager = FileManager.default
    private let photoScanner = PhotoScanner.shared
    
    // MARK: - Directory Management
    
    /// Adds a new directory after user selection.
    /// - Returns: The selected directory URL, or nil if user canceled.
    func selectAndAddDirectory() -> URL? {
        guard let directory = photoScanner.selectDirectory() else {
            return nil
        }
        
        if !selectedDirectories.contains(directory) {
            selectedDirectories.append(directory)
            return directory
        }
        return nil
    }
    
    /// Removes a directory from the selection list.
    /// - Parameter url: The directory URL to remove.
    func removeDirectory(_ url: URL) {
        selectedDirectories.removeAll { $0 == url }
    }
    
    /// Loads directories from persistent storage.
    /// Handles migration from legacy single-directory storage.
    func loadDirectories() {
        let defaults = UserDefaults.standard
        let directoriesKey = AppConstants.UserDefaultsKeys.photoDirectories
        let legacyKey = AppConstants.UserDefaultsKeys.lastPhotoDirectory
        
        if let paths = defaults.stringArray(forKey: directoriesKey) {
            selectedDirectories = paths
                .map { URL(fileURLWithPath: $0) }
                .filter { fileManager.fileExists(atPath: $0.path) }
        } else if let legacyPath = defaults.string(forKey: legacyKey) {
            let directory = URL(fileURLWithPath: legacyPath)
            if fileManager.fileExists(atPath: legacyPath) {
                selectedDirectories = [directory]
                saveDirectories() // Migrate to new storage
            }
        }
    }
    
    /// Saves the currently selected directories to persistent storage.
    private func saveDirectories() {
        let defaults = UserDefaults.standard
        let paths = selectedDirectories.map { $0.path }
        defaults.set(paths, forKey: AppConstants.UserDefaultsKeys.photoDirectories)
    }
    
    /// Clears all selected directories.
    func clearDirectories() {
        selectedDirectories = []
    }
    
    /// Checks if at least one directory is selected.
    var hasDirectories: Bool {
        return !selectedDirectories.isEmpty
    }
}
