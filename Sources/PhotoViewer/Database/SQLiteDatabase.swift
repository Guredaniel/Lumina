import Foundation
import SQLite3

/// Thread-safe SQLite database manager for Lumina.
/// Optimized for SSD endurance (WAL mode, normal sync, batch transactions)
/// and high-performance querying and incremental scanning.
final class SQLiteDatabase: @unchecked Sendable {
    static let shared = SQLiteDatabase()
    
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.photoviewer.database", qos: .userInitiated)
    
    // Default location: ~/Library/Application Support/com.photoviewer/lumina.sqlite
    init(databaseURL: URL? = nil) {
        let fileURL: URL
        if let databaseURL = databaseURL {
            fileURL = databaseURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let appDir = appSupport.appendingPathComponent("com.photoviewer", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            fileURL = appDir.appendingPathComponent("lumina.sqlite")
        }
        
        openDatabase(at: fileURL)
        configurePragmas()
        createTables()
        cleanupDuplicateLivePhotoVideos()
    }
    
    deinit {
        queue.sync {
            if let db = self.db {
                sqlite3_close_v2(db)
                self.db = nil
            }
        }
    }
    
    // MARK: - Setup & Configuration
    
    private func openDatabase(at fileURL: URL) {
        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(fileURL.path, &dbPointer, flags, nil) == SQLITE_OK {
            self.db = dbPointer
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(dbPointer))
            print("SQLiteDatabase: Failed to open database at \(fileURL.path): \(errorMsg)")
            if let dbPointer = dbPointer {
                sqlite3_close_v2(dbPointer)
            }
        }
    }
    
    private func configurePragmas() {
        guard let db = db else { return }
        
        // WAL mode: sequential append writes, reduces SSD write amplification,
        // allows concurrent reading while background scanning writes
        executeRaw("PRAGMA journal_mode = WAL;", db: db)
        
        // Normal sync: crash-safe with WAL, eliminates redundant fsync writes on SSDs
        executeRaw("PRAGMA synchronous = NORMAL;", db: db)
        
        // Foreign keys and cache sizing (2MB memory cache)
        executeRaw("PRAGMA foreign_keys = ON;", db: db)
        executeRaw("PRAGMA cache_size = -2000;", db: db)
    }
    
    private func createTables() {
        guard let db = db else { return }
        
        let createPhotosTable = """
        CREATE TABLE IF NOT EXISTS photos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url_path TEXT UNIQUE NOT NULL,
            filename TEXT NOT NULL,
            date_taken REAL NOT NULL,
            file_modified_date REAL NOT NULL,
            file_size INTEGER NOT NULL,
            is_video INTEGER NOT NULL DEFAULT 0,
            video_path TEXT,
            exif_json TEXT,
            is_favorite INTEGER NOT NULL DEFAULT 0
        );
        """
        
        let createIndexes = """
        CREATE INDEX IF NOT EXISTS idx_photos_date_taken ON photos(date_taken DESC);
        CREATE INDEX IF NOT EXISTS idx_photos_url_path ON photos(url_path);
        CREATE INDEX IF NOT EXISTS idx_photos_is_favorite ON photos(is_favorite);
        """
        
        let createDirectoriesTable = """
        CREATE TABLE IF NOT EXISTS scanned_directories (
            path TEXT PRIMARY KEY,
            last_scan_date REAL NOT NULL
        );
        """
        
        executeRaw(createPhotosTable, db: db)
        executeRaw(createIndexes, db: db)
        executeRaw(createDirectoriesTable, db: db)
    }
    
