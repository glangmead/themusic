//
//  AppView.swift
//  Orbital
//
//  Created by Greg Langmead on 12/1/25.
//

import SwiftUI

struct AppView: View {
  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    if sizeClass == .compact {
      CompactAppLayout()
    } else {
      RegularAppLayout()
    }
  }
}

// MARK: - Compact (iPhone) Layout

private struct CompactAppLayout: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  @State private var isShowingVisualizer = false
  @State private var createDocument: SongDocument?

  var body: some View {
    TabView {
      Tab("Songs", systemImage: "music.note.list") {
        OrbitalView()
      }
      Tab("Classics", systemImage: "building.columns") {
        ClassicsBrowserView()
      }
      Tab("Create", systemImage: "wand.and.stars") {
        NavigationStack {
          if let doc = createDocument {
            GeneratorFormView(params: doc.generatorPattern ?? GeneratorSyntax())
              .environment(doc)
          } else {
            ProgressView()
          }
        }
      }
      Tab("Sound library", systemImage: "pianokeys") {
        PresetLibraryView()
      }
      Tab("Sound design", systemImage: "slider.horizontal.3") {
        PadTemplateFormView()
      }
      Tab("Sound design 2", systemImage: "waveform.path.ecg") {
        PADSynthFormView()
      }
    }
    .task {
      if createDocument == nil {
        createDocument = SongDocument(generatorPattern: GeneratorSyntax(), engine: engine)
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewBottomAccessory(isEnabled: library.anySongPlaying || createDocument?.isPlaying == true || createDocument?.isLoading == true) {
      PlaybackAccessoryView(
        state: library.currentPlaybackState ?? createDocument,
        isShowingVisualizer: $isShowingVisualizer
      )
    }
    .overlay {
      VisualizerView(engine: engine, isPresented: $isShowingVisualizer)
        .ignoresSafeArea()
        .opacity(isShowingVisualizer ? 1 : 0)
        .allowsHitTesting(isShowingVisualizer)
        .animation(.easeInOut(duration: 0.4), value: isShowingVisualizer)
    }
  }
}

// MARK: - Regular (iPad) Layout

enum SidebarCategory: String, CaseIterable, Identifiable {
  case songs = "Songs"
  case classics = "Classics"
  case create = "Create"
  case soundLibrary = "Sound Library"
  case soundDesign = "Sound Design"
  case soundDesign2 = "Sound Design 2"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .songs: "music.note.list"
    case .classics: "building.columns"
    case .create: "wand.and.stars"
    case .soundLibrary: "pianokeys"
    case .soundDesign: "slider.horizontal.3"
    case .soundDesign2: "waveform.path.ecg"
    }
  }
}

