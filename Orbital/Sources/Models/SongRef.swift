//
//  SongRef.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import Foundation
import MediaPlayer

struct SongRef: Identifiable {
  let id = UUID()
  let name: String
  let patternFileName: String // e.g. "aurora_arpeggio.json"
}

/// Lightweight struct for decoding just the pattern name from a JSON file.
private struct PatternNameOnly: Decodable {
  let name: String
}

@MainActor @Observable
class SongLibrary {
  var songs: [SongRef] = []

  /// Populate the song list by enumerating pattern JSON files in the given directory.
  func loadSongs(from baseURL: URL?) {
    guard let baseURL else { return }
    let patternsDir = baseURL.appendingPathComponent("patterns")
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: patternsDir,
      includingPropertiesForKeys: nil
    ) else { return }
    songs = files
      .filter { $0.pathExtension == "json" }
      .compactMap { url -> SongRef? in
        guard let data = try? Data(contentsOf: url),
              let nameOnly = try? JSONDecoder().decode(PatternNameOnly.self, from: data)
        else { return nil }
        return SongRef(name: nameOnly.name, patternFileName: url.lastPathComponent)
      }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// Playback states keyed by SongRef.id, created lazily by SongCells.
  var playbackStates: [UUID: SongDocument] = [:]

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
    loadSongs(from: resourceBaseURL)
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
      MPNowPlayingInfoPropertyPlaybackRate: 1.0,
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
      MPNowPlayingInfoPropertyPlaybackRate: 1.0,
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
