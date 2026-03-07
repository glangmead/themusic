//
//  ComposerDetailView.swift
//  Orbital
//

import SwiftUI

struct ComposerDetailView: View {
  @Environment(ClassicsCatalogLibrary.self) private var catalog
  let composer: ComposerEntry

  var body: some View {
    let workGroups = catalog.cachedWorkGroups(for: composer.slug)
    List {
      Section {
        ComposerHeaderView(composer: composer)
      }
      ForEach(workGroups) { group in
        Section(group.displayTitle) {
          ForEach(group.renditions) { rendition in
            NavigationLink {
              RenditionDetailView(composer: composer, rendition: rendition)
            } label: {
              RenditionRow(rendition: rendition)
            }
          }
        }
      }
    }
    .navigationTitle(composer.name)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await catalog.loadWorkGroupsIfNeeded(for: composer)
    }
  }
}

// MARK: - ComposerHeaderView

private struct ComposerHeaderView: View {
  let composer: ComposerEntry

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

// MARK: - RenditionRow

private struct RenditionRow: View {
  let rendition: PlaybackRendition

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(rendition.title)
        .lineLimit(2)
      HStack(spacing: 8) {
        if let key = rendition.key {
          Text(key)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let dur = rendition.pdmx?.durationSeconds {
          Text(formatDuration(dur))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let bpm = rendition.tempoBpm {
          Text("\(bpm) BPM")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds)
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
  }
}

#Preview {
  NavigationStack {
    ComposerDetailView(composer: ComposerEntry(
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
    ))
  }
  .environment(ClassicsCatalogLibrary())
  .environment(SpatialAudioEngine())
  .environment(SongLibrary())
  .environment(ResourceManager())
}
