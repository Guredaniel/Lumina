import Foundation

/// Custom error type for PhotoViewer operations with localized error messages.
enum PhotoViewerError: LocalizedError {
    case scanFailed(reason: String)
    case fileNotFound(path: String)
    case permissionDenied(path: String)
    case invalidThumbnail(path: String)
    case corruptedMetadata(path: String)
    case invalidDirectory(path: String)
    case fileAccessError(underlyingError: Error)
    
    var errorDescription: String? {
        switch self {
        case .scanFailed(let reason):
            return "Failed to scan directories: \(reason)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied(let path):
            return "Permission denied accessing: \(path)"
        case .invalidThumbnail(let path):
            return "Could not generate thumbnail for: \(path)"
        case .corruptedMetadata(let path):
            return "Corrupted metadata in: \(path)"
        case .invalidDirectory(let path):
            return "Invalid directory: \(path)"
        case .fileAccessError(let underlyingError):
            return "File access error: \(underlyingError.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Check file permissions and try again."
        case .fileNotFound:
            return "The file may have been moved or deleted."
        case .invalidDirectory:
            return "Select a valid directory that exists on your system."
        case .scanFailed:
            return "Try selecting a different directory or check system logs."
        default:
            return nil
        }
    }
}
