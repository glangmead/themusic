//
//  PADSynthTypes.swift
//  Orbital
//

import Foundation

// MARK: - Parameter Types

enum PADBaseShape: String, CaseIterable, Identifiable, Codable {
  case oneOverN = "1/n"
  case oneOverSqrtN = "1/√n"
  case oddHarmonics = "Odd harmonics"
  case equal = "Equal"
  case oneOverNSquared = "1/n²"

  var id: String { rawValue }

  func amplitude(harmonic nh: Int) -> CoreFloat {
    let n = CoreFloat(nh)
    switch self {
    case .oneOverN: return 1.0 / n
    case .oneOverSqrtN: return 1.0 / sqrt(n)
    case .oddHarmonics: return (nh % 2 == 1) ? 1.0 / n : 0.0
    case .equal: return 1.0
    case .oneOverNSquared: return 1.0 / (n * n)
    }
  }
}

enum PADProfileShape: String, CaseIterable, Identifiable, Codable {
  case gaussian = "Gaussian"
  case flat = "Flat"
  case detuned = "Detuned"
  case narrow = "Narrow"

  var id: String { rawValue }
}

enum PADOvertonePreset: String, CaseIterable, Identifiable {
  case harmonic = "Harmonic"
  case piano = "Piano"
  case bell = "Bell"
  case metallic = "Metallic"
  case glass = "Glass"

  var id: String { rawValue }

  var stretchValue: CoreFloat {
    switch self {
    case .harmonic: return 1.0
    case .piano: return 1.01
    case .bell: return 1.15
    case .metallic: return 1.3
    case .glass: return 0.95
    }
  }
}
