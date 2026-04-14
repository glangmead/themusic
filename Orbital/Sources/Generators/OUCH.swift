//
//  OUCH.swift
//  Orbital
//
//  Tymoczko's upper-voice configuration system for triadic chorale counterpoint.
//  See Tonality: An Owner's Manual, Chapter 3 §6 (pp. 125-128), Figure 3.6.4.
//
//  Five configurations describe the spacing of three upper voices over an
//  independent bass. The Bach-style state machine in OUCHState drives the
//  chorale voicer — powers of T/t leave the configuration invariant, so moving
//  between configurations requires a non-uniform reassignment by the solver.
//

import Foundation

// MARK: - OUCHConfiguration

/// The five upper-voice spacing configurations for triadic counterpoint.
enum OUCHConfiguration: String, Codable, CaseIterable {
  /// All three voices within one octave, complete triad.
  case closed
  /// Each voice two chord steps above the next-lowest, complete triad (> 1 octave span).
  case open
  /// Two voices an octave apart with the third voice between them; 2 distinct pitch classes.
  case halfOpen
  /// Two adjacent voices at unison, third voice within an octave; 2 distinct pitch classes.
  case unusualDoubleInterval
  /// Two voices an octave apart, third voice outside that span; 2 distinct pitch classes.
  case unusualOpenOctave

  var displayName: String {
    switch self {
    case .closed:                return "Closed"
    case .open:                  return "Open"
    case .halfOpen:              return "Half-Open"
    case .unusualDoubleInterval: return "Unusual (Doubled Unison)"
    case .unusualOpenOctave:     return "Unusual (Open Octave)"
    }
  }
}

// MARK: - OUCHSelector

/// User-facing selection: pin to one configuration, or let the state machine walk.
enum OUCHSelector: String, Codable, CaseIterable {
  case fixedClosed
  case fixedOpen
  case fixedHalfOpen
  case fixedUnusual
  case stochastic

  var displayName: String {
    switch self {
    case .fixedClosed:   return "Always Closed"
    case .fixedOpen:     return "Always Open"
    case .fixedHalfOpen: return "Always Half-Open"
    case .fixedUnusual:  return "Always Unusual"
    case .stochastic:    return "Stochastic (Bach-like)"
    }
  }
}

// MARK: - OUCHState

/// Stateful OUCH configuration walker. Holds the current configuration and
/// samples the next from a weighted transition table.
struct OUCHState {
  var current: OUCHConfiguration

  init(current: OUCHConfiguration = .closed) {
    self.current = current
  }

  /// Transition probabilities from Tymoczko Figure 3.6.3 (Bach chorales).
  /// Includes self-loops closed→closed (31.8%) and open→open (11.8%) — the two
  /// most common transitions in the corpus.
  static let bachTransitions: [OUCHConfiguration: [(OUCHConfiguration, Double)]] = [
    .closed: [
      (.closed, 0.318),
      (.halfOpen, 0.091),
      (.unusualDoubleInterval, 0.036),
      (.open, 0.028)
    ],
    .open: [
      (.open, 0.118),
      (.halfOpen, 0.043),
      (.closed, 0.031),
      (.unusualOpenOctave, 0.016)
    ],
    .halfOpen: [
      (.closed, 0.085),
      (.open, 0.046),
      (.halfOpen, 0.033)
    ],
    .unusualDoubleInterval: [
      (.closed, 0.035)
    ],
    .unusualOpenOctave: [
      (.open, 0.017)
    ]
  ]

  /// Step the state by sampling from the transition table (stochastic) or
  /// jumping to the fixed target.
  mutating func step(using rng: inout SeededRNG, selector: OUCHSelector) -> OUCHConfiguration {
    switch selector {
    case .fixedClosed:   current = .closed
    case .fixedOpen:     current = .open
    case .fixedHalfOpen: current = .halfOpen
    case .fixedUnusual:
      // Alternate between the two unusual configurations deterministically.
      current = (current == .unusualDoubleInterval) ? .unusualOpenOctave : .unusualDoubleInterval
    case .stochastic:
      current = sampleNext(from: current, using: &rng)
    }
    return current
  }

  private func sampleNext(from state: OUCHConfiguration, using rng: inout SeededRNG) -> OUCHConfiguration {
    guard let transitions = Self.bachTransitions[state], !transitions.isEmpty else {
      return state
    }
    let total = transitions.reduce(0.0) { $0 + $1.1 }
    let pick = Double(rng.nextInt(in: 0...1_000_000)) / 1_000_000.0 * total
    var accum = 0.0
    for (target, weight) in transitions {
      accum += weight
      if pick <= accum { return target }
    }
    return transitions.last!.0
  }
}

// MARK: - Classification

/// Given three upper-voice MIDI pitches (ascending), identify their OUCH configuration.
/// Used to initialize OUCHState from an existing voicing.
func classifyOUCH(upperVoices: [Int]) -> OUCHConfiguration {
  guard upperVoices.count == 3 else { return .closed }
  let sorted = upperVoices.sorted()
  let low = sorted[0]
  let mid = sorted[1]
  let high = sorted[2]

  let lowPC = ((low % 12) + 12) % 12
  let midPC = ((mid % 12) + 12) % 12
  let highPC = ((high % 12) + 12) % 12

  let pcs = Set([lowPC, midPC, highPC])
  let span = high - low

  if pcs.count == 3 {
    // Complete triad: closed if within an octave, open otherwise.
    return span < 12 ? .closed : .open
  }

  // Two distinct pitch classes — one is doubled.
  if low == mid || mid == high {
    // Two adjacent voices at unison.
    return .unusualDoubleInterval
  }
  if lowPC == highPC && span == 12 {
    // Outer voices exactly an octave apart — halfOpen or unusualOpenOctave.
    // halfOpen: middle voice has a different pitch class AND sits between them (it always does here).
    if midPC != lowPC { return .halfOpen }
    // All three voices on same PC with outer span = 12: middle voice equals an outer voice.
    // Fall through to unusualOpenOctave.
    return .unusualOpenOctave
  }
  // Two voices an octave apart but not the outer pair — third voice is outside.
  if high - mid == 12 || mid - low == 12 {
    return .unusualOpenOctave
  }
  // Fallback: treat as halfOpen.
  return .halfOpen
}
