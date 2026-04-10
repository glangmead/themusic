//
//  ArrowSeedMapTests.swift
//  OrbitalTests
//

import Testing
@testable import Orbital

@Suite("ArrowSeedMap", .serialized)
struct ArrowSeedMapTests {
  @Test("Builds entries only for random consumers")
  func entriesForRandomConsumersOnly() {
    let r = ArrowRandom(min: -1, max: 1)
    let c = ArrowConst(value: 0.5)  // not a random consumer
    let i = ArrowIdentity()         // not a random consumer
    let sum = ArrowSum(innerArrs: [r, c, i])

    let map = ArrowSeedMap.build(root: sum, songSeed: 0xDEAD_BEEF)
    #expect(map.count == 1)
    #expect(map[ObjectIdentifier(r)] != nil)
    #expect(map[ObjectIdentifier(c)] == nil)
    #expect(map[ObjectIdentifier(i)] == nil)
  }

  @Test("Sibling random consumers get distinct seeds")
  func siblingsDistinct() {
    let r1 = ArrowRandom(min: -1, max: 1)
    let r2 = ArrowRandom(min: -1, max: 1)
    let sum = ArrowSum(innerArrs: [r1, r2])

    let map = ArrowSeedMap.build(root: sum, songSeed: 0xCAFE_BABE)
    let seed1 = map[ObjectIdentifier(r1)]
    let seed2 = map[ObjectIdentifier(r2)]
    #expect(seed1 != nil)
    #expect(seed2 != nil)
    #expect(seed1 != seed2)
  }

  @Test("Same structural tree, two compilations, identical seed multiset")
  func sameTreeSameValues() {
    func makeTree() -> Arrow11 {
      let r = ArrowRandom(min: -1, max: 1)
      let nss = NoiseSmoothStep(noiseFreq: 50, min: -1, max: 1)
      let exp = ArrowExponentialRandom(min: 0.01, max: 1.0)
      return ArrowSum(innerArrs: [r, nss, exp])
    }
    let songSeed: UInt64 = 0xABCD_EF01
    let mapA = ArrowSeedMap.build(root: makeTree(), songSeed: songSeed)
    let mapB = ArrowSeedMap.build(root: makeTree(), songSeed: songSeed)
    #expect(mapA.count == mapB.count)
    let valuesA = Set(mapA.values)
    let valuesB = Set(mapB.values)
    #expect(valuesA == valuesB)
  }

  @Test("Different songSeed → different per-node seeds")
  func differentSongSeedsDifferentValues() {
    let r1 = ArrowRandom(min: -1, max: 1)
    let r2 = ArrowRandom(min: -1, max: 1)
    let sum = ArrowSum(innerArrs: [r1, r2])

    let mapA = ArrowSeedMap.build(root: sum, songSeed: 1)
    let mapB = ArrowSeedMap.build(root: sum, songSeed: 999_999)
    #expect(mapA[ObjectIdentifier(r1)] != mapB[ObjectIdentifier(r1)])
    #expect(mapA[ObjectIdentifier(r2)] != mapB[ObjectIdentifier(r2)])
  }

  @Test("Walker descends into ArrowEqualPowerCrossfade.mixPointArr via extraRandomChildren")
  func walkerCoversMixPointArr() {
    let r1 = ArrowRandom(min: -1, max: 1)
    let r2 = ArrowRandom(min: -1, max: 1)
    let mixPointRand = ArrowRandom(min: 0, max: 1)
    let crossfade = ArrowEqualPowerCrossfade(
      innerArrs: [r1, r2],
      mixPointArr: mixPointRand
    )

    let map = ArrowSeedMap.build(root: crossfade, songSeed: 42)
    // All three random consumers must get distinct seeds: r1 and r2 via the
    // innerArrs path, mixPointRand via the extraRandomChildren hook on
    // ArrowEqualPowerCrossfade.
    #expect(map[ObjectIdentifier(r1)] != nil)
    #expect(map[ObjectIdentifier(r2)] != nil)
    #expect(map[ObjectIdentifier(mixPointRand)] != nil)
    let allSeeds = Set([map[ObjectIdentifier(r1)]!,
                        map[ObjectIdentifier(r2)]!,
                        map[ObjectIdentifier(mixPointRand)]!])
    #expect(allSeeds.count == 3)
  }
}
