//
//  WorkDetailView.swift
//  Orbital
//
//  Detail view for a catalog work. Shows metadata, MIDI download buttons,
//  and playback controls for downloaded files.
//

import SwiftUI

struct WorkDetailView: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  @Environment(MIDIDownloadManager.self) private var downloadManager
  @Environment(MIDIDownloadLedger.self) private var ledger
  let composer: CatalogComposer
  let work: CatalogWork

  private static let minBpm: CoreFloat = 0.1
  private static let maxBpm: CoreFloat = 240.0
  @State private var bpm: CoreFloat = 15
  @State private var currentDocument: SongDocument?
  @State private var webViewItem: IdentifiableURL?
  @State private var downloadError: String?

  private var isCurrentlyActive: Bool {
    guard let doc = currentDocument else { return false }
    return library.currentPlaybackState === doc
  }
  private var isLoading: Bool { isCurrentlyActive && currentDocument?.isLoading == true }
  private var isPlaying: Bool { isCurrentlyActive && currentDocument?.isPlaying == true }
  private var isPaused: Bool { isCurrentlyActive && currentDocument?.isPaused == true }

  var body: some View {
    List {
      Section {
        WorkHeaderView(composer: composer)
      }

      // Metadata
      Section("Details") {
        if let label = work.catalogLabel {
          LabeledContent("Catalog", value: label)
        }
        if let key = work.key {
          LabeledContent("Key", value: key)
        }
        if let instruments = work.instruments, !instruments.isEmpty {
          LabeledContent("Instruments", value: instruments.joined(separator: ", "))
        }
        if let year = work.yearComposed {
          LabeledContent("Composed", value: "\(year)")
        }
      }

      // MIDI sources
      if let sources = work.sources, !sources.isEmpty {
        Section("MIDI Sources") {
          ForEach(sources) { source in
            SourceSection(source: source)
          }
        }
      }

      // Playback controls for any downloaded file
      let downloadedUrls = work.allMidiUrls.filter { ledger.isDownloaded($0) }
      if !downloadedUrls.isEmpty {
        Section("Playback") {
          SliderWithField(
            value: $bpm,
            label: "BPM",
            range: Self.minBpm...Self.maxBpm,
            logarithmic: true
          )
          .disabled(isPlaying)

          // Play button for the first downloaded file
          if let firstUrl = downloadedUrls.first {
            Button {
              handlePlayButton(sourceUrl: firstUrl)
            } label: {
              if isLoading {
                ProgressView()
                  .frame(maxWidth: .infinity)
              } else {
                Label(
                  isPlaying ? "Playing\u{2026}" : isPaused ? "Resume" : "Play",
                  systemImage: isPlaying ? "pause.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
              }
            }
            .buttonStyle(.bordered)
            .tint(isPlaying ? .orange : .accentColor)
            .disabled(isLoading)
          }
        }
      }

      // Error display
      if let downloadError {
        Section {
          Label(downloadError, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
        }
      }
    }
    .navigationTitle(work.title)
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $webViewItem) { item in
      NavigationStack {
        MIDIWebView(
          url: item.url,
          composerSlug: composer.slug,
          ledger: ledger,
          onDownloadComplete: { _ in
            webViewItem = nil
          }
        )
        .navigationTitle("Download")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { webViewItem = nil }
          }
        }
      }
    }
  }

  // MARK: - Source Section

  @ViewBuilder
  private func SourceSection(source: MIDISource) -> some View {
    ForEach(source.midiUrls, id: \.self) { urlString in
      let isDownloaded = ledger.isDownloaded(urlString)
      let isDownloading = downloadManager.activeDownloads.contains(urlString)
      let filename = MIDIDownloadManager.localFilename(
        from: urlString, existingIn: .temporaryDirectory
      )

      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(filename)
            .font(.callout)
            .lineLimit(1)
          Text(source.origin)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        Spacer()

        if isDownloaded {
          // Play button for this specific file
          Button("Play", systemImage: "play.circle.fill") {
            handlePlayButton(sourceUrl: urlString)
          }
          .labelStyle(.iconOnly)
          .font(.title2)
          .foregroundStyle(.green)
          .buttonStyle(.plain)
        } else if isDownloading {
          ProgressView()
        } else if source.requiresWebView {
          // WebView download (kdf)
          Button("Open in browser", systemImage: "arrow.up.right.square") {
            if let url = URL(string: urlString) {
              webViewItem = IdentifiableURL(url: url)
            }
          }
          .labelStyle(.iconOnly)
          .font(.title3)
          .buttonStyle(.plain)
        } else {
          // Direct download
          Button("Download", systemImage: "arrow.down.circle") {
            Task {
              await directDownload(urlString: urlString)
            }
          }
          .labelStyle(.iconOnly)
          .font(.title3)
          .buttonStyle(.plain)
        }
      }
    }
  }

  // MARK: - Actions

  private func directDownload(urlString: String) async {
    downloadError = nil
    do {
      try await downloadManager.download(url: urlString, composerSlug: composer.slug)
    } catch {
      downloadError = error.localizedDescription
    }
  }

  private func handlePlayButton(sourceUrl: String) {
    guard !isLoading else { return }
    if isPlaying {
      library.pauseAll()
    } else if isPaused {
      library.resumeAll()
    } else {
      startPlayback(sourceUrl: sourceUrl)
    }
  }

  private func startPlayback(sourceUrl: String) {
    guard let localURL = ledger.localURL(for: sourceUrl) else { return }
    let relativePath = localURL.lastPathComponent
    let composerPath = "\(composer.slug)/\(relativePath)"
    let tracks = [MidiTrackEntry(presetFilename: nil, numVoices: 4, modulators: nil)]
    let midiSpec = MidiTracksSyntax(filename: composerPath, loop: false, bpm: bpm, tracks: tracks)
    let pattern = PatternSyntax(midiTracks: midiSpec)
    let doc = SongDocument(
      patternSyntax: pattern,
      displayName: work.title,
      subtitle: composer.name,
      engine: engine,
      resourceBaseURL: ledger.baseDirectory
    )
    currentDocument = doc
    library.play(document: doc)
  }
}

// MARK: - WorkHeaderView

private struct WorkHeaderView: View {
  let composer: CatalogComposer

  var body: some View {
    VStack(spacing: 8) {
      if let urlString = composer.portraitUrl, let url = URL(string: urlString) {
        FaceAwarePortraitView(url: url, frameHeight: 200)
          .frame(maxWidth: .infinity)
      }
      Text(composer.name)
        .font(.headline)
      if !composer.lifespan.isEmpty {
        Text(composer.lifespan)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if let extract = composer.wikipediaExtract {
        Text(extract)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(4)
      }
    }
    .listRowInsets(EdgeInsets())
    .padding()
  }
}

// MARK: - Identifiable wrapper for URL sheet presentation

struct IdentifiableURL: Identifiable {
  let url: URL
  var id: String { url.absoluteString }
}
