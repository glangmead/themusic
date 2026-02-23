//
//  Sampler.swift
//  Orbital
//
//  Created by Greg Langmead on 2/14/26.
//

import AVFAudio

/// A thin wrapper around AVAudioUnitSampler that owns the sampler node
/// and knows how to load instrument files (wav, aiff, sf2, exs).
/// Parallels Arrow11 as a "space of sonic possibilities" for sample-based sounds.
class Sampler {
  let node: AVAudioUnitSampler
  let fileNames: [String]
  let bank: UInt8
  let program: UInt8
  let resourceBaseURL: URL?

  init(fileNames: [String], bank: UInt8, program: UInt8, resourceBaseURL: URL? = nil) {
    self.node = AVAudioUnitSampler()
    self.fileNames = fileNames
    self.bank = bank
    self.program = program
    self.resourceBaseURL = resourceBaseURL
  }

  /// Loads the instrument into the sampler node. Throws on failure.
  /// Runs the actual file I/O on a background thread so the main thread
  /// remains responsive (important for large SoundFont files).
  func loadInstrument() async throws {
    let urls = fileNames.compactMap { fileName in
      resolveResourceURL(name: fileName, ext: "wav", resourceBaseURL: resourceBaseURL) ??
      resolveResourceURL(name: fileName, ext: "aiff", resourceBaseURL: resourceBaseURL) ??
      resolveResourceURL(name: fileName, ext: "aif", resourceBaseURL: resourceBaseURL)
    }

    // Capture node locally so we can use it from a nonisolated context.
    let samplerNode = node
    let program = program
    let bank = bank

    if !urls.isEmpty {
      try await Task.detached {
        try samplerNode.loadAudioFiles(at: urls)
      }.value
    } else if let fileName = fileNames.first, let url = resolveResourceURL(name: fileName, ext: "exs", resourceBaseURL: resourceBaseURL) {
      try await Task.detached {
        try samplerNode.loadInstrument(at: url)
      }.value
    } else if let fileName = fileNames.first, let url = resolveResourceURL(name: fileName, ext: "sf2", resourceBaseURL: resourceBaseURL) {
      try await Task.detached {
        try samplerNode.loadSoundBankInstrument(at: url, program: program, bankMSB: bank, bankLSB: 0)
      }.value
    } else {
      throw SamplerError.fileNotFound(fileNames)
    }
  }

  enum SamplerError: LocalizedError {
    case fileNotFound([String])

    var errorDescription: String? {
      switch self {
      case .fileNotFound(let names):
        return "Could not find sampler file(s): \(names.joined(separator: ", "))"
      }
    }
  }
}
