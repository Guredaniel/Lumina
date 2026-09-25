import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: PhotoViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    
    var body: some View {
        TabView {
            Form {
                Picker("Grid Columns:", selection: $appSettings.gridColumns) {
                    Text("Auto").tag(0)
                    Text("3 (Large)").tag(3)
                    Text("4 (Medium)").tag(4)
                    Text("6 (Small)").tag(6)
                    Text("8 (Tiny)").tag(8)
                }
                .pickerStyle(.menu)
                .frame(width: 250)
                
                Spacer().frame(height: 10)
                
                Toggle("Show Filenames", isOn: $appSettings.showFilenames)
                Toggle("Enable Live Photos", isOn: $appSettings.enableLivePhotos)

                Section("Automatic Trips") {
                    Toggle("Detect Trips Automatically", isOn: $appSettings.automaticTripDetection)

                    Stepper(value: $appSettings.tripMinimumPhotos, in: 2...50) {
                        Text("Minimum Photos: \(appSettings.tripMinimumPhotos)")
                    }

                    Stepper(value: $appSettings.tripLocationRadius, in: 5...500, step: 5) {
                        Text("Location Radius: \(Int(appSettings.tripLocationRadius)) km")
                    }

                    Stepper(value: $appSettings.tripMaximumTimeGap, in: 6...168, step: 6) {
                        Text("Maximum Time Gap: \(Int(appSettings.tripMaximumTimeGap)) hours")
                    }

                    if viewModel.hiddenTripCount > 0 {
                        Button("Show Hidden Trips") {
                            viewModel.restoreHiddenTrips()
                        }
                    }
                }
                
                if appSettings.enableLivePhotos {
                    Picker("Live Playback:", selection: $appSettings.livePhotoPlaybackMode) {
                        Text("Loop").tag("loop")
                        Text("Play Once").tag("once")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 250)
                }
            }
            .padding(40)
            .frame(width: AppConstants.UI.settingsWindowWidth, height: AppConstants.UI.settingsWindowHeight)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            
            VStack(spacing: 0) {
                if viewModel.selectedDirectories.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No Directories")
                            .font(.headline)
                        Text("Add a directory to scan for photos.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.selectedDirectories, id: \.self) { url in
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                Text(url.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button(action: {
                                    viewModel.removeDirectory(url)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.inset)
                }
                
                Divider()
                
                HStack {
                    Spacer()
                    Button(action: {
                        viewModel.addDirectory()
                    }) {
                        Label("Add Directory...", systemImage: "plus")
                    }
                }
                .padding()
            }
            .frame(width: 500, height: 300)
            .tabItem {
                Label("Directories", systemImage: "folder")
            }
            
        }
        .onChange(of: appSettings.automaticTripDetection) { _ in
            viewModel.refreshTripAlbums()
        }
        .onChange(of: appSettings.tripMinimumPhotos) { _ in
            viewModel.refreshTripAlbums()
        }
        .onChange(of: appSettings.tripLocationRadius) { _ in
            viewModel.refreshTripAlbums()
        }
        .onChange(of: appSettings.tripMaximumTimeGap) { _ in
            viewModel.refreshTripAlbums()
        }
    }
}