private struct RegularAppLayout: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  @Environment(ResourceManager.self) private var resourceManager
  @Environment(ClassicsCatalogLibrary.self) private var catalog
  @State private var selectedCategory: SidebarCategory? = .songs
  @State private var isShowingVisualizer = false
  @State private var createDocument: SongDocument?
  @State private var presets: [PresetRef] = []

  var body: some View {
    NavigationSplitView {
      List(SidebarCategory.allCases, selection: $selectedCategory) { category in
        Label(category.rawValue, systemImage: category.systemImage)
          .tag(category)
          .accessibilityIdentifier("sidebar-\(category.rawValue)")
          .accessibilityLabel(category.rawValue)
          .accessibilityAddTraits(.isButton)
      }
      .navigationTitle("Orbital")
    } detail: {
      detailForCategory
    }
    .task {
      if createDocument == nil {
        createDocument = SongDocument(generatorPattern: GeneratorSyntax(), engine: engine)
      }
    }
    .task {
      await catalog.preloadAllWorkGroups()
    }
    .task {
      loadPresets()
    }
    .safeAreaInset(edge: .bottom) {
      if library.anySongPlaying || createDocument?.isPlaying == true || createDocument?.isLoading == true {
        PlaybackAccessoryView(
          state: library.currentPlaybackState ?? createDocument,
          isShowingVisualizer: $isShowingVisualizer
        )
        .padding()
        .background(.ultraThinMaterial)
      }
    }
    .overlay {
      VisualizerView(engine: engine, isPresented: $isShowingVisualizer)
        .ignoresSafeArea()
        .opacity(isShowingVisualizer ? 1 : 0)
        .allowsHitTesting(isShowingVisualizer)
        .animation(.easeInOut(duration: 0.4), value: isShowingVisualizer)
    }
  }

  @ViewBuilder
  private var detailForCategory: some View {
    switch selectedCategory {
    case .songs:
      iPadSongsView
    case .classics:
      iPadClassicsView
    case .soundLibrary:
      iPadSoundLibraryView
    case .create:
      NavigationStack {
        if let doc = createDocument {
          GeneratorFormView(params: doc.generatorPattern ?? GeneratorSyntax())
            .environment(doc)
        } else {
          ProgressView()
        }
      }
    case .soundDesign:
      PadTemplateFormView()
    case .soundDesign2:
      PADSynthFormView()
    case nil:
      ContentUnavailableView("Select a Category", systemImage: "sidebar.left", description: Text("Choose a category from the sidebar."))
    }
  }

  // MARK: - Songs

  @ViewBuilder
  private var iPadSongsView: some View {
    @Bindable var library = library
    NavigationStack {
      Group {
        if resourceManager.isReady {
          SongListContent()
        } else {
          ProgressView("Loading songs...")
        }
      }
      .navigationTitle("Songs")
    }
  }

  // MARK: - Classics

  @ViewBuilder
  private var iPadClassicsView: some View {
    NavigationStack {
      iPadComposerList
    }
  }

  @ViewBuilder
  private var iPadComposerList: some View {
    @Bindable var catalog = catalog
    List(catalog.sortedComposers) { composer in
      NavigationLink(value: composer.id) {
        ComposerRow(composer: composer)
      }
    }
    .navigationTitle("Composers")
    .navigationDestination(for: CatalogComposer.ID.self) { composerID in
      if let composer = catalog.sortedComposers.first(where: { $0.id == composerID }) {
        ComposerDetailView(composer: composer)
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Picker("Sort by", selection: $catalog.sortOrder) {
            ForEach(ClassicsCatalogLibrary.SortOrder.allCases) { order in
              Text(order.rawValue).tag(order)
            }
          }
          Divider()
          Toggle("Ascending", isOn: $catalog.sortAscending)
        } label: {
          Label("Sort", systemImage: "arrow.up.arrow.down")
        }
      }
    }
  }

  // MARK: - Sound Library

  @ViewBuilder
  private var iPadSoundLibraryView: some View {
    NavigationStack {
      List {
        Section {
          NavigationLink(value: "__wavetable_browser__") {
            Label("Wavetable Browser", systemImage: "waveform")
          }
        }
        ForEach(presets) { preset in
          NavigationLink(value: preset.fileName) {
            Text(preset.spec.name)
          }
        }
      }
      .navigationTitle("Sounds")
      .navigationDestination(for: String.self) { presetID in
        if presetID == "__wavetable_browser__" {
          WavetableBrowserView()
        } else if let preset = presets.first(where: { $0.fileName == presetID }) {
          PresetFormView(presetSpec: preset.spec)
            .navigationTitle(preset.spec.name)
        }
      }
    }
  }

  private func loadPresets() {
    guard let base = resourceManager.resourceBaseURL else { return }
    let presetsDir = base.appendingPathComponent("presets")
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: presetsDir,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }) ?? []
    presets = urls.compactMap { url -> PresetRef? in
      let fileName = url.lastPathComponent
      guard let data = try? Data(contentsOf: url),
            let spec = try? JSONDecoder().decode(PresetSyntax.self, from: data)
      else { return nil }
      return PresetRef(fileName: fileName, spec: spec)
    }.sorted { $0.spec.name.localizedCaseInsensitiveCompare($1.spec.name) == .orderedAscending }
  }
}

