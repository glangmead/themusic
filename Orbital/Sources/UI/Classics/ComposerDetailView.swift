//
//  ComposerDetailView.swift
//  Orbital
//

import SwiftUI

struct ComposerDetailView: View {
  @Environment(ClassicsCatalogLibrary.self) private var catalog
  @Environment(MIDIDownloadLedger.self) private var ledger
  let composer: CatalogComposer
  @State private var searchText = ""

  var body: some View {
    let tokens = ClassicsSearch.tokens(for: searchText)
    let works = catalog.cachedWorks(for: composer.slug)
      .filter { ClassicsSearch.matches(composer: composer, work: $0, tokens: tokens) }
    let worksWithMidi = works.filter { !($0.sources?.isEmpty ?? true) }
    let worksWithoutMidi = works.filter { $0.sources?.isEmpty ?? true }

    List {
      Section {
        ComposerHeaderView(composer: composer)
      }

      if !worksWithMidi.isEmpty {
        Section("Works with MIDI (\(worksWithMidi.count))") {
          ForEach(worksWithMidi) { work in
            NavigationLink {
              WorkDetailView(composer: composer, work: work)
            } label: {
              WorkRow(work: work)
            }
          }
        }
      }

      if !worksWithoutMidi.isEmpty {
        Section("Other Works (\(worksWithoutMidi.count))") {
          ForEach(worksWithoutMidi) { work in
            VStack(alignment: .leading, spacing: 2) {
              Text(work.title)
                .lineLimit(2)
              if let label = work.catalogLabel {
                Text(label)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
    .navigationTitle(composer.name)
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: "Search works")
    .overlay {
      if !searchText.isEmpty && works.isEmpty {
        ContentUnavailableView.search(text: searchText)
      }
    }
    .task {
      await catalog.loadWorksIfNeeded(for: composer)
    }
  }
}

// MARK: - ComposerHeaderView

struct ComposerHeaderView: View {
  let composer: CatalogComposer

  var body: some View {
    VStack(spacing: 12) {
      if let urlString = composer.portraitUrl, let url = URL(string: urlString) {
        FaceAwarePortraitView(url: url, frameHeight: 250)
          .frame(maxWidth: .infinity)
      }
      if let urlString = composer.appleClassicalUrl, let url = URL(string: urlString) {
        Link(destination: url) {
          Label("Apple Music Classical", systemImage: "music.note")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      }
      if let extract = composer.wikipediaExtract {
        Text(extract)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .listRowInsets(EdgeInsets())
    .padding()
  }
}

// MARK: - WorkRow

private struct WorkRow: View {
  @Environment(MIDIDownloadLedger.self) private var ledger
  let work: CatalogWork

  private var downloadedCount: Int {
    work.allMidiUrls.filter { ledger.isDownloaded($0) }.count
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(work.title)
        .lineLimit(2)
      HStack(spacing: 8) {
        if let label = work.catalogLabel {
          Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let key = work.key {
          Text(key)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        let total = work.allMidiUrls.count
        if total > 0 {
          Text("\(total) MIDI")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if downloadedCount > 0 {
          Label("\(downloadedCount)", systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.green)
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    ComposerDetailView(composer: CatalogComposer(
      slug: "bach",
      qid: "Q1339",
      name: "Johann Sebastian Bach",
      birth: "1685-03-21",
      death: "1750-07-28",
      portraitUrl: nil,
      wikipediaUrl: nil,
      wikipediaExtract: "A prolific Baroque composer.",
      appleClassicalUrl: nil,
      era: "Baroque",
      nationality: "DEU"
    ))
  }
  .environment(ClassicsCatalogLibrary())
  .environment(SpatialAudioEngine())
  .environment(SongLibrary())
  .environment(ResourceManager())
  .environment(MIDIDownloadManager(ledger: MIDIDownloadLedger(baseDirectory: .temporaryDirectory)))
  .environment(MIDIDownloadLedger(baseDirectory: .temporaryDirectory))
}
