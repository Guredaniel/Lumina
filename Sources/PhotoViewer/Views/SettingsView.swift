import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: PhotoViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var showingRestoreTrips = false
    @State private var selectedHiddenTripIDs: Set<String> = []

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            tripSettings
                .tabItem {
                    Label("Trips", systemImage: "airplane")
                }
            directorySettings
                .tabItem {
                    Label("Directories", systemImage: "folder")
                }
        }
        .frame(minWidth: 560, minHeight: 460)
        .sheet(isPresented: $showingRestoreTrips) {
            restoreTripsSheet
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
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

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
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

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
    }
}