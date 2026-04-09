//
//  SongRef.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import Foundation
import MediaPlayer

struct SongRef: Identifiable, Equatable, Sendable {
  /// Stable identity derived from the pattern filename so NSMetadataQuery updates
  /// don't invalidate navigation selections.
  var id: String { patternFileName }
  /// Optional subtitle shown in the playback accessory (e.g. composer name when playing from Classics).
  let subtitle: String?
  let patternFileName: String // e.g. "score/The Beatles – Yesterday.json"

  /// Display name derived from the filename.
  var name: String {
    PatternFilename.displayName(from: URL(filePath: patternFileName).lastPathComponent)
  }

  init(subtitle: String? = nil, patternFileName: String) {
    self.subtitle = subtitle
    self.patternFileName = patternFileName
  }
}

@MainActor @Observable
class SongLibrary {
  var songs: [SongRef] = []

  private var metadataQuery: NSMetadataQuery?
  private var isUsingICloud = false
  private var localBaseURL: URL?

  // MARK: - Song discovery

  /// Start monitoring the iCloud Documents container (or fall back to a local scan).
  func startMonitoring(baseURL: URL?, isICloud: Bool) {
    if isICloud {
      isUsingICloud = true
      startMetadataQuery()
    } else {
      localBaseURL = baseURL
      loadSongsFromLocal(baseURL: baseURL)
    }
  }

  /// Local-only fallback: single directory scan, no JSON reads.
  private func loadSongsFromLocal(baseURL: URL?) {
    guard let baseURL else { return }
    let patternsDir = baseURL.appending(path: "patterns")
    var allFiles: [URL] = []
    for subdir in ["midi", "score", "table"] {
      let dir = patternsDir.appending(path: subdir)
      let files = (try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil
      )) ?? []
      allFiles += files
    }
    songs = allFiles
      .filter { $0.pathExtension == "json" }
      .map { url in
        let subdir = url.deletingLastPathComponent().lastPathComponent
        return SongRef(patternFileName: "\(subdir)/\(url.lastPathComponent)")
      }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private func startMetadataQuery() {
    let query = NSMetadataQuery()
    query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
    query.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)

