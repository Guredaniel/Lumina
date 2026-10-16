import SwiftUI
import AppKit

@main
struct PhotoViewerApp: App {
    // Use StateObject to own the lifecycle of the shared ViewModel
    @StateObject private var viewModel = PhotoViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .commands {
            // MARK: - File Menu
            CommandGroup(replacing: .newItem) {
                Button("Add Folder...") {
                    viewModel.addDirectory()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button("Clear Library") {
                    viewModel.clearPhotos()
                }
            }
            
            // MARK: - Edit Menu
            CommandGroup(after: .pasteboard) {
                Divider()
                
                Button(viewModel.selectedPhoto.map { viewModel.isFavorite(photo: $0) ? "Remove from Favorites" : "Add to Favorites" } ?? "Add to Favorites") {
                    if let photo = viewModel.selectedPhoto {
                        viewModel.toggleFavorite(photo: photo)
                    }
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(viewModel.selectedPhoto == nil)
                
                Button("Delete") {
                    if let photo = viewModel.selectedPhoto {
                        viewModel.deletePhoto(photo)
                    }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(viewModel.selectedPhoto == nil)
            }
            
            // MARK: - View Menu
            CommandGroup(after: .toolbar) {
                Button("Refresh Library") {
                    viewModel.scanAllDirectories(showLoading: false)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            
            SidebarCommands()
            ToolbarCommands()
            
            // MARK: - Window Menu
            CommandGroup(replacing: .windowList) {
                Button("Minimize") {
                    if let window = NSApplication.shared.keyWindow {
                        window.miniaturize(nil)
                    }
                }
                .keyboardShortcut("m", modifiers: .command)
                
                Button("Zoom") {
                    if let window = NSApplication.shared.keyWindow {
                        window.zoom(nil)
                    }
                }
            }
        }
        
        // 3. App Menu: Settings
        // Creating a Settings scene automatically adds "Settings..." to the App Menu
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}