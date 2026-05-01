import Foundation

/// Coordinates the scanning process and manages related photo state.
/// Internal utility used by PhotoViewModel to separate scanning logic.
class ScanCoordinator {
    // MARK: - Properties
    var photoMonths: [PhotoMonth] = []
    var isScanning = false
    var isLoading = false
    var errorMessage: String? = nil
    
    // MARK: - Private Properties
    private let photoScanner = PhotoScanner.shared
    
    // MARK: - Photo Navigation
    
    /// Returns all photos in a flat array, grouped by month.
    var allPhotosFlat: [Photo] {
        return photoMonths.flatMap { $0.photos }
    }
    
    /// Finds the next photo after the given photo.
    /// - Parameter photo: The current photo.
    /// - Returns: The next photo, or nil if at the end.
    func nextPhoto(after photo: Photo) -> Photo? {
        let all = allPhotosFlat
        guard let index = all.firstIndex(where: { $0.url == photo.url }) else { return nil }
        return index < all.count - 1 ? all[index + 1] : nil
    }
    
    /// Finds the previous photo before the given photo.
    /// - Parameter photo: The current photo.
    /// - Returns: The previous photo, or nil if at the beginning.
    func previousPhoto(before photo: Photo) -> Photo? {
        let all = allPhotosFlat
        guard let index = all.firstIndex(where: { $0.url == photo.url }) else { return nil }
        return index > 0 ? all[index - 1] : nil
    }
}
