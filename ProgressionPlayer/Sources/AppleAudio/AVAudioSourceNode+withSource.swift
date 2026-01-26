//
//  AVAudioSourceNode+withSource.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/15/25.
//

import AVFAudio
import CoreAudio
import Accelerate

extension AVAudioSourceNode {
  static func withSource(source: Arrow11, sampleRate: Double) -> AVAudioSourceNode {
    
    // Scratch buffer for time values. 4096 is assumed to be enough for CoreAudio on various hardware.
    var timeBuffer = [Float](repeating: 0, count: 4096)
    
    // The AVAudioSourceNode initializer takes a 'render block' – a closure
    // that the audio engine calls repeatedly to request audio samples.
    return AVAudioSourceNode { (isSilence, timestamp, frameCount, audioBufferList) -> OSStatus in
      // isSilence: A pointer to a Boolean indicating if the buffer contains silence.
      //            We'll set this to 'false' as we are generating sound.
      // timestamp: The audio timestamp at which the rendering is happening.
      // frameCount: The number of audio frames (samples) the engine is requesting.
      //             We need to fill this many samples into the buffer.
      // audioBufferList: A pointer to the AudioBufferList structure where we write our samples.
      
      let count = Int(frameCount)
      
      // Safety check for buffer size
      if count > timeBuffer.count {
        // For now, this is a failure state
        fatalError("OS requested a buffer larger than 4096, please report to the developer.")
      }
      
      // Create a mutable pointer to the AudioBufferList for easier access.
      let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
      
      // the absolute time, as counted by frames
      let framePos = timestamp.pointee.mSampleTime
      let startFrame = CoreFloat(framePos)
      let sr = CoreFloat(sampleRate)
      
      // 1. Fill time buffer using vectorized ramp generation
      var start = startFrame / sr
      var step: Float = 1.0 / sr
      vDSP_vramp(&start, &step, &timeBuffer, 1, vDSP_Length(count))
      
      // 2. Process block
      // We assume mono or identical stereo. If stereo, we copy channel 0 to channel 1 later.
      if let firstBuffer = ablPointer.first, let data = firstBuffer.mData {
        let outputPtr = data.assumingMemoryBound(to: Float.self)
        let outputBuffer = UnsafeMutableBufferPointer(start: outputPtr, count: count)
        
        timeBuffer.withUnsafeBufferPointer { timePtr in
          let timeSlice = UnsafeBufferPointer(start: timePtr.baseAddress, count: count)
          source.process(inputs: timeSlice, outputs: outputBuffer)
        }
        
        // Handle other channels if they exist (copy from first)
        for i in 1..<ablPointer.count {
          if let channelBuffer = ablPointer[i].mData {
            let channelPtr = channelBuffer.assumingMemoryBound(to: Float.self)
            channelPtr.update(from: outputPtr, count: count)
          }
        }
      }
      
      // Inform the audio engine that we have generated sound, not silence.
      isSilence.pointee = false
      return noErr
    }
  }
}
