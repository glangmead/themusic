//
//  ChoraleVoicer.swift
//  Orbital
//
//  Voice-leading constraint solver for the chorale generator.
//  Given the previous upper-voice pitches, the next ChordInScale (including bass),
//  and an optional target OUCH configuration, find the assignment of chord tones
//  to upper voices that minimizes voice movement while respecting constraints.
//
//  For triads (3 upper voices), the target configuration narrows the search.
//  For sevenths (4 upper voices), all chord tones are present without doubling
//  and the solver enumerates 4! permutations across candidate octaves.
//  For dyads (2 upper voices), the solver places each tone minimizing motion.
//

import Foundation

// MARK: - Constraints

/// Configuration for the voice-leading solver.
struct VoicingConstraints {
  /// MIDI range within which any upper voice may land.
  var upperVoiceRange: ClosedRange<Int>
  /// Leaps beyond this semitone threshold incur a soft penalty.
  var maxLeapSemitones: Int
  /// Reject progressions that create parallel fifths or octaves between any two voices.
  var avoidParallels: Bool
  /// Reject doubling the scale's 7th degree (leading tone) across bass + upper voices.
  var avoidLeadingToneDoubling: Bool

  static let `default` = VoicingConstraints(
    upperVoiceRange: 55...84,       // G3 through C6 — roomy chorale range
    maxLeapSemitones: 7,            // perfect fifth
    avoidParallels: true,
    avoidLeadingToneDoubling: true
  )
}

// MARK: - Voicer

/// Finds the upper-voice MIDI pitches for the next chord given a previous voicing.
struct ChoraleVoicer {
  var constraints: VoicingConstraints

  init(constraints: VoicingConstraints = .default) {
    self.constraints = constraints
  }

  /// Produce the next upper-voice MIDI tuple.
  func voice( // swiftlint:disable:this function_parameter_count
    previousUpper: [Int],
    previousBass: Int,
    nextChordPCs: [Int],
    nextBass: Int,
    upperVoiceCount: Int,
    targetConfiguration: OUCHConfiguration?,
    scaleRootPC: Int
  ) -> [Int] {
    let candidates = enumerateCandidates(
      chordPCs: nextChordPCs,
      upperVoiceCount: upperVoiceCount,
      targetConfiguration: targetConfiguration
    )

    let leadingTonePC = ((scaleRootPC - 1) % 12 + 12) % 12

    var best: [Int]?
    var bestCost = Double.infinity

    for candidate in candidates {
      if !candidate.allSatisfy(constraints.upperVoiceRange.contains) { continue }
      // Voices must be strictly increasing (no crossings, no unison among upper voices
      // except for U_DI which explicitly allows adjacent unison).
      if !allowsCrossingCheck(candidate: candidate, configuration: targetConfiguration) { continue }
      // Must not cross the bass.
      if candidate.first! <= nextBass { continue }

      if constraints.avoidLeadingToneDoubling {
        var ltCount = 0
        if ((nextBass % 12) + 12) % 12 == leadingTonePC { ltCount += 1 }
        for pitch in candidate where ((pitch % 12) + 12) % 12 == leadingTonePC {
          ltCount += 1
        }
        if ltCount >= 2 { continue }
      }

      var cost = motionCost(previous: previousUpper, next: candidate)
      if constraints.avoidParallels,
         !previousUpper.isEmpty,
         hasParallelFifthsOrOctaves(
          prevUpper: previousUpper, prevBass: previousBass,
          newUpper: candidate, newBass: nextBass
         ) {
        cost += 60  // strong penalty — still better than holding or transitioning to silence
      }
      if cost < bestCost {
        bestCost = cost
        best = candidate
      }
    }

    if let best { return best }
    // No candidate satisfied the constraints. Prefer to hold the previous voicing
    // if it's available — keeps the voices from dropping to a dissonant default.
    if !previousUpper.isEmpty, previousUpper.count == upperVoiceCount {
      return previousUpper
    }
    return fallbackInitial(chordPCs: nextChordPCs, upperVoiceCount: upperVoiceCount)
  }

  // MARK: Candidate enumeration

