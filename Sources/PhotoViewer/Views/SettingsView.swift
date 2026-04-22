import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: PhotoViewModel
    
    @AppStorage("gridColumns") private var gridColumns: Int = 4
    @AppStorage("showFilenames") private var showFilenames: Bool = false
    @AppStorage("enableLivePhotos") private var enableLivePhotos: Bool = true
    @AppStorage("livePhotoPlaybackMode") private var livePhotoPlaybackMode: String = "loop"
    
    var body: some View {
        TabView {
            Form {
                Picker("Grid Columns:", selection: $gridColumns) {
                    Text("Auto").tag(0)
                    Text("3 (Large)").tag(3)
                    Text("4 (Medium)").tag(4)
                    Text("6 (Small)").tag(6)
                    Text("8 (Tiny)").tag(8)
                }
                .pickerStyle(.menu)
                .frame(width: 250)
                
                Spacer().frame(height: 10)
                
                Toggle("Show Filenames", isOn: $showFilenames)
                Toggle("Enable Live Photos", isOn: $enableLivePhotos)
                
                if enableLivePhotos {
                    Picker("Live Playback:", selection: $livePhotoPlaybackMode) {
                        Text("Loop").tag("loop")
                        Text("Play Once").tag("once")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 250)
                }
            }
            .padding(40)
            .frame(width: 400, height: 210)
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
    }
}
