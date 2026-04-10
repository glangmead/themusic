//
//  Fnv1a64.swift
//  Orbital
//
//  64-bit FNV-1a string hash. Stable across platforms and processes — unlike
//  Swift's built-in `Hasher`, which is randomized per process. Used for
//  deriving per-Arrow-node sub-seeds from path strings; do NOT replace with
//  `Hasher.combine` because that breaks reproducibility across launches.
//

import Foundation

func fnv1a64(_ s: String) -> UInt64 {
  var hash: UInt64 = 0xcbf2_9ce4_8422_2325
  for byte in s.utf8 {
    hash ^= UInt64(byte)
    hash &*= 0x0000_0100_0000_01b3
  }
  return hash
}