    NotificationCenter.default.addObserver(
      forName: .NSMetadataQueryDidFinishGathering,
      object: query,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.handleQueryResults() }
    }

    NotificationCenter.default.addObserver(
      forName: .NSMetadataQueryDidUpdate,
      object: query,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.handleQueryResults() }
    }

    query.start()
    metadataQuery = query
  }

  private static let validSubdirs: Set<String> = ["midi", "score", "table"]

  private func handleQueryResults() {
    metadataQuery?.disableUpdates()
    defer { metadataQuery?.enableUpdates() }

    guard let results = metadataQuery?.results as? [NSMetadataItem] else { return }

    // NSMetadataQuery can return duplicate items during live updates.
    // Deduplicate by patternFileName.
    var seen = Set<String>()
    songs = results.compactMap { item -> SongRef? in
      guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
            url.pathExtension == "json"
      else { return nil }
      let subdir = url.deletingLastPathComponent().lastPathComponent
      guard Self.validSubdirs.contains(subdir) else { return nil }
      let parentDir = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
      guard parentDir == "patterns" else { return nil }
      let filename = "\(subdir)/\(url.lastPathComponent)"
      guard seen.insert(filename).inserted else { return nil }
      return SongRef(patternFileName: filename)
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// Playback states keyed by SongRef.id, created lazily by SongCells.
  var playbackStates: [String: SongDocument] = [:]

  /// Manages lock screen / Control Center Now Playing info and remote commands.
  private var _nowPlayingManager: NowPlayingManager?
  var nowPlayingManager: NowPlayingManager {
    if let existing = _nowPlayingManager { return existing }
    let manager = NowPlayingManager(library: self)
    _nowPlayingManager = manager
    return manager
  }

  /// The currently playing (or paused) song's state, if any.
  var currentPlaybackState: SongDocument?

  func playbackState(for song: SongRef, engine: SpatialAudioEngine, resourceBaseURL: URL? = nil) -> SongDocument {
    if let existing = playbackStates[song.id] { return existing }
    let state = SongDocument(song: song, engine: engine, resourceBaseURL: resourceBaseURL)
    playbackStates[song.id] = state
    return state
  }

  /// Play a pre-built SongDocument (e.g. from the Classics browser).
  /// Stops any currently playing song first; toggles pause/resume if the same doc is re-tapped.
  func play(document: SongDocument) {
    if document === currentPlaybackState {
      document.togglePlayback()
      if document.isPaused {
        nowPlayingManager.songPaused()
      } else {
        nowPlayingManager.songResumed(name: document.song.name)
      }
      return
    }
    currentPlaybackState?.stop()
    currentPlaybackState = document
    document.togglePlayback()
    nowPlayingManager.songStarted(name: document.song.name)
  }

  /// Start playing a song, stopping any currently playing song first.
  /// If the tapped song is already the current song, toggle pause/resume.
  func play(_ song: SongRef, engine: SpatialAudioEngine, resourceBaseURL: URL? = nil) {
    let state = playbackState(for: song, engine: engine, resourceBaseURL: resourceBaseURL)
    if state === currentPlaybackState {
      state.togglePlayback()
      if state.isPaused {
        nowPlayingManager.songPaused()
      } else {
        nowPlayingManager.songResumed(name: song.name)
      }
      return
    }
    currentPlaybackState?.stop()
    currentPlaybackState = state
    state.togglePlayback()
    nowPlayingManager.songStarted(name: song.name)
  }

  /// True when the current song is playing, paused, or loading.
  var anySongPlaying: Bool {
    currentPlaybackState?.isPlaying == true || currentPlaybackState?.isLoading == true
  }

  /// True when the current song is paused.
  var allPaused: Bool {
    currentPlaybackState?.isPaused == true
  }

  /// True when the current song is still loading (e.g. SoundFont instruments).
  var isLoading: Bool {
    currentPlaybackState?.isLoading == true
  }

  /// The name of the currently playing or loading song, if any.
  var currentSongName: String? {
    guard let state = currentPlaybackState, state.isPlaying || state.isLoading else { return nil }
    return state.song.name
  }

  /// The most recent chord change label from the currently playing score, if any.
  var currentChordLabel: String? {
    currentPlaybackState?.currentChordLabel
  }

  func pauseAll() {
    currentPlaybackState?.pause()
    nowPlayingManager.songPaused()
  }

  func resumeAll() {
    currentPlaybackState?.resume()
    if let name = currentSongName {
      nowPlayingManager.songResumed(name: name)
    }
  }

  func stopAll() {
    currentPlaybackState?.stop()
    currentPlaybackState = nil
    nowPlayingManager.songStopped()
  }

  func deleteSong(_ song: SongRef) {
    // Stop playback if this song is currently playing
    if currentPlaybackState === playbackStates[song.id] {
      currentPlaybackState?.stop()
      currentPlaybackState = nil
      nowPlayingManager.songStopped()
    }
    playbackStates[song.id] = nil
    songs.removeAll { $0.id == song.id }
    PatternStorage.delete(filename: song.patternFileName)
  }

  func duplicateSong(_ song: SongRef, resourceBaseURL: URL?) {
    guard PatternStorage.duplicate(filename: song.patternFileName) != nil else { return }
    if !isUsingICloud {
      loadSongsFromLocal(baseURL: resourceBaseURL ?? localBaseURL)
    }
  }
}

// MARK: - NowPlayingManager

/// Publishes song metadata to the lock screen / Control Center and handles
/// remote transport commands (play, pause, stop via headphones or lock screen).
@MainActor
class NowPlayingManager {
  private weak var library: SongLibrary?
  private var commandsRegistered = false

  init(library: SongLibrary) {
    self.library = library
    registerRemoteCommands()
  }

  // MARK: State updates

  func songStarted(name: String) {
    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = [
      MPMediaItemPropertyTitle: name,
      MPNowPlayingInfoPropertyPlaybackRate: 1.0
    ]
  }

  func songPaused() {
    let center = MPNowPlayingInfoCenter.default()
    var info = center.nowPlayingInfo ?? [:]
    info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
    center.nowPlayingInfo = info
  }

  func songResumed(name: String) {
    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = [
      MPMediaItemPropertyTitle: name,
      MPNowPlayingInfoPropertyPlaybackRate: 1.0
    ]
  }

  func songStopped() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  // MARK: Remote commands

  private func registerRemoteCommands() {
    guard !commandsRegistered else { return }
    commandsRegistered = true

    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.library?.resumeAll()
      return .success
    }

    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.library?.pauseAll()
      return .success
    }

    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let library = self?.library else { return .commandFailed }
      if library.allPaused {
        library.resumeAll()
      } else {
        library.pauseAll()
      }
      return .success
    }

    commandCenter.stopCommand.addTarget { [weak self] _ in
      self?.library?.stopAll()
      return .success
    }

    // Disable unsupported commands
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.isEnabled = false
  }
}
