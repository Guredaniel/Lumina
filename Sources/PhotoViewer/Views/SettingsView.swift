import SwiftUI

// MARK: - Settings Tab Enum

private enum SettingsTab: String, CaseIterable {
    case general     = "general"
    case trips       = "trips"
    case directories = "directories"
    case storage     = "storage"
    case privacy     = "privacy"
}

// MARK: - Root View

struct SettingsView: View {
    @ObservedObject var viewModel: PhotoViewModel
    @ObservedObject private var appSettings = AppSettings.shared

    @SceneStorage("selectedSettingsTab") private var selectedTab: String = SettingsTab.general.rawValue

    // Dialog state
    @State private var showingRestoreTrips = false
    @State private var selectedHiddenTripIDs: Set<String> = []
    @State private var cacheSizeBytes: Int64 = 0
    @State private var showingClearCacheAlert = false
    @State private var showingResetDefaultsAlert = false
    @State private var showingClearLocationCacheAlert = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("General", systemImage: "gearshape", value: SettingsTab.general.rawValue) {
                generalSettings
            }

            Tab("Trips", systemImage: "airplane", value: SettingsTab.trips.rawValue) {
                tripSettings
            }

            Tab("Directories", systemImage: "folder", value: SettingsTab.directories.rawValue) {
                directorySettings
            }

