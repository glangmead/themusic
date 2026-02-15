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
  static func withSource(source: AudioGate, sampleRate: Double) -> AVAudioSourceNode {
    
    var timeBuffer = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
    var valBuffer = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
    
    // The AVAudioSourceNode initializer takes a 'render block' – a closure
    // that the audio engine calls repeatedly to request audio samples.
    return AVAudioSourceNode { (isSilence, timestamp, frameCount, audioBufferList) -> OSStatus in
      // isSilence: A pointer to a Boolean indicating if the buffer contains silence.
      // timestamp: The audio timestamp at which the rendering is happening.
      // frameCount: The number of audio frames (samples) the engine is requesting.
      //             We need to fill this many samples into the buffer.
      // audioBufferList: A pointer to the AudioBufferList structure where we write our samples.
      
      // Fast path: if the gate is closed, zero the buffer and signal silence
      if !source.isOpen {
        let audioBufferListPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for buf in audioBufferListPointer {
          if let data = buf.mData {
            memset(data, 0, Int(buf.mDataByteSize))
          }
        }
        isSilence.pointee = true
        return noErr
      }
      
      let count = Int(frameCount)
      //print("frame count \(count)")
      
      // Safety check for buffer size
      if count > MAX_BUFFER_SIZE {
        // For now, this is a failure state
        fatalError("OS requested a buffer larger than \(MAX_BUFFER_SIZE), please report to the developer.")
      }
      
      // Resize buffers to match requested count without reallocation (if within capacity)
      if timeBuffer.count > count {
        timeBuffer.removeLast(timeBuffer.count - count)
        valBuffer.removeLast(valBuffer.count - count)
      } else if timeBuffer.count < count {
        let diff = count - timeBuffer.count
        timeBuffer.append(contentsOf: repeatElement(0, count: diff))
        valBuffer.append(contentsOf: repeatElement(0, count: diff))
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
      if let firstBuffer = audioBufferListPointer.first, let data = firstBuffer.mData {
        // Run the generator into our internal Double buffer
        source.process(inputs: timeBuffer, outputs: &valBuffer)
        
        let outputPtr = data.assumingMemoryBound(to: Float.self)
        var outputBuffer = UnsafeMutableBufferPointer(start: outputPtr, count: count)
        
        // Convert our internal Doubles to the output Floats
        vDSP.convertElements(of: valBuffer, to: &outputBuffer)
        
        // Handle other channels if they exist (copy from first)
        for i in 1..<audioBufferListPointer.count {
          if let channelBuffer = audioBufferListPointer[i].mData {
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
