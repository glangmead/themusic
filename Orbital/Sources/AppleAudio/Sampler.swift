//
//  Sampler.swift
//  ProgressionPlayer
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
  
  init(fileNames: [String], bank: UInt8, program: UInt8) {
    self.node = AVAudioUnitSampler()
    self.fileNames = fileNames
    self.bank = bank
    self.program = program
  }
  
  func loadInstrument() {
    let urls = fileNames.compactMap { fileName in
      Bundle.main.url(forResource: fileName, withExtension: "wav") ??
      Bundle.main.url(forResource: fileName, withExtension: "aiff") ??
      Bundle.main.url(forResource: fileName, withExtension: "aif")
    }
    
    if !urls.isEmpty {
      do {
        try node.loadAudioFiles(at: urls)
      } catch {
        print("Error loading audio file \(urls): \(error.localizedDescription)")
      }
    } else if let fileName = fileNames.first, let url = Bundle.main.url(forResource: fileName, withExtension: "exs") {
      do {
        try node.loadInstrument(at: url)
      } catch {
        print("Error loading exs instrument \(fileName): \(error.localizedDescription)")
      }
    } else if let fileName = fileNames.first, let url = Bundle.main.url(forResource: fileName, withExtension: "sf2") {
      do {
        try node.loadSoundBankInstrument(at: url, program: program, bankMSB: bank, bankLSB: 0)
        print("loaded program \(program) bankMSB \(bank) bankLSB 0")
      } catch {
        print("Error loading sound bank instrument \(fileName): \(error.localizedDescription)")
      }
    } else {
      print("Could not find sampler file(s): \(fileNames)")
    }
  }
}
