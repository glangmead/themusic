//
//  ArrowSeedMap.swift
//  Orbital
//
//  Walks a compiled Arrow graph in deterministic DFS order, assigns each
//  random-consuming node a stable structural path identifier, and derives a
//  64-bit per-node sub-seed from the song seed via SplitMix64.
//
//  Used by Preset/SpatialPreset right after compilation to feed
//  Arrow11.resetRandomRecursive(seedMap:) so render-thread random consumers
//  produce deterministic streams from the same song seed across runs.
//
//  Hashing uses hand-rolled FNV-1a (in Fnv1a64.swift), NEVER Swift's built-in
//  Hasher, because Hasher is randomized per process and would break
//  reproducibility across launches.
//

import Foundation

enum ArrowSeedMap {
  /// Walk the compiled Arrow graph in deterministic DFS order. For every node
  /// where `consumesRandomness == true`, derive a 64-bit sub-seed from
  /// `songSeed XOR fnv1a64(structuralPath)` via one SplitMix64 step and store
  /// it under the node's `ObjectIdentifier`.
  static func build(root: Arrow11, songSeed: UInt64) -> [ObjectIdentifier: UInt64] {
    var map: [ObjectIdentifier: UInt64] = [:]
    var pathStack: [String] = []
    walk(node: root, songSeed: songSeed, pathStack: &pathStack, map: &map)
    return map
  }

  private static func walk(
    node: Arrow11,
    songSeed: UInt64,
    pathStack: inout [String],
    map: inout [ObjectIdentifier: UInt64]
  ) {
    pathStack.append(node.pathSegment)
    defer { pathStack.removeLast() }

    if node.consumesRandomness {
      let pathHash = fnv1a64(pathStack.joined(separator: "/"))
      var splitter = SplitMix64(seed: songSeed ^ pathHash)
      map[ObjectIdentifier(node)] = splitter.next()
    }

    if let inner = node.innerArr {
      pathStack.append("inner")
      walk(node: inner, songSeed: songSeed, pathStack: &pathStack, map: &map)
      pathStack.removeLast()
    }
    for (i, child) in node.innerArrs.enumerated() {
      pathStack.append("[\(i)]")
      walk(node: child, songSeed: songSeed, pathStack: &pathStack, map: &map)
      pathStack.removeLast()
    }
    for (label, child) in node.extraRandomChildren {
      pathStack.append(label)
      walk(node: child, songSeed: songSeed, pathStack: &pathStack, map: &map)
      pathStack.removeLast()
    }
  }
}
