import SwiftUI

@main
struct PhotoViewerApp: App {
    // Use StateObject to own the lifecycle of the shared ViewModel
    @StateObject private var viewModel = PhotoViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .commands {
            // Add custom commands to the macOS System Menu Bar
            
            // 1. File Menu: Remove "New Window" and add custom actions
            // By using 'replacing', we eliminate the default "New Window" (Cmd+N) entry.
            CommandGroup(replacing: .newItem) {
                Button("Add Folder...") {
                    viewModel.addDirectory()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Button("Clear Library") {
                    viewModel.clearPhotos()
                }
            }
            
            // 2. View Menu: Refresh Library
            CommandGroup(after: .toolbar) {
                Button("Refresh Library") {
                    viewModel.scanAllDirectories(showLoading: false)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            
            // 3. View Menu: Standard macOS controls
            SidebarCommands()
            ToolbarCommands()
        }
        
        // 3. App Menu: Settings
        // Creating a Settings scene automatically adds "Settings..." to the App Menu
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}