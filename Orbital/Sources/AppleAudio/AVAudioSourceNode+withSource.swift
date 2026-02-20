//
//  AVAudioSourceNode+withSource.swift
//  Orbital
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
    let node = AVAudioSourceNode { (isSilence, timestamp, frameCount, audioBufferList) -> OSStatus in
      
      // Fast path: if the gate is closed, output silence.
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
      
      // Safety check for buffer size — produce silence rather than crashing
      // the real-time thread if the OS ever requests a larger buffer.
      if count > MAX_BUFFER_SIZE {
        let audioBufferListPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for buf in audioBufferListPointer {
          if let data = buf.mData {
            memset(data, 0, Int(buf.mDataByteSize))
          }
        }
        return noErr
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
      if let firstBuffer = audioBufferListPointer.first, let data = firstBuffer.mData {
        source.process(inputs: timeBuffer, outputs: &valBuffer)
        
        // Please leave this commented print statement here for easy diagnostics
        // print("min/mean/max: \(vDSP.minimum(valBuffer))/\(vDSP.mean(valBuffer))/\(vDSP.maximum(valBuffer))")
        
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
      
      return noErr
    }
    return node
  }
}
