//
//  RenditionDetailView.swift
//  Orbital
//

import SwiftUI

struct RenditionDetailView: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  let composer: ComposerEntry
  let rendition: PlaybackRendition

  @State private var bpm: Double = 30
  @State private var currentDocument: SongDocument?

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
        RenditionHeaderView(composer: composer)
      }

      if rendition.midi != nil {
      Section("Playback") {
        LabeledContent("BPM") {
          HStack {
            Slider(value: $bpm, in: 15...120, step: 5)
              .disabled(isPlaying)
            Text("\(Int(bpm))")
              .monospacedDigit()
              .frame(width: 36, alignment: .trailing)
          }
        }

        Button {
          handlePlayButton()
        } label: {
          if isLoading {
            ProgressView()
              .frame(maxWidth: .infinity)
          } else {
            Label(
              isPlaying ? "Playing…" : isPaused ? "Resume" : "Play",
              systemImage: isPlaying ? "pause.fill" : "play.fill"
            )
            .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.bordered)
        .tint(isPlaying ? .orange : .accentColor)
        .disabled(isLoading)
      }
      } // end if rendition.midi != nil

      Section("Details") {
        if let key = rendition.key {
          LabeledContent("Key", value: key)
        }
        if let ts = rendition.timeSignature {
          LabeledContent("Time", value: ts)
        }
        if let measures = rendition.nMeasures {
          LabeledContent("Measures", value: "\(measures)")
        }
        if let parts = rendition.nParts {
          LabeledContent("Parts", value: "\(parts)")
        }
        if let instruments = rendition.instrumentsGm, !instruments.isEmpty {
          LabeledContent("Instruments", value: instruments.joined(separator: ", "))
        }
        if let views = rendition.pdmx?.nViews {
          LabeledContent("MuseScore Views", value: "\(views)")
        }
        if let dur = rendition.pdmx?.durationSeconds {
          LabeledContent("Duration (original)", value: formatDuration(dur))
        }
      }

      if let urlString = rendition.appleClassicalSearchUrl, let url = URL(string: urlString) {
        Section {
          Link(destination: url) {
            Label("Search Apple Music Classical", systemImage: "magnifyingglass")
          }
        }
      }
    }
    .navigationTitle(rendition.title)
    .navigationBarTitleDisplayMode(.inline)
  }

  private func handlePlayButton() {
    guard !isLoading else { return }
    if isPlaying {
      library.pauseAll()
    } else if isPaused {
      library.resumeAll()
    } else {
      startPlayback()
    }
  }

  private func startPlayback() {
    guard let midiFile = rendition.midi else { return }
    let midiPath = "catalog_playback/\(composer.slug)/\(midiFile)"
    let tracks = [MidiTrackEntry(presetFilename: nil, numVoices: 4, modulators: nil)]
    let midiSpec = MidiTracksSyntax(filename: midiPath, loop: false, bpm: bpm, tracks: tracks)
    let pattern = PatternSyntax(name: rendition.title, midiTracks: midiSpec)
    // catalog_playback files live in the app bundle (not the iCloud documents directory),
    // so resourceBaseURL must be nil to force the bundle lookup path in midiFileURL.
    let doc = SongDocument(
      patternSyntax: pattern,
      name: rendition.title,
      subtitle: composer.name,
      engine: engine,
      resourceBaseURL: nil
    )
    currentDocument = doc
    library.play(document: doc)
  }

  private func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds)
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
  }
}

// MARK: - RenditionHeaderView

private struct RenditionHeaderView: View {
  let composer: ComposerEntry

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

#Preview {
  let composer = ComposerEntry(
    slug: "bach",
    qid: "Q1339",
    name: "Johann Sebastian Bach",
    birth: "1685-03-21",
    death: "1750-07-28",
    portraitUrl: nil,
    wikipediaUrl: nil,
    wikipediaExtract: "A prolific Baroque composer.",
    pageviewsYearly: 1_000_000,
    appleClassicalUrl: nil
  )
  let rendition = PlaybackRendition(
    title: "Sinfonia in E major BWV 792",
    midi: "midi/BWV_792_Sinfonia_VI.mid",
    musicxml: nil,
    wikidataId: "Q111804166",
    wikidataTitle: "15 Sinfonias",
    displayTitle: "15 Sinfonias",
    key: "E major",
    tempoBpm: 184,
    nMeasures: 41,
    nParts: 1,
    nNotes: 530,
    notesPerSecond: 8.9,
    appleClassicalSearchUrl: nil,
    pdmx: nil,
    instrumentsGm: ["Orchestral Harp"],
    timeSignature: "9/8"
  )
  NavigationStack {
    RenditionDetailView(composer: composer, rendition: rendition)
  }
  .environment(SpatialAudioEngine())
  .environment(SongLibrary())
}
