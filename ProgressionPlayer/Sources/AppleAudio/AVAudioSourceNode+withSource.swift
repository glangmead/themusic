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
    
    // Scratch buffer for time values. Accelerate framework requires all the buffers to be of identical size
    // and I'm observing 512 so far.
    // TODO: But it represents a hard-coded value I will need to move away from.
    var timeBuffer = [CoreFloat](repeating: 0, count: 512)
    
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
      let audioBufferListPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
      
      // the absolute time, as counted by frames
      let framePos = timestamp.pointee.mSampleTime
      let startFrame = CoreFloat(framePos)
      let sr = CoreFloat(sampleRate)
      
      // 1. Fill time buffer using vectorized ramp generation
      let start = startFrame / sr
      let step: CoreFloat = 1.0 / sr
      vDSP.formRamp(withInitialValue: start, increment: step, result: &timeBuffer)
      
      // 2. Process block
      // We assume mono or identical stereo. If stereo, we copy channel 0 to channel 1 later.
      //if let firstBuffer = audioBufferListPointer.first, let data = firstBuffer.mData {
        //let outputPtr = data.assumingMemoryBound(to: CoreFloat.self)
        //let outputBuffer = UnsafeMutableBufferPointer(start: outputPtr, count: count)
        //var outputArray = Array(outputBuffer) // https://stackoverflow.com/questions/41574498/how-to-use-unsafemutablerawpointer-to-fill-an-array
        var outputArray = [CoreFloat](repeating: 0, count: timeBuffer.count)
        source.process(inputs: timeBuffer, outputs: &outputArray)
        
        //let mean = vDSP.mean(outputArray)
        //let meanTime = vDSP.mean(timeBuffer)
        //print("\(meanTime): mean \(mean)")
        
        // Handle other channels if they exist (copy from first)
        for i in 0..<audioBufferListPointer.count {
          if let channelBuffer = audioBufferListPointer[i].mData {
            let channelPtr = channelBuffer.assumingMemoryBound(to: CoreFloat.self)
            channelPtr.update(from: outputArray, count: count)
          }
        }
      //}
      
      // Inform the audio engine that we have generated sound, not silence.
      isSilence.pointee = false
      return noErr
    }
  }
}
