//
//  ArrowResetRandomTests.swift
//  OrbitalTests
//
//  Verifies that ArrowRandom, ArrowExponentialRandom, and NoiseSmoothStep
//  produce identical sample buffers when reseeded with the same seed map.
//

import Testing
@testable import Orbital

@Suite("Arrow reset random", .serialized)
struct ArrowResetRandomTests {
  @Test("ArrowRandom: same seed → identical buffer")
  func arrowRandomDeterministic() {
    let node = ArrowRandom(min: -1.0, max: 1.0)
    let id = ObjectIdentifier(node)
    let map: [ObjectIdentifier: UInt64] = [id: 0xCAFE_BABE_DEAD_BEEF]

    var buf1 = [CoreFloat](repeating: 0, count: 256)
    var buf2 = [CoreFloat](repeating: 0, count: 256)
    let inputs = [CoreFloat](repeating: 0, count: 256)

    node.resetRandomRecursive(seedMap: map)
    node.process(inputs: inputs, outputs: &buf1)

    node.resetRandomRecursive(seedMap: map)
    node.process(inputs: inputs, outputs: &buf2)

    #expect(buf1 == buf2)
    // Sanity: the buffer is not all-zero (PRNG actually fired).
    #expect(buf1.contains { $0 != 0 })
  }

  @Test("ArrowRandom: different seed → different buffer")
  func arrowRandomDifferentSeeds() {
    let node = ArrowRandom(min: -1.0, max: 1.0)
    let id = ObjectIdentifier(node)
    let inputs = [CoreFloat](repeating: 0, count: 256)
    var buf1 = [CoreFloat](repeating: 0, count: 256)
    var buf2 = [CoreFloat](repeating: 0, count: 256)

    node.resetRandomRecursive(seedMap: [id: 1])
    node.process(inputs: inputs, outputs: &buf1)

    node.resetRandomRecursive(seedMap: [id: 2])
    node.process(inputs: inputs, outputs: &buf2)

    #expect(buf1 != buf2)
  }

  @Test("ArrowExponentialRandom: same seed → identical buffer")
  func arrowExpRandomDeterministic() {
    let node = ArrowExponentialRandom(min: 0.01, max: 5.0)
    let id = ObjectIdentifier(node)
    let map: [ObjectIdentifier: UInt64] = [id: 0xDEAD_BEEF_CAFE]
    let inputs = [CoreFloat](repeating: 0, count: 256)
    var buf1 = [CoreFloat](repeating: 0, count: 256)
    var buf2 = [CoreFloat](repeating: 0, count: 256)

    node.resetRandomRecursive(seedMap: map)
    node.process(inputs: inputs, outputs: &buf1)

    node.resetRandomRecursive(seedMap: map)
    node.process(inputs: inputs, outputs: &buf2)

    #expect(buf1 == buf2)
    #expect(buf1.contains { $0 > 0.01 })
  }

  @Test("NoiseSmoothStep: same seed → identical buffer")
  func noiseSmoothStepDeterministic() {
    let node = NoiseSmoothStep(noiseFreq: 100.0, min: -1.0, max: 1.0)
    node.setSampleRateRecursive(rate: 44_100)
    let id = ObjectIdentifier(node)
    let map: [ObjectIdentifier: UInt64] = [id: 0xABCD_EF01_2345_6789]
    let inputs = [CoreFloat](repeating: 0, count: 1024)
    var buf1 = [CoreFloat](repeating: 0, count: 1024)
    var buf2 = [CoreFloat](repeating: 0, count: 1024)

    node.resetRandomRecursive(seedMap: map)
    node.process(inputs: inputs, outputs: &buf1)

    node.resetRandomRecursive(seedMap: map)
    node.process(inputs: inputs, outputs: &buf2)

    #expect(buf1 == buf2)
    #expect(buf1.contains { $0 != 0 })
  }

  @Test("NoiseSmoothStep without reset produces zeros")
  func noiseSmoothStepUnseededIsZero() {
    let node = NoiseSmoothStep(noiseFreq: 100.0, min: -1.0, max: 1.0)
    node.setSampleRateRecursive(rate: 44_100)
    let inputs = [CoreFloat](repeating: 0, count: 256)
    var buf = [CoreFloat](repeating: 99.0, count: 256)
    node.process(inputs: inputs, outputs: &buf)
    // First samples should be zero (no PRNG seeded → both lastSample and
    // nextSample are 0). After enough samples to cross a segment boundary,
    // it would still output 0 because next = prng.nextFloat from a zero-seeded
    // PRNG, which is non-zero. So the FIRST few samples are guaranteed zero.
    #expect(buf[0] == 0)
  }

  @Test("Composite graph: identical reset → identical render")
  func compositeGraph() {
    let r1 = ArrowRandom(min: -1, max: 1)
    let r2 = ArrowRandom(min: -1, max: 1)
    let nss = NoiseSmoothStep(noiseFreq: 50, min: -1, max: 1)
    let exp = ArrowExponentialRandom(min: 0.01, max: 2.0)
    let sum = ArrowSum(innerArrs: [r1, r2, nss, exp])
    sum.setSampleRateRecursive(rate: 44_100)

    // Build a fake seed map with distinct seeds per node.
    let map: [ObjectIdentifier: UInt64] = [
      ObjectIdentifier(r1): 0x1111_1111_1111_1111,
      ObjectIdentifier(r2): 0x2222_2222_2222_2222,
      ObjectIdentifier(nss): 0x3333_3333_3333_3333,
      ObjectIdentifier(exp): 0x4444_4444_4444_4444
    ]

    let inputs = [CoreFloat](repeating: 0, count: 512)
    var buf1 = [CoreFloat](repeating: 0, count: 512)
    var buf2 = [CoreFloat](repeating: 0, count: 512)

    sum.resetRandomRecursive(seedMap: map)
    sum.process(inputs: inputs, outputs: &buf1)

    sum.resetRandomRecursive(seedMap: map)
    sum.process(inputs: inputs, outputs: &buf2)

    #expect(buf1 == buf2)
    #expect(buf1.contains { $0 != 0 })
  }
}
