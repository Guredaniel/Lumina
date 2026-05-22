# Lumina - Native macOS Photo Browser

A native macOS app built with SwiftUI that displays photos organized by month with quick previews and metadata.

## Features

- 📁 Select any folder to scan for photos recursively
- 📅 Automatically organizes photos by month and year
- 🖼️ Efficient thumbnail generation with caching
- 👁️ Quick preview with full-resolution image display
- 📊 EXIF metadata extraction (date, camera, dimensions)
- 💨 Fast and responsive UI with background processing
- 🎨 Native macOS design with dark mode support

## System Requirements

- macOS 13.0 or later
- Xcode 15.3 or later (for building)
- Swift 5.0 or later

## Setup & Building

### Option 1: Build with Xcode (Recommended)

1. **Open the Project in Xcode:**
   ```bash
   open ~/PhotoViewer/PhotoViewer.xcodeproj
   ```

2. **Select the Target:**
   - Ensure "Lumina" is selected as the active scheme in the top toolbar

3. **Build:**
   - Press `Cmd + B` or go to `Product > Build`

4. **Run:**
   - Press `Cmd + R` or go to `Product > Run`

### Option 2: Build from Command Line

```bash
cd ~/PhotoViewer

# Build the app
xcodebuild -project PhotoViewer.xcodeproj -scheme Lumina -configuration Release

# Run the app
open ./build/Release/Lumina.app
```

### Option 3: Build with Swift Package Manager

```bash
cd ~/PhotoViewer

# Build
swift build -c release

# Run
./.build/release/Lumina
```

## Project Structure

```
PhotoViewer/
├── Sources/PhotoViewer/
│   ├── Models/
│   │   ├── Photo.swift              # Individual photo model with metadata
│   │   ├── PhotoMonth.swift         # Month grouping container
│   │   └── ThumbnailCache.swift     # Dual-level thumbnail caching
│   ├── Services/
│   │   ├── PhotoScanner.swift       # Directory scanning & EXIF extraction
│   │   └── ThumbnailService.swift   # Async thumbnail generation with QLThumbnailGenerator
│   ├── ViewModels/
│   │   └── PhotoViewModel.swift     # State management & coordination
│   ├── Views/
│   │   ├── ContentView.swift        # Main interface
│   │   ├── PhotoGridView.swift      # LazyVGrid for responsive layout
│   │   └── PreviewView.swift        # Full-size preview with metadata
│   └── PhotoViewerApp.swift         # App entry point
├── Info.plist                        # App configuration
├── Package.swift                     # Swift package manifest
└── PhotoViewer.xcodeproj/            # Xcode project file
    ├── project.pbxproj              # Project configuration
    └── project.xcworkspace/         # Workspace data
```

## Usage

1. **Launch the app** - either from Xcode or by running the built app
2. **Select a folder** - click "Select Folder" button and choose a directory
3. **Browse photos** - photos automatically organize by month
4. **View details** - click on a thumbnail to see full-size image and EXIF data
5. **Change folder** - click "Change Folder" to select a different directory

## Key Technologies

- **SwiftUI** - Modern declarative UI framework for macOS
- **ImageIO** - EXIF metadata extraction
- **QuickLookThumbnailing (QLThumbnailGenerator)** - High-performance thumbnail generation
- **NSCache** - In-memory thumbnail caching
- **FileManager** - Directory traversal and file operations
- **Combine/async-await** - Asynchronous operations

## Performance Optimizations

1. **Lazy Loading** - Thumbnails generated on-demand as user scrolls
2. **Dual-Level Caching** - In-memory cache + disk cache for fast reopens
3. **Background Processing** - Directory scanning and thumbnail generation on background threads
4. **Responsive Grid** - LazyVGrid automatically adjusts columns to window width
5. **Memory Management** - Cache purging when size limit exceeded

## Known Limitations

- Currently scans local directories only (no network locations or external drive monitoring)
- Recursive search can be slow on very large directory trees (100k+ files)
- Some rare image formats may fall back to NSImage thumbnail generation

## Future Enhancements

- Add search/filter by date range
- Implement slideshow mode
- Add image editing capabilities (rotate, crop)
- Support for video thumbnails
- Batch operations (move, delete, export)
- Customizable sorting and grouping options

## Troubleshooting

### "Permission Denied" Error
- Ensure the app has permission to access the selected folder
- Check System Preferences > Security & Privacy

### Thumbnails Not Loading
- First load generates thumbnails (may take time with many images)
- Restart the app to use cached thumbnails
- Check ~/Library/Caches/com.photoviewer/thumbnails/ for cache

### App Crashes When Selecting Large Folder
- This is typically due to memory constraints with 10,000+ images
- Try selecting a subfolder with fewer images
- Consider increasing available RAM

## Building for Distribution

To create a signed and notarized app for distribution:

```bash
# Build with release configuration
xcodebuild -project PhotoViewer.xcodeproj -scheme Lumina -configuration Release -derivedDataPath build

# Sign the app (requires Developer ID)
codesign --deep --force --verify --verbose --sign "Developer ID Application" ./build/Release/Lumina.app

# Create DMG for distribution
hdiutil create -volname Lumina -srcfolder ./build/Release/Lumina.app -ov -format UDZO Lumina.dmg
```

## Development Notes

### Adding Support for New Image Formats
- Update `supportedUTTypes` in `PhotoScanner.swift`
- Add type identifiers to the array

### Modifying Cache Behavior
- Adjust cache size limits in `ThumbnailCache.swift`:
  - `maxCacheSize` - Total disk cache size
  - `memoryCache.totalCostLimit` - In-memory cache size
  - `memoryCache.countLimit` - Max number of cached thumbnails

### Debugging EXIF Extraction
- Enable debug logging in `PhotoScanner.extractImageDate()`
- Check extracted metadata in Console.app

## License

Created with ❤️ for macOS users who organize their photo libraries effectively.

## Support

For issues or feature requests, please create a detailed report including:
- macOS version
- Xcode version
- Number of photos in tested directory
- Any error messages from Console.app
