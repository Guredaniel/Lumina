import Foundation

@MainActor
class PhotoViewModel: ObservableObject {
    @Published var photoMonths: [PhotoMonth] = []
    @Published var isLoading = false
    @Published var selectedPhoto: Photo? = nil
    @Published var errorMessage: String? = nil
    
    @Published var selectedDirectories: [URL] = []
    @Published var favoritePaths: Set<String> = []
    
    private let photoScanner = PhotoScanner.shared
    
    init() {
        loadFavorites()
    }
    
    func toggleFavorite(photo: Photo) {
        if favoritePaths.contains(photo.url.path) {
            favoritePaths.remove(photo.url.path)
        } else {
            favoritePaths.insert(photo.url.path)
        }
        saveFavorites()
    }
    
    func isFavorite(photo: Photo) -> Bool {
        favoritePaths.contains(photo.url.path)
    }
    
    private func loadFavorites() {
        if let saved = UserDefaults.standard.stringArray(forKey: "favoritePhotoPaths") {
            favoritePaths = Set(saved)
        }
    }
    
    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoritePaths), forKey: "favoritePhotoPaths")
    }
    
    func addDirectory() {
        guard let directory = photoScanner.selectDirectory() else {
            return
        }
        
        if !selectedDirectories.contains(directory) {
            selectedDirectories.append(directory)
            saveDirectories()
            scanAllDirectories()
        }
    }
    
    func removeDirectory(_ url: URL) {
        selectedDirectories.removeAll { $0 == url }
        saveDirectories()
        scanAllDirectories()
    }
    
    func scanAllDirectories() {
        isLoading = true
        errorMessage = nil
        photoMonths = []
        
        if selectedDirectories.isEmpty {
            isLoading = false
            return
        }
        
        Task {
            do {
                let months = try await photoScanner.scanDirectories(selectedDirectories)
                self.photoMonths = months
                isLoading = false
                
                if months.isEmpty {
                    errorMessage = "No photos found in the selected directories"
                }
            } catch {
                isLoading = false
                errorMessage = "Error scanning directories: \(error.localizedDescription)"
            }
        }
    }
    
    func loadDirectories() {
        if let paths = UserDefaults.standard.stringArray(forKey: "photoDirectories") {
            selectedDirectories = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        } else if let legacyPath = UserDefaults.standard.string(forKey: "lastPhotoDirectory") {
            let directory = URL(fileURLWithPath: legacyPath)
            if FileManager.default.fileExists(atPath: legacyPath) {
                selectedDirectories = [directory]
                saveDirectories()
            }
        }
        scanAllDirectories()
    }
    
    private func saveDirectories() {
        UserDefaults.standard.set(selectedDirectories.map { $0.path }, forKey: "photoDirectories")
    }
    
    func clearPhotos() {
        photoMonths = []
        selectedPhoto = nil
        errorMessage = nil
    }
    
    func getPhotosInMonth(_ month: PhotoMonth) -> [Photo] {
        return month.sortedPhotos
    }
    
    var allPhotosFlat: [Photo] {
        photoMonths.flatMap { $0.sortedPhotos }
    }
    
    func nextPhoto(after photo: Photo) -> Photo? {
        let all = allPhotosFlat
        guard let index = all.firstIndex(of: photo) else { return nil }
        if index < all.count - 1 {
            return all[index + 1]
        }
        return nil
    }
    
    func previousPhoto(before photo: Photo) -> Photo? {
        let all = allPhotosFlat
        guard let index = all.firstIndex(of: photo) else { return nil }
        if index > 0 {
            return all[index - 1]
        }
        return nil
    }
    
    func deletePhoto(_ photo: Photo) {
        do {
            // Move file to trash
            try FileManager.default.trashItem(at: photo.url, resultingItemURL: nil)
            
            // Move associated live photo video to trash if it exists
            if let videoURL = photo.videoURL, FileManager.default.fileExists(atPath: videoURL.path) {
                try? FileManager.default.trashItem(at: videoURL, resultingItemURL: nil)
            }
            
            // Remove from the photoMonths array
            for i in 0..<photoMonths.count {
                if let photoIndex = photoMonths[i].photos.firstIndex(of: photo) {
                    var updatedPhotos = photoMonths[i].photos
                    updatedPhotos.remove(at: photoIndex)
                    
                    if updatedPhotos.isEmpty {
                        photoMonths.remove(at: i)
                    } else {
                        photoMonths[i] = PhotoMonth(year: photoMonths[i].year, month: photoMonths[i].month, photos: updatedPhotos)
                    }
                    break
                }
            }
            
            // If the deleted photo is currently selected in PreviewView, we need to handle that.
            // This is typically handled by the PreviewView itself moving to the next/prev photo before calling delete.
            if selectedPhoto == photo {
                selectedPhoto = nil
            }
        } catch {
            print("DEBUG: Failed to delete photo: \(error)")
            self.errorMessage = "Failed to move photo to trash: \(error.localizedDescription)"
        }
    }
}
