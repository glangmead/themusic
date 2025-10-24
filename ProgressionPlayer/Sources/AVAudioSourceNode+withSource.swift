//
//  AVAudioSourceNode+withSource.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/15/25.
//

import AVFAudio

extension AVAudioSourceNode {
  static func withSource(source: Arrow11, sampleRate: Double) -> AVAudioSourceNode {
    
    // The AVAudioSourceNode initializer takes a 'render block' – a closure
    // that the audio engine calls repeatedly to request audio samples.
    AVAudioSourceNode { (isSilence, timestamp, frameCount, audioBufferList) -> OSStatus in
      // isSilence: A pointer to a Boolean indicating if the buffer contains silence.
      //            We'll set this to 'false' as we are generating sound.
      // timestamp: The audio timestamp at which the rendering is happening.
      // frameCount: The number of audio frames (samples) the engine is requesting.
      //             We need to fill this many samples into the buffer.
      // audioBufferList: A pointer to the AudioBufferList structure where we write our samples.
      
      // Create a mutable pointer to the AudioBufferList for easier access.
      let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
      
      // the absolute time, as counted by frames
      let framePos = timestamp.pointee.mSampleTime
      
      // Loop through each frame (sample) that the audio engine is requesting.
      for frameDelta in 0..<Int(frameCount) {
        // Get the next amplitude sample from our custom WaveOscillator.
        // Our oscillator produces Double values between -1.0 and 1.0.
        //let sample = source.nextSample()
        let sample = source.of((framePos + Double(frameDelta))/sampleRate)
        //print("\(sample)")
        // For a stereo sound, there would be two buffers (left and right channels).
        // For a mono sound, typically one buffer.
        for buffer in ablPointer {
          guard let pointer = buffer.mData?.assumingMemoryBound(to: Float.self) else {
            continue // Skip to the next buffer if pointer is invalid
          }
          
          // Write the sample to the current frame in the buffer.
          // We cast the Double sample from our oscillator to Float,
          // as Float is the expected sample type for Core Audio.
          pointer[frameDelta] = Float(sample)
        }
      }
      
      // Inform the audio engine that we have generated sound, not silence.
      isSilence.pointee = false
      return noErr
    }
  }
}