  private func enumerateCandidates(
    chordPCs: [Int],
    upperVoiceCount: Int,
    targetConfiguration: OUCHConfiguration?
  ) -> [[Int]] {
    let uniquePCs = Array(Set(chordPCs))
    let lo = constraints.upperVoiceRange.lowerBound
    let hi = constraints.upperVoiceRange.upperBound

    // For each chord tone, all MIDI pitches in range that share its pitch class.
    func pitches(for pc: Int) -> [Int] {
      var out: [Int] = []
      for midi in lo...hi where ((midi % 12) + 12) % 12 == ((pc % 12) + 12) % 12 {
        out.append(midi)
      }
      return out
    }

    switch upperVoiceCount {
    case 2:
      // Dyad: pick one pitch per chord tone (2 tones, 2 voices, no doubling).
      guard uniquePCs.count == 2 else { return [] }
      var result: [[Int]] = []
      let a = pitches(for: uniquePCs[0])
      let b = pitches(for: uniquePCs[1])
      for pa in a {
        for pb in b where pb > pa { result.append([pa, pb]) }
      }
      return result

    case 4:
      // Seventh: permute 4 distinct chord tones across 4 voices.
      guard uniquePCs.count == 4 else { return [] }
      var result: [[Int]] = []
      for perm in permutations(uniquePCs) {
        let a = pitches(for: perm[0])
        let b = pitches(for: perm[1])
        let c = pitches(for: perm[2])
        let d = pitches(for: perm[3])
        for pa in a {
          for pb in b where pb > pa {
            for pc in c where pc > pb {
              for pd in d where pd > pc {
                result.append([pa, pb, pc, pd])
              }
            }
          }
        }
      }
      return result

    case 3:
      guard uniquePCs.count == 3 else { return [] }
      return enumerateTriadCandidates(
        chordPCs: uniquePCs,
        target: targetConfiguration,
        pitches: pitches
      )

    default:
      return []
    }
  }

  private func enumerateTriadCandidates(
    chordPCs: [Int],
    target: OUCHConfiguration?,
    pitches: (Int) -> [Int]
  ) -> [[Int]] {
    var result: [[Int]] = []

    // Complete candidates (all 3 chord tones present).
    for perm in permutations(chordPCs) {
      let a = pitches(perm[0])
      let b = pitches(perm[1])
      let c = pitches(perm[2])
      for pa in a {
        for pb in b where pb > pa {
          for pc in c where pc > pb {
            let spans = [pb - pa, pc - pb]
            let outer = pc - pa
            let config = triadConfiguration(spans: spans, outerSpan: outer, voices: [pa, pb, pc])
            if target == nil || config == target! {
              result.append([pa, pb, pc])
            }
          }
        }
      }
    }

    // Incomplete candidates (2 chord tones, one doubled) for H / U_DI / U_OO.
    guard let target, target != .closed, target != .open else {
      return result
    }

    for doubled in chordPCs {
      let otherPCs = chordPCs.filter { $0 != doubled }
      for other in otherPCs {
        let d = pitches(doubled)
        let o = pitches(other)
        // Three voices: two on `doubled`, one on `other`. All orderings, ascending.
        for dA in d {
          for dB in d where dB > dA {
            for pO in o {
              let voices = [dA, dB, pO].sorted()
              if Set(voices).count < 3 && target != .unusualDoubleInterval { continue }
              let spans = [voices[1] - voices[0], voices[2] - voices[1]]
              let outer = voices[2] - voices[0]
              let config = triadConfiguration(spans: spans, outerSpan: outer, voices: voices)
              if config == target { result.append(voices) }
            }
            if target == .unusualDoubleInterval {
              for pO in o {
                let voices = [dA, dA, pO].sorted()
                let spans = [voices[1] - voices[0], voices[2] - voices[1]]
                let outer = voices[2] - voices[0]
                if outer <= 12 && (spans[0] == 0 || spans[1] == 0) {
                  result.append(voices)
                }
              }
            }
          }
        }
      }
    }
    return result
  }

  private func triadConfiguration(spans: [Int], outerSpan: Int, voices: [Int]) -> OUCHConfiguration {
    let pcs = Set(voices.map { ((($0 % 12) + 12) % 12) })
    if pcs.count == 3 {
      return outerSpan < 12 ? .closed : .open
    }
    if spans.contains(0) { return .unusualDoubleInterval }
    if outerSpan == 12 { return .halfOpen }
    if spans.contains(12) { return .unusualOpenOctave }
    return .halfOpen
  }

