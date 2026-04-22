import SwiftUI

@main
struct PhotoViewerApp: App {
    @StateObject private var viewModel = PhotoViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 700)
        
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