    @discardableResult
    private func executeRaw(_ sql: String, db: OpaquePointer) -> Bool {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                let message = String(cString: errMsg)
                print("SQLiteDatabase error executing '\(sql)': \(message)")
                sqlite3_free(errMsg)
            }
            return false
        }
        return true
    }
    
    // MARK: - Incremental Scanning Helpers
    
    /// Returns dictionary of known files in the given directory path: [urlPath: (modifiedDate, fileSize)]
    func getKnownFiles(forDirectoryPrefix directoryPath: String) -> [String: (modifiedDate: Date, fileSize: Int)] {
        queue.sync {
            guard let db = self.db else { return [:] }
            
            // Match files whose path starts with the directory path
            let sql = "SELECT url_path, file_modified_date, file_size FROM photos WHERE url_path LIKE ? || '%';"
            var statement: OpaquePointer?
            var result: [String: (modifiedDate: Date, fileSize: Int)] = [:]
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                return [:]
            }
            defer { sqlite3_finalize(statement) }
            
            sqlite3_bind_text(statement, 1, (directoryPath as NSString).utf8String, -1, nil)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let pathCStr = sqlite3_column_text(statement, 0) else { continue }
                let path = String(cString: pathCStr)
                let modTimestamp = sqlite3_column_double(statement, 1)
                let size = Int(sqlite3_column_int64(statement, 2))
                
                result[path] = (Date(timeIntervalSince1970: modTimestamp), size)
            }
            
            return result
        }
    }
    
    /// Batch upserts photos into the database within a single transaction to protect SSD.
    func batchUpsertPhotos(_ items: [(photo: Photo, fileModifiedDate: Date, fileSize: Int)]) {
        guard !items.isEmpty else { return }
        
        queue.sync {
            guard let db = self.db else { return }
            
            executeRaw("BEGIN IMMEDIATE TRANSACTION;", db: db)
            
            let sql = """
            INSERT INTO photos (
                url_path, filename, date_taken, file_modified_date, file_size,
                is_video, video_path, exif_json, is_favorite
            ) VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?,
                COALESCE((SELECT is_favorite FROM photos WHERE url_path = ?), 0)
            )
            ON CONFLICT(url_path) DO UPDATE SET
                filename = excluded.filename,
                date_taken = excluded.date_taken,
                file_modified_date = excluded.file_modified_date,
                file_size = excluded.file_size,
                is_video = excluded.is_video,
                video_path = excluded.video_path,
                exif_json = excluded.exif_json;
            """
            
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                executeRaw("ROLLBACK;", db: db)
                return
            }
            defer { sqlite3_finalize(statement) }
            
            for item in items {
                let photo = item.photo
                let path = photo.url.path
                let filename = photo.filename
                let dateTaken = photo.date.timeIntervalSince1970
                let modDate = item.fileModifiedDate.timeIntervalSince1970
                let fileSize = Int64(item.fileSize)
                let isVideo = photo.isVideo ? 1 : 0
                let videoPath = photo.videoURL?.path
                
                let exifData = try? JSONSerialization.data(withJSONObject: photo.exifMetadata, options: [])
                let exifJson = exifData.flatMap { String(data: $0, encoding: .utf8) }
                
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (filename as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 3, dateTaken)
                sqlite3_bind_double(statement, 4, modDate)
                sqlite3_bind_int64(statement, 5, fileSize)
                sqlite3_bind_int(statement, 6, Int32(isVideo))
                
                if let videoPath = videoPath {
                    sqlite3_bind_text(statement, 7, (videoPath as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 7)
                }
                
                if let exifJson = exifJson {
                    sqlite3_bind_text(statement, 8, (exifJson as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 8)
                }
                
                // For subquery COALESCE:
                sqlite3_bind_text(statement, 9, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    print("SQLiteDatabase: error inserting \(path)")
                }
            }
            
            executeRaw("COMMIT;", db: db)
            
            // Clean up any standalone videos that are now paired with Live Photos
            let cleanupSql = """
            DELETE FROM photos 
            WHERE is_video = 1 
              AND LOWER(url_path) IN (SELECT LOWER(video_path) FROM photos WHERE video_path IS NOT NULL);
            """
            executeRaw(cleanupSql, db: db)
        }
    }
    
    /// Removes any standalone video entries that are actually paired with a Live Photo image.
    @discardableResult
    func cleanupDuplicateLivePhotoVideos() -> Int {
        queue.sync {
            guard let db = self.db else { return 0 }
            let sql = """
            DELETE FROM photos 
            WHERE is_video = 1 
              AND LOWER(url_path) IN (SELECT LOWER(video_path) FROM photos WHERE video_path IS NOT NULL);
            """
            executeRaw(sql, db: db)
            return Int(sqlite3_changes(db))
        }
    }
    
    /// Deletes specific photo paths from the database.
    func deletePhotos(paths: [String]) {
        guard !paths.isEmpty else { return }
        
        queue.sync {
            guard let db = self.db else { return }
            executeRaw("BEGIN IMMEDIATE TRANSACTION;", db: db)
            
            let sql = "DELETE FROM photos WHERE url_path = ?;"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                for path in paths {
                    sqlite3_reset(statement)
                    sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                    sqlite3_step(statement)
                }
                sqlite3_finalize(statement)
            }
            
            executeRaw("COMMIT;", db: db)
        }
    }
    
    // MARK: - Query Operations
    
    /// Fetches all photos matching any of the specified directory prefixes.
    /// If directories is empty, returns all photos.
    func fetchPhotos(forDirectories directories: [URL]) -> [Photo] {
        queue.sync {
            guard let db = self.db else { return [] }
            
            let sql: String
            let dirPaths = directories.map { $0.standardizedFileURL.path }
            let notPairedVideoCondition = "NOT (is_video = 1 AND LOWER(url_path) IN (SELECT LOWER(video_path) FROM photos WHERE video_path IS NOT NULL))"
            
            if dirPaths.isEmpty {
                sql = "SELECT url_path, filename, date_taken, is_video, video_path, exif_json FROM photos WHERE \(notPairedVideoCondition) ORDER BY date_taken DESC;"
            } else {
                let clauses = Array(repeating: "url_path LIKE ? || '%'", count: dirPaths.count).joined(separator: " OR ")
                sql = "SELECT url_path, filename, date_taken, is_video, video_path, exif_json FROM photos WHERE (\(clauses)) AND \(notPairedVideoCondition) ORDER BY date_taken DESC;"
            }
            
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                return []
            }
            defer { sqlite3_finalize(statement) }
            
            for (index, dirPath) in dirPaths.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), (dirPath as NSString).utf8String, -1, nil)
            }
            
            var photos: [Photo] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let photo = parsePhotoRow(from: statement) {
                    photos.append(photo)
                }
            }
            
            return photos
        }
    }
    
    /// Groups photos into PhotoMonths directly from query results.
    func fetchPhotoMonths(forDirectories directories: [URL]) -> [PhotoMonth] {
        let photos = fetchPhotos(forDirectories: directories)
        guard !photos.isEmpty else { return [] }
        
        struct MonthKey: Hashable {
            let year: Int
            let month: Int
        }
        
        let calendar = Calendar.current
        var orderMap: [MonthKey: [Photo]] = [:]
        var orderedKeys: [MonthKey] = []
        
        for photo in photos {
            let components = calendar.dateComponents([.year, .month], from: photo.date)
            let key = MonthKey(year: components.year ?? 2000, month: components.month ?? 1)
            
            if orderMap[key] == nil {
                orderMap[key] = [photo]
                orderedKeys.append(key)
            } else {
                orderMap[key]?.append(photo)
            }
        }
        
        return orderedKeys.map { key in
            PhotoMonth(year: key.year, month: key.month, photos: orderMap[key] ?? [])
        }
    }
    
    // MARK: - Favorites Management
    
    /// Fetches all favorite photo paths.
    func fetchFavoritePaths() -> Set<String> {
        queue.sync {
            guard let db = self.db else { return [] }
            let sql = "SELECT url_path FROM photos WHERE is_favorite = 1;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            
            var paths = Set<String>()
            while sqlite3_step(statement) == SQLITE_ROW {
                if let pathCStr = sqlite3_column_text(statement, 0) {
                    paths.insert(String(cString: pathCStr))
                }
            }
            return paths
        }
    }
    
    /// Toggles or sets favorite status for a given photo path.
    func setFavorite(urlPath: String, isFavorite: Bool) {
        queue.sync {
            guard let db = self.db else { return }
            let sql = "UPDATE photos SET is_favorite = ? WHERE url_path = ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            
            sqlite3_bind_int(statement, 1, isFavorite ? 1 : 0)
            sqlite3_bind_text(statement, 2, (urlPath as NSString).utf8String, -1, nil)
            sqlite3_step(statement)
        }
    }
    
    /// Sets favorites in bulk (used for initial migration from UserDefaults).
    func syncFavorites(_ favoritePaths: Set<String>) {
        guard !favoritePaths.isEmpty else { return }
        queue.sync {
            guard let db = self.db else { return }
            executeRaw("BEGIN IMMEDIATE TRANSACTION;", db: db)
            
            let sql = "UPDATE photos SET is_favorite = 1 WHERE url_path = ?;"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                for path in favoritePaths {
                    sqlite3_reset(statement)
                    sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                    sqlite3_step(statement)
                }
                sqlite3_finalize(statement)
            }
            
            executeRaw("COMMIT;", db: db)
        }
    }
    
    // MARK: - Row Parser
    
    private func parsePhotoRow(from statement: OpaquePointer?) -> Photo? {
        guard let statement = statement,
              let pathCStr = sqlite3_column_text(statement, 0) else { return nil }
        
        let path = String(cString: pathCStr)
        let url = URL(fileURLWithPath: path)
        let dateTimestamp = sqlite3_column_double(statement, 2)
        let date = Date(timeIntervalSince1970: dateTimestamp)
        let isVideo = sqlite3_column_int(statement, 3) != 0
        
        var videoURL: URL? = nil
        if let videoPathCStr = sqlite3_column_text(statement, 4) {
            let videoPath = String(cString: videoPathCStr)
            videoURL = URL(fileURLWithPath: videoPath)
        }
        
        var exifMetadata: [String: String] = [:]
        if let exifJsonCStr = sqlite3_column_text(statement, 5) {
            let jsonString = String(cString: exifJsonCStr)
            if let data = jsonString.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                exifMetadata = dict
            }
        }
        
        return Photo(
            url: url,
            date: date,
            exifMetadata: exifMetadata,
            videoURL: videoURL,
            isVideo: isVideo
        )
    }
}