/// iPad song list with swipe actions, shown inside the Songs category detail.
private struct SongListContent: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  @Environment(ResourceManager.self) private var resourceManager
  @State private var songToDelete: SongRef?
  @State private var isShowingDeleteConfirmation = false

  var body: some View {
    List {
      ForEach(library.songs) { song in
        NavigationLink(value: song.id) {
          SongCell(song: song)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
          Button(role: .destructive) {
            songToDelete = song
          } label: {
            Label("Delete", systemImage: "trash")
          }
          .tint(.red)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
          Button {
            library.duplicateSong(song, resourceBaseURL: resourceManager.resourceBaseURL)
          } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
          }
          .tint(.blue)
        }
      }
    }
    .confirmationDialog(
      "Delete \(songToDelete?.name ?? "")?",
      isPresented: $isShowingDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let song = songToDelete {
          library.deleteSong(song)
        }
      }
    } message: {
      Text("This will permanently delete the pattern from iCloud. This cannot be undone.")
    }
    .onChange(of: songToDelete) {
      isShowingDeleteConfirmation = songToDelete != nil
    }
    .navigationDestination(for: SongRef.ID.self) { songID in
      if let song = library.songs.first(where: { $0.id == songID }) {
        let state = library.playbackState(for: song, engine: engine, resourceBaseURL: resourceManager.resourceBaseURL)
        SongSettingsView(song: song)
          .environment(state)
      }
    }
  }
}

// MARK: - Playback Accessory

struct PlaybackAccessoryView: View {
  @Environment(SongLibrary.self) private var library
  @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  let state: SongDocument?
  @Binding var isShowingVisualizer: Bool
  @State private var isShowingEventLog = false

  var body: some View {
    HStack {
      if placement != .inline {
        if library.isLoading {
          ProgressView()
        }

        VStack(alignment: .leading, spacing: 2) {
          if let name = library.currentSongName {
            Text(name)
              .lineLimit(1)
          }
          // Show subtitle (e.g. composer name from Classics) first; fall back to chord label.
          let secondaryText = state?.song.subtitle ?? state?.currentChordLabel
          if let secondary = secondaryText {
            Text(secondary)
              .font(.caption.italic())
              .lineLimit(1)
              .transition(.opacity)
          }
        }
        .animation(.easeInOut(duration: 0.2), value: state?.song.subtitle ?? state?.currentChordLabel)

        Spacer()
      }

      if placement == .inline {
        AccessoryButtons(isShowingVisualizer: $isShowingVisualizer)
          .buttonStyle(.glass)
      } else {
        AccessoryButtons(isShowingVisualizer: $isShowingVisualizer)
      }
    }
    .padding(.horizontal)
    .contentShape(Rectangle())
    .onTapGesture {
      isShowingEventLog = true
    }
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel("Show Event Log")
    .sheet(isPresented: $isShowingEventLog) {
      if let state {
        EventLogSheet(state: state)
      }
    }
  }
}

private struct AccessoryButtons: View {
  @Environment(SongLibrary.self) private var library
  @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  @Binding var isShowingVisualizer: Bool

  var body: some View {
    HStack(spacing: placement == .inline ? 12 : 20) {
      if !library.isLoading {
        Button(library.allPaused ? "Play" : "Pause", systemImage: library.allPaused ? "play.fill" : "pause.fill") {
          if library.allPaused {
            library.resumeAll()
          } else {
            library.pauseAll()
          }
        }

        Button("Stop", systemImage: "stop.fill", action: library.stopAll)
      }

      Button("Visualizer", systemImage: "sparkles.tv") {
        withAnimation(.easeInOut(duration: 0.4)) {
          isShowingVisualizer = true
        }
      }
    }
  }
}

/// Full event log presented as a sheet with a grab bar.
private struct EventLogSheet: View {
  let state: SongDocument
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      EventLogView(eventLog: state.eventLog)
        .navigationTitle("Event Log")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
    .presentationDragIndicator(.visible)
  }
}

#Preview {
  let ledger = MIDIDownloadLedger(baseDirectory: .temporaryDirectory)
  AppView()
    .environment(SpatialAudioEngine())
    .environment(SongLibrary())
    .environment(ResourceManager())
    .environment(ClassicsCatalogLibrary())
    .environment(ledger)
    .environment(MIDIDownloadManager(ledger: ledger))
}
