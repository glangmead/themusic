//
//  SongTakesSection.swift
//  Orbital
//
//  Per-song takes UI: shows the current seed (when playing), a paste field
//  to replay a specific seed, a favorites list, and a recent-history list.
//  Only rendered when the SongDocument reports `hasRandomness == true`.
//

import SwiftUI

struct SongTakesSection: View {
  let songDocument: SongDocument
  @Environment(TakesStore.self) private var store

  @State private var seedInput: String = ""
  @State private var seedInputError: Bool = false
  @State private var showAllRecent: Bool = false

  private static let recentVisibleCount = 20

  var body: some View {
    if songDocument.hasRandomness {
      Section("Takes") {
        if let seedString = songDocument.currentSeedString, songDocument.isPlaying {
          currentTakeRow(seedString)
        }
        pasteSeedRow

        let entries = store.entries(for: songDocument.song.id)
        let favorites = entries.filter(\.favorite)
        let recents = entries.filter { !$0.favorite }

        if !favorites.isEmpty {
          favoritesList(favorites)
        }
        if !recents.isEmpty {
          recentList(recents)
        }
      }
    }
  }

  private func currentTakeRow(_ seedString: String) -> some View {
    HStack {
      Text("Now playing")
        .foregroundStyle(.secondary)
      Spacer()
      Button {
        UIPasteboard.general.string = seedString
      } label: {
        Text(seedString)
          .font(.body.monospaced())
      }
      .buttonStyle(.bordered)
      .accessibilityLabel("Copy seed " + spelled(seedString))
      .accessibilityHint("Double-tap to copy seed to clipboard")
    }
  }

  private var pasteSeedRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Replay a specific seed")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        TextField("ABCDE12345", text: $seedInput)
          .font(.body.monospaced())
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
          .onChange(of: seedInput) { _, newValue in
            seedInputError = !newValue.isEmpty && SeedCodec.decode(newValue) == nil
          }
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .stroke(seedInputError ? Color.red : Color.clear, lineWidth: 1)
          )
        Button("Play") {
          guard SeedCodec.decode(seedInput) != nil else {
            seedInputError = true
            return
          }
          songDocument.setPendingSeed(seedInput)
          songDocument.restart()
          seedInput = ""
          seedInputError = false
        }
        .disabled(seedInput.isEmpty || seedInputError)
      }
    }
  }

  private func favoritesList(_ entries: [TakeEntry]) -> some View {
    Group {
      Text("Favorites")
        .font(.caption)
        .foregroundStyle(.secondary)
      ForEach(entries) { entry in
        takeRow(entry)
      }
    }
  }

  private func recentList(_ entries: [TakeEntry]) -> some View {
    let visible = showAllRecent ? entries : Array(entries.prefix(Self.recentVisibleCount))
    return Group {
      Text("Recent")
        .font(.caption)
        .foregroundStyle(.secondary)
      ForEach(visible) { entry in
        takeRow(entry)
      }
      if entries.count > Self.recentVisibleCount {
        Button {
          showAllRecent.toggle()
        } label: {
          Text(showAllRecent ? "Show fewer" : "Show all (\(entries.count))")
            .font(.caption)
        }
      }
    }
  }

  private func takeRow(_ entry: TakeEntry) -> some View {
    let isVersionMismatch = entry.appVersion != nil && entry.appVersion != TakeEntry.currentAppVersion
    return HStack {
      if entry.favorite {
        Image(systemName: "star.fill")
          .foregroundStyle(.yellow)
      }
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(entry.seed)
            .font(.body.monospaced())
            .accessibilityLabel("Seed " + spelled(entry.seed))
          if isVersionMismatch {
            Image(systemName: "exclamationmark.triangle")
              .font(.caption)
              .foregroundStyle(.orange)
              .accessibilityLabel("Recorded in app version \(entry.appVersion ?? "unknown"); may sound different now")
          }
        }
        HStack(spacing: 8) {
          Text(entry.startedAt, format: .relative(presentation: .named))
          Text(formatDuration(entry.playedSeconds))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        songDocument.setPendingSeed(entry.seed)
        songDocument.restart()
      } label: {
        Image(systemName: "play.fill")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Play this take")
    }
    .swipeActions(edge: .leading) {
      Button {
        store.setFavorite(id: entry.id, !entry.favorite)
      } label: {
        Label(entry.favorite ? "Unfavorite" : "Favorite",
              systemImage: entry.favorite ? "star.slash" : "star")
      }
      .tint(.yellow)
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button(role: .destructive) {
        store.delete(id: entry.id)
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }

  /// Spell out each character separated by spaces so VoiceOver doesn't mumble
  /// (e.g. "G H 4 K 2 M 9 P 3 A" instead of "GH4K2M9P3A").
  private func spelled(_ s: String) -> String {
    s.map(String.init).joined(separator: " ")
  }

  private func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds)
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
  }
}
