//
//  WaveTable.swift
//  Orbital
//
//  Created by Greg Langmead on 10/29/25.
//

import AVFAudio
import Foundation

func loadAudioSignal(audioURL: URL) -> (signal: [Float], rate: Double, frameCount: Int) {
  // also:
  // from scipy.io import wavfile
  // d = wavfile.read("dx117.wav")
  // list(d[1]) <-- python list of floats
  let file = try! AVAudioFile(forReading: audioURL)
  let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.fileFormat.sampleRate, channels: file.fileFormat.channelCount, interleaved: false)!
  let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(file.length))
  try! file.read(into: buf!) // You probably want better error handling
  let floatArray = Array(UnsafeBufferPointer(start: buf?.floatChannelData![0], count: Int(buf!.frameLength)))
  return (signal: floatArray, rate: file.fileFormat.sampleRate, frameCount: Int(file.length))
}
