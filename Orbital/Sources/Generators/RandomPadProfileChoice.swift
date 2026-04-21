//
//  RandomPadProfileChoice.swift
//  Orbital
//
//  UI-facing selector over the GM pad profiles used by makeRandomPadPreset.
//

import Foundation

enum RandomPadProfileChoice: String, CaseIterable, Identifiable {
  case melody
  case piano
  case chromPerc
  case organ
  case guitar
  case bass
  case strings
  case ensemble
  case brass
  case reed
  case pipe
  case synthLead
  case synthPad
  case any

  var id: Self { self }

  var displayName: String {
    switch self {
    case .melody:    return "Melody"
    case .piano:     return "Piano"
    case .chromPerc: return "Chromatic Perc."
    case .organ:     return "Organ"
    case .guitar:    return "Guitar"
    case .bass:      return "Bass"
    case .strings:   return "Strings"
    case .ensemble:  return "Ensemble"
    case .brass:     return "Brass"
    case .reed:      return "Reed"
    case .pipe:      return "Pipe"
    case .synthLead: return "Synth Lead"
    case .synthPad:  return "Synth Pad"
    case .any:       return "Any"
    }
  }

  /// Representative GM program for the profile; nil selects the unrestricted `default` profile.
  /// .melody matches the Generator arpeggio track exactly (GM 0 + pluckedOrStruck),
  /// so auditioning with this option previews what a rendered melody line will sound like.
  var gmProgram: Int? {
    switch self {
    case .melody:    return 0
    case .piano:     return 0
    case .chromPerc: return 8
    case .organ:     return 16
    case .guitar:    return 24
    case .bass:      return 32
    case .strings:   return 40
    case .ensemble:  return 48
    case .brass:     return 56
    case .reed:      return 64
    case .pipe:      return 72
    case .synthLead: return 80
    case .synthPad:  return 88
    case .any:       return nil
    }
  }

  /// Whether this profile should layer the impulse-excited-string constraint bundle
  /// (fast attack, short decay, narrow chorus, slight stretch) on top of its GM constraints.
  var pluckedOrStruck: Bool {
    switch self {
    case .melody, .piano, .chromPerc, .guitar: return true
    default:                                   return false
    }
  }
}
