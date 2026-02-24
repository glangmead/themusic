//
//  ArrowSyntax+Parameters.swift
//  Orbital
//
//  Extracted from ArrowHandler.swift
//

import Foundation

// MARK: - Parameter Descriptor Types

/// The kind of parameter, determining its UI widget and write-through behavior.
enum ArrowParamKind: Equatable {
  case constVal
  case constOctave
  case constCent
  case envelopeAttack(envName: String)
  case envelopeDecay(envName: String)
  case envelopeSustain(envName: String)
  case envelopeRelease(envName: String)
  case oscShape(oscName: String)
  case chorusCentRadius(choruserName: String)
  case chorusNumVoices(choruserName: String)
}

/// Metadata for one editable parameter discovered by walking ArrowSyntax.
struct ArrowParamDescriptor: Identifiable {
  let id: String
  let displayName: String
  let group: String
  let kind: ArrowParamKind
  let defaultValue: CoreFloat
  let defaultShape: BasicOscillator.OscShape?
  let suggestedRange: ClosedRange<CoreFloat>
  let stepSize: CoreFloat?
}

// MARK: - ArrowSyntax Parameter Discovery

extension ArrowSyntax {
  /// Walk the syntax tree and collect descriptors for every editable parameter.
  /// Constants named "freq" are excluded (they are set per-note by the voice system).
  func parameterDescriptors() -> [ArrowParamDescriptor] {
    var descriptors: [ArrowParamDescriptor] = []
    var seenIds: Set<String> = []
    collectDescriptors(into: &descriptors, seenIds: &seenIds)
    return descriptors
  }

  private func collectDescriptors(
    into descriptors: inout [ArrowParamDescriptor],
    seenIds: inout Set<String>
  ) {
    switch self {
    case .const(let name, let val):
      guard name != "freq" else { return }
      guard seenIds.insert(name).inserted else { return }
      descriptors.append(ArrowParamDescriptor(
        id: name,
        displayName: Self.displayName(for: name),
        group: Self.groupName(for: name),
        kind: .constVal,
        defaultValue: val,
        defaultShape: nil,
        suggestedRange: Self.suggestedRange(for: name, defaultValue: val),
        stepSize: Self.suggestedStep(for: name)
      ))

    case .constOctave(let name, let val):
      guard seenIds.insert(name).inserted else { return }
      descriptors.append(ArrowParamDescriptor(
        id: name,
        displayName: Self.displayName(for: name),
        group: Self.groupName(for: name),
        kind: .constOctave,
        defaultValue: val,
        defaultShape: nil,
        suggestedRange: -5...5,
        stepSize: 1
      ))

    case .constCent(let name, let val):
      guard seenIds.insert(name).inserted else { return }
      descriptors.append(ArrowParamDescriptor(
        id: name,
        displayName: Self.displayName(for: name),
        group: Self.groupName(for: name),
        kind: .constCent,
        defaultValue: val,
        defaultShape: nil,
        suggestedRange: -500...500,
        stepSize: 1
      ))

    case .envelope(let name, let attack, let decay, let sustain, let release, _):
      let group = Self.envelopeGroupName(for: name)
      if seenIds.insert("\(name).attack").inserted {
        descriptors.append(ArrowParamDescriptor(
          id: "\(name).attack", displayName: "Attack", group: group,
          kind: .envelopeAttack(envName: name), defaultValue: attack,
          defaultShape: nil, suggestedRange: 0...5, stepSize: nil
        ))
      }
      if seenIds.insert("\(name).decay").inserted {
        descriptors.append(ArrowParamDescriptor(
          id: "\(name).decay", displayName: "Decay", group: group,
          kind: .envelopeDecay(envName: name), defaultValue: decay,
          defaultShape: nil, suggestedRange: 0...5, stepSize: nil
        ))
      }
      if seenIds.insert("\(name).sustain").inserted {
        descriptors.append(ArrowParamDescriptor(
          id: "\(name).sustain", displayName: "Sustain", group: group,
          kind: .envelopeSustain(envName: name), defaultValue: sustain,
          defaultShape: nil, suggestedRange: 0...1, stepSize: nil
        ))
      }
      if seenIds.insert("\(name).release").inserted {
        descriptors.append(ArrowParamDescriptor(
          id: "\(name).release", displayName: "Release", group: group,
          kind: .envelopeRelease(envName: name), defaultValue: release,
          defaultShape: nil, suggestedRange: 0...5, stepSize: nil
        ))
      }

    case .osc(let name, let shape, let width):
      let group = Self.oscGroupName(for: name)
      if seenIds.insert("\(name).shape").inserted {
        descriptors.append(ArrowParamDescriptor(
          id: "\(name).shape", displayName: "Shape", group: group,
          kind: .oscShape(oscName: name), defaultValue: 0,
          defaultShape: shape, suggestedRange: 0...1, stepSize: nil
        ))
      }
      width.collectDescriptors(into: &descriptors, seenIds: &seenIds)

    case .choruser(let name, _, let centRadius, let numVoices):
      let group = Self.choruserGroupName(for: name)
      if seenIds.insert("\(name).centRadius").inserted {
        descriptors.append(ArrowParamDescriptor(
          id: "\(name).centRadius", displayName: "Chorus Cents", group: group,
          kind: .chorusCentRadius(choruserName: name),
          defaultValue: CoreFloat(centRadius), defaultShape: nil,
          suggestedRange: 0...30, stepSize: 1
        ))
      }
      if seenIds.insert("\(name).numVoices").inserted {
        descriptors.append(ArrowParamDescriptor(
          id: "\(name).numVoices", displayName: "Chorus Voices", group: group,
          kind: .chorusNumVoices(choruserName: name),
          defaultValue: CoreFloat(numVoices), defaultShape: nil,
          suggestedRange: 1...12, stepSize: 1
        ))
      }

    case .lowPassFilter(_, let cutoff, let resonance):
      cutoff.collectDescriptors(into: &descriptors, seenIds: &seenIds)
      resonance.collectDescriptors(into: &descriptors, seenIds: &seenIds)

    case .compose(let arrows):
      for child in arrows {
        child.collectDescriptors(into: &descriptors, seenIds: &seenIds)
      }

    case .prod(let arrows):
      for child in arrows {
        child.collectDescriptors(into: &descriptors, seenIds: &seenIds)
      }

    case .sum(let arrows):
      for child in arrows {
        child.collectDescriptors(into: &descriptors, seenIds: &seenIds)
      }

    case .crossfade(let arrows, _, let mixPoint):
      mixPoint.collectDescriptors(into: &descriptors, seenIds: &seenIds)
      for child in arrows {
        child.collectDescriptors(into: &descriptors, seenIds: &seenIds)
      }

    case .crossfadeEqPow(let arrows, _, let mixPoint):
      mixPoint.collectDescriptors(into: &descriptors, seenIds: &seenIds)
      for child in arrows {
        child.collectDescriptors(into: &descriptors, seenIds: &seenIds)
      }

    case .reciprocalConst(let name, let val):
      guard seenIds.insert(name).inserted else { return }
      descriptors.append(ArrowParamDescriptor(
        id: name,
        displayName: Self.displayName(for: name),
        group: Self.groupName(for: name),
        kind: .constVal,
        defaultValue: val,
        defaultShape: nil,
        suggestedRange: Self.suggestedRange(for: name, defaultValue: val),
        stepSize: Self.suggestedStep(for: name)
      ))

    case .reciprocal(of: let inner):
      inner.collectDescriptors(into: &descriptors, seenIds: &seenIds)

    case .identity, .control, .rand, .exponentialRand, .noiseSmoothStep, .line,
         .eventNote, .eventVelocity, .libraryArrow, .emitterValue, .quickExpression:
      break
    }
  }

  // MARK: - Naming Helpers

  private static func displayName(for constName: String) -> String {
    let mappings: [String: String] = [
      "osc1Mix": "Mix", "osc2Mix": "Mix", "osc3Mix": "Mix",
      "osc1Width": "Pulse Width", "osc2Width": "Pulse Width", "osc3Width": "Pulse Width",
      "osc1VibWidth": "Vibrato Width", "osc2VibWidth": "Vibrato Width", "osc3VibWidth": "Vibrato Width",
      "vibratoAmp": "Amplitude", "vibratoFreq": "Frequency",
      "vibratoOscShift": "Osc Shift", "vibratoOscScale": "Osc Scale",
      "cutoff": "Cutoff", "cutoffLow": "Cutoff Low",
      "cutoffMultiplier": "Cutoff Multiplier",
      "resonance": "Resonance",
      "overallAmp": "Overall Amp", "overallAmp2": "Overall Amp 2",
    ]
    return mappings[constName] ?? constName
  }

  private static func groupName(for constName: String) -> String {
    if constName.hasPrefix("osc1") { return "Oscillator 1" }
    if constName.hasPrefix("osc2") { return "Oscillator 2" }
    if constName.hasPrefix("osc3") { return "Oscillator 3" }
    if constName.hasPrefix("vibrato") { return "Vibrato" }
    if constName.hasPrefix("cutoff") || constName == "resonance" { return "Filter" }
    if constName.hasPrefix("overall") { return "Output" }
    return "Parameters"
  }

  private static func envelopeGroupName(for envName: String) -> String {
    if envName == "ampEnv" { return "Amp Envelope" }
    if envName == "filterEnv" { return "Filter Envelope" }
    if envName == "vibratoEnv" { return "Vibrato Envelope" }
    return "\(envName) Envelope"
  }

  private static func oscGroupName(for oscName: String) -> String {
    if oscName == "osc1" { return "Oscillator 1" }
    if oscName == "osc2" { return "Oscillator 2" }
    if oscName == "osc3" { return "Oscillator 3" }
    if oscName == "vibratoOsc" { return "Vibrato" }
    return oscName
  }

  private static func choruserGroupName(for choruserName: String) -> String {
    if choruserName == "osc1Choruser" { return "Oscillator 1" }
    if choruserName == "osc2Choruser" { return "Oscillator 2" }
    if choruserName == "osc3Choruser" { return "Oscillator 3" }
    return choruserName
  }

  private static func suggestedRange(
    for name: String, defaultValue: CoreFloat
  ) -> ClosedRange<CoreFloat> {
    // Well-known parameter ranges
    let knownRanges: [String: ClosedRange<CoreFloat>] = [
      "osc1Mix": 0...1, "osc2Mix": 0...1, "osc3Mix": 0...1,
      "osc1Width": 0...1, "osc2Width": 0...1, "osc3Width": 0...1,
      "osc1VibWidth": 0...1, "osc2VibWidth": 0...1, "osc3VibWidth": 0...1,
      "vibratoAmp": 0...0.01, "vibratoFreq": 0...30,
      "vibratoOscShift": 0...1, "vibratoOscScale": 0...1,
      "cutoff": 1...20000, "cutoffLow": 0...500,
      "cutoffMultiplier": 0...20,
      "resonance": 0.1...15,
      "overallAmp": 0...2, "overallAmp2": 0...2,
    ]
    if let range = knownRanges[name] { return range }
    // Fallback: infer from magnitude
    let mag = abs(defaultValue)
    if mag < 0.01 { return -1...1 }
    if mag < 1 { return 0...2 }
    if mag < 10 { return 0...(mag * 4) }
    return 0...(mag * 2)
  }

  private static func suggestedStep(for name: String) -> CoreFloat? {
    let steppedParams: Set<String> = [
      "cutoff", "cutoffLow",
    ]
    if steppedParams.contains(name) { return 1 }
    return nil
  }
}