  // MARK: - Cost

  private func motionCost(previous: [Int], next: [Int]) -> Double {
    let center = (constraints.upperVoiceRange.lowerBound + constraints.upperVoiceRange.upperBound) / 2
    // Quadratic pull toward range center keeps the chord from drifting endlessly
    // upward (or downward) under repeated T or TT shifts. Small drifts are nearly
    // free; large drifts get expensive enough that the voicer prefers to wrap
    // a voice down an octave instead of marching past the range boundary.
    let centroid = next.reduce(0, +) / next.count
    let drift = centroid - center
    let centroidPenalty = Double(drift * drift) * 0.5

    guard previous.count == next.count else {
      // First-chord initialization: pick smallest span from the range center.
      return Double(next.map { abs($0 - center) }.reduce(0, +)) + centroidPenalty
    }
    var cost = centroidPenalty
    for (pv, nv) in zip(previous, next) {
      let leap = abs(nv - pv)
      cost += Double(leap)
      if leap > constraints.maxLeapSemitones {
        cost += Double((leap - constraints.maxLeapSemitones) * 4)
      }
    }
    return cost
  }

  // MARK: - Crossing check

  private func allowsCrossingCheck(candidate: [Int], configuration: OUCHConfiguration?) -> Bool {
    for i in 1..<candidate.count {
      if candidate[i] < candidate[i - 1] { return false }
      if candidate[i] == candidate[i - 1] && configuration != .unusualDoubleInterval { return false }
    }
    return true
  }

  // MARK: - Parallels

  private func hasParallelFifthsOrOctaves(
    prevUpper: [Int], prevBass: Int,
    newUpper: [Int], newBass: Int
  ) -> Bool {
    guard prevUpper.count == newUpper.count else { return false }
    let prev = [prevBass] + prevUpper
    let next = [newBass] + newUpper
    for i in 0..<prev.count {
      for j in (i + 1)..<prev.count {
        let prevInterval = abs(prev[j] - prev[i]) % 12
        let newInterval = abs(next[j] - next[i]) % 12
        if (prevInterval == 7 && newInterval == 7) ||
           (prevInterval == 0 && newInterval == 0) {
          // Same interval, and both voices actually moved — parallel motion.
          if prev[i] != next[i] && prev[j] != next[j] {
            return true
          }
        }
      }
    }
    return false
  }

  // MARK: - Fallbacks

  private func fallbackInitial(chordPCs: [Int], upperVoiceCount: Int) -> [Int] {
    let center = (constraints.upperVoiceRange.lowerBound + constraints.upperVoiceRange.upperBound) / 2
    print("fallbackInitial of chordPCs \(chordPCs)")
    let uniquePCs = Array(Set(chordPCs))
    guard !uniquePCs.isEmpty else {
      // No chord tones resolved — emit a close-position major triad at the center,
      // strictly inside the allowed range. Picks consonance over silence so the
      // ear isn't blasted by a semitone cluster.
      let base = max(constraints.upperVoiceRange.lowerBound,
                     min(constraints.upperVoiceRange.upperBound - 12, center))
      let offsets = [0, 4, 7, 12]  // major triad with octave doubling, up to 4 voices
      return (0..<upperVoiceCount).map { base + offsets[$0 % offsets.count] }
    }
    var result: [Int] = []
    var last = center - 12
    for i in 0..<upperVoiceCount {
      let pc = uniquePCs[i % uniquePCs.count]
      var candidate = center - 12
      for midi in constraints.upperVoiceRange where ((midi % 12) + 12) % 12 == ((pc % 12) + 12) % 12 {
        if midi > last {
          candidate = midi
          break
        }
      }
      last = candidate
      result.append(candidate)
    }
    return result.sorted()
  }
}

// MARK: - Permutations

private func permutations<T>(_ array: [T]) -> [[T]] {
  if array.count <= 1 { return [array] }
  var result: [[T]] = []
  for i in 0..<array.count {
    var rest = array
    let picked = rest.remove(at: i)
    for tail in permutations(rest) {
      result.append([picked] + tail)
    }
  }
  return result
}