            TabSection("System") {
                Tab("Storage", systemImage: "internaldrive", value: SettingsTab.storage.rawValue) {
                    storageSettings
                }

                Tab("Privacy", systemImage: "hand.raised", value: SettingsTab.privacy.rawValue) {
                    privacySettings
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(minWidth: 620, minHeight: 460)
        .sheet(isPresented: $showingRestoreTrips) {
            restoreTripsSheet
        }
        .onChange(of: appSettings.automaticTripDetection) { _ in viewModel.refreshTripAlbums() }
        .onChange(of: appSettings.tripMinimumPhotos)      { _ in viewModel.refreshTripAlbums() }
        .onChange(of: appSettings.tripLocationRadius)     { _ in viewModel.refreshTripAlbums() }
        .onChange(of: appSettings.tripMaximumTimeGap)     { _ in viewModel.refreshTripAlbums() }
        .onChange(of: appSettings.enableReverseGeocoding) { _ in viewModel.refreshTripAlbums() }
    }

    // MARK: - General

    private var generalSettings: some View {
        Form {
            Section("Appearance") {
                Picker("Grid size", selection: $appSettings.gridColumns) {
                    Text("Automatic").tag(0)
                    Text("Large").tag(3)
                    Text("Medium").tag(4)
                    Text("Small").tag(6)
                    Text("Compact").tag(8)
                }
                Toggle("Show filenames below photos", isOn: $appSettings.showFilenames)
            }

            Section("Live Photos") {
                Toggle("Enable Live Photos", isOn: $appSettings.enableLivePhotos)
                if appSettings.enableLivePhotos {
                    Picker("Playback", selection: $appSettings.livePhotoPlaybackMode) {
                        Text("Play once").tag("once")
                        Text("Loop").tag("loop")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    // MARK: - Trips

    private var tripSettings: some View {
        Form {
            Section("Automatic Albums") {
                Toggle("Detect trips automatically", isOn: $appSettings.automaticTripDetection)
            }

            Section("Detection") {
                Stepper(value: $appSettings.tripMinimumPhotos, in: 2...50) {
                    LabeledContent("Minimum photos", value: "\(appSettings.tripMinimumPhotos)")
                }
                .disabled(!appSettings.automaticTripDetection)

                LabeledContent("Location radius") {
                    HStack(spacing: 12) {
                        Slider(value: $appSettings.tripLocationRadius, in: 5...500, step: 5)
                            .frame(maxWidth: 220)
                        Text("\(Int(appSettings.tripLocationRadius)) km")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                .disabled(!appSettings.automaticTripDetection)

                LabeledContent("Maximum time between photos") {
                    HStack(spacing: 12) {
                        Slider(value: $appSettings.tripMaximumTimeGap, in: 6...168, step: 6)
                            .frame(maxWidth: 220)
                        Text("\(Int(appSettings.tripMaximumTimeGap)) hr")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                .disabled(!appSettings.automaticTripDetection)
            }

            Section("Hidden Albums") {
                if viewModel.hiddenTripCount > 0 {
                    LabeledContent("Hidden trips", value: "\(viewModel.hiddenTripCount)")
                    Button("Choose Trips to Restore…") {
                        selectedHiddenTripIDs = []
                        showingRestoreTrips = true
                    }
                } else {
                    Text("No hidden trips")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Trips")
    }

    // MARK: - Directories

    private var directorySettings: some View {
        VStack(spacing: 0) {
            Form {
                Section("Photo Library Folders") {
                    if viewModel.selectedDirectories.isEmpty {
                        Text("No folders added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.selectedDirectories, id: \.self) { url in
                            HStack(spacing: 12) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(url.lastPathComponent)
                                        .lineLimit(1)
                                    Text(url.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer(minLength: 8)

                                Button(role: .destructive) {
                                    viewModel.removeDirectory(url)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove folder")
                                .accessibilityLabel("Remove \(url.lastPathComponent)")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button {
                    viewModel.addDirectory()
                } label: {
                    Label("Add Folder…", systemImage: "plus")
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .navigationTitle("Directories")
    }

    // MARK: - Storage

    private var storageSettings: some View {
        Form {
            Section("Thumbnail Cache") {
                LabeledContent("Location") {
                    Text(AppSettings.shared.thumbnailCachePath.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                LabeledContent("Disk Usage") {
                    Text(ByteCountFormatter.string(fromByteCount: cacheSizeBytes, countStyle: .file))
                        .monospacedDigit()
                }

                Button("Clear Thumbnail Cache…") {
                    showingClearCacheAlert = true
                }
            }

            Section("Preferences") {
                Button("Reset All Settings to Defaults…") {
                    showingResetDefaultsAlert = true
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Storage")
        .onAppear {
            cacheSizeBytes = ThumbnailCacheManager.shared.diskCacheSize()
        }
        .confirmationDialog(
            "Clear Thumbnail Cache?",
            isPresented: $showingClearCacheAlert,
            titleVisibility: .visible
        ) {
            Button("Clear Cache", role: .destructive) {
                ThumbnailCacheManager.shared.clear()
                cacheSizeBytes = ThumbnailCacheManager.shared.diskCacheSize()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All cached thumbnails on disk will be removed and re-rendered as needed.")
        }
        .confirmationDialog(
            "Reset Settings?",
            isPresented: $showingResetDefaultsAlert,
            titleVisibility: .visible
        ) {
            Button("Reset to Defaults", role: .destructive) {
                appSettings.resetToDefaults()
                viewModel.refreshTripAlbums()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All settings will be restored to their factory defaults.")
        }
    }

    // MARK: - Privacy

    private var privacySettings: some View {
        Form {
            Section {
                Toggle("Enable location lookup for photos", isOn: $appSettings.enableReverseGeocoding)
                Text("When enabled, the app contacts Apple\u{2019}s servers to convert GPS coordinates in your photos to place names. Disable this to prevent any network requests for location data. Previously resolved names remain visible from the local cache.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Reverse Geocoding")
            }

            Section("Location Cache") {
                Button("Clear Cached Location Names\u{2026}") {
                    showingClearLocationCacheAlert = true
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Privacy")
        .confirmationDialog(
            "Clear Location Cache?",
            isPresented: $showingClearLocationCacheAlert,
            titleVisibility: .visible
        ) {
            Button("Clear Location Cache", role: .destructive) {
                SQLiteDatabase.shared.clearLocationCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All locally cached place names will be removed. They will be re-fetched from Apple\u{2019}s servers the next time a geotagged photo is viewed, if location lookup is enabled.")
        }
    }

    // MARK: - Restore Trips Sheet

    private var restoreTripsSheet: some View {
        NavigationStack {
            List(viewModel.hiddenTripAlbums) { trip in
                Toggle(isOn: selectionBinding(for: trip.id)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(trip.title)
                        Text(trip.dateRange)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .navigationTitle("Restore Hidden Trips")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingRestoreTrips = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore Selected") {
                        viewModel.restoreHiddenTrips(withIDs: selectedHiddenTripIDs)
                        showingRestoreTrips = false
                    }
                    .disabled(selectedHiddenTripIDs.isEmpty)
                }
            }
            .frame(minWidth: 420, minHeight: 320)
        }
    }

    private func selectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedHiddenTripIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedHiddenTripIDs.insert(id)
                } else {
                    selectedHiddenTripIDs.remove(id)
                }
            }
        )
    }
}