//
//  AVAudioUnitReverb+Mac.swift
//  Orbital
//
//  Workaround for macOS bug where AVAudioUnitReverb.loadFactoryPreset()
//  is silently ignored. macOS uses kAudioUnitSubType_MatrixReverb instead
//  of kAudioUnitSubType_Reverb2, and the preset mapping is broken.
//  See: https://stackoverflow.com/questions/45644747
//
//  On iOS-app-on-Mac (designed for iPad), we go through the AUAudioUnit
//  factoryPresets API which correctly applies the preset on both platforms.
//

import AVFAudio

extension AVAudioUnitReverb {
  /// Loads a factory preset via the AUAudioUnit API, working around
  /// the macOS bug where loadFactoryPreset(_:) is silently ignored.
  func loadFactoryPresetReliably(_ preset: AVAudioUnitReverbPreset) {
    if ProcessInfo.processInfo.isiOSAppOnMac {
      let au = auAudioUnit
      if let factoryPresets = au.factoryPresets,
         let match = factoryPresets.first(where: { $0.number == preset.rawValue }) {
        au.currentPreset = match
      }
    } else {
      loadFactoryPreset(preset)
    }
  }
}
