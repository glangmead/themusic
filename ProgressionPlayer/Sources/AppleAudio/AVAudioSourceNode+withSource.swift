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
    
    // Underrun protection: detect gaps in mSampleTime between successive
    // callbacks. A gap means the audio thread fell behind and the hardware
    // played stale/corrupt samples (the glitch). We can't prevent that first
    // pop, but we fade to silence quickly afterwards to prevent sustained
    // crackling, then smoothly fade back in once timing stabilizes.
    var lastSampleTime: Float64 = -1
    var lastFrameCount: UInt32 = 0
    var fadeGain: Float = 1.0
    var isFadingOut = false
    var stableCallbackCount = 0
    var gainRampBuffer = [Float](repeating: 1.0, count: MAX_BUFFER_SIZE)
    
    let fadeOutRate: Float = 0.05    // multiply gain by this per buffer (~instant fade out)
    let fadeInRate: Float = 0.002    // added per sample (~10ms fade in at 48kHz)
    let stableCountThreshold = 3     // require N stable callbacks before fading back in
    
    // The AVAudioSourceNode initializer takes a 'render block' – a closure
    // that the audio engine calls repeatedly to request audio samples.
    return AVAudioSourceNode { (isSilence, timestamp, frameCount, audioBufferList) -> OSStatus in
      
      // Fast path: if the gate is closed, zero the buffer and signal silence
      if !source.isOpen {
        let audioBufferListPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for buf in audioBufferListPointer {
          if let data = buf.mData {
            memset(data, 0, Int(buf.mDataByteSize))
          }
        }
        isSilence.pointee = true
        lastSampleTime = -1
        lastFrameCount = 0
        fadeGain = 1.0
        isFadingOut = false
        stableCallbackCount = 0
        return noErr
      }
      
      let count = Int(frameCount)
      
      // Safety check for buffer size
      if count > MAX_BUFFER_SIZE {
        fatalError("OS requested a buffer larger than \(MAX_BUFFER_SIZE), please report to the developer.")
      }
      
      // --- Underrun detection ---
      let currentSampleTime = timestamp.pointee.mSampleTime
      if lastSampleTime >= 0 {
        let expectedSampleTime = lastSampleTime + Float64(lastFrameCount)
        let gap = currentSampleTime - expectedSampleTime
        if gap > 1.0 {
          isFadingOut = true
          stableCallbackCount = 0
        } else {
          stableCallbackCount += 1
        }
      }
      lastSampleTime = currentSampleTime
      lastFrameCount = frameCount
      
      // --- Update fade gain ---
      if isFadingOut {
        fadeGain *= fadeOutRate
        if fadeGain < 0.0001 {
          fadeGain = 0
        }
        if stableCallbackCount >= stableCountThreshold {
          isFadingOut = false
        }
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
      
      // --- Silence fast path when fully faded out ---
      if fadeGain == 0 {
        for buf in audioBufferListPointer {
          if let data = buf.mData {
            memset(data, 0, Int(buf.mDataByteSize))
          }
        }
        isSilence.pointee = true
        // Still process DSP so internal time advances correctly
        source.process(inputs: timeBuffer, outputs: &valBuffer)
        return noErr
      }
      
      // 2. Process block
      if let firstBuffer = audioBufferListPointer.first, let data = firstBuffer.mData {
        source.process(inputs: timeBuffer, outputs: &valBuffer)
        
        let outputPtr = data.assumingMemoryBound(to: Float.self)
        var outputBuffer = UnsafeMutableBufferPointer(start: outputPtr, count: count)
        
        // Convert our internal Doubles to the output Floats
        vDSP.convertElements(of: valBuffer, to: &outputBuffer)
        
        // 3. Apply gain (fade out or fade in)
        if fadeGain < 1.0 {
          if isFadingOut {
            // Uniform scale — fading out rapidly
            var gain = fadeGain
            vDSP_vsmul(outputPtr, 1, &gain, outputPtr, 1, vDSP_Length(count))
          } else {
            // Fading back in — per-sample linear ramp for smooth recovery
            var currentGain = fadeGain
            for i in 0..<count {
              gainRampBuffer[i] = currentGain
              currentGain = min(1.0, currentGain + fadeInRate)
            }
            vDSP_vmul(outputPtr, 1, &gainRampBuffer, 1, outputPtr, 1, vDSP_Length(count))
            fadeGain = min(1.0, fadeGain + fadeInRate * Float(count))
          }
        }
        
        // Handle other channels if they exist (copy from first, after gain)
        for i in 1..<audioBufferListPointer.count {
          if let channelBuffer = audioBufferListPointer[i].mData {
            let channelPtr = channelBuffer.assumingMemoryBound(to: Float.self)
            channelPtr.update(from: outputPtr, count: count)
          }
        }
      }
      
      isSilence.pointee = ObjCBool(fadeGain == 0)
      return noErr
    }
  }
}
