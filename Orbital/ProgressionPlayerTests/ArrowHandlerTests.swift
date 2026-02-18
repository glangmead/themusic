//
//  ArrowHandlerTests.swift
//  ProgressionPlayerTests
//
//  Tests for ArrowHandler: parameter descriptors, write-through, readFromHandles.
//

import Testing
import Foundation
@testable import ProgressionPlayer

// MARK: - Helpers

/// Build an ArrowHandler and attach compiled handles, mirroring what SyntacticSynth does.
@MainActor
private func buildHandlerWithHandles(
  filename: String = "5th_cluedo.json",
  presetCount: Int = 3,
  voicesPerPreset: Int = 1
) throws -> (handler: ArrowHandler, handles: ArrowWithHandles) {
  let syntax = try loadPresetSyntax(filename)
  guard let arrowSyntax = syntax.arrow else {
    throw PresetLoadError.fileNotFound("No arrow in \(filename)")
  }

  // Build presets and aggregate handles
  var presets = [Preset]()
  for _ in 0..<presetCount {
    let preset = Preset(arrowSyntax: arrowSyntax, numVoices: voicesPerPreset, initEffects: false)
    presets.append(preset)
  }
  let aggregated = ArrowWithHandles(ArrowIdentity())
  for preset in presets {
    if let h = preset.handles {
      let _ = aggregated.withMergeDictsFromArrow(h)
    }
  }

  let handler = ArrowHandler(syntax: arrowSyntax)
  handler.attachHandles(aggregated)
  return (handler, aggregated)
}

// MARK: - Parameter Descriptor Tests

@Suite("ArrowHandler Parameter Descriptors", .serialized)
@MainActor
struct ArrowHandlerDescriptorTests {

  @Test("5th_cluedo descriptors include osc shapes, envelopes, and chorusers")
  func cluedoDescriptors() throws {
    let syntax = try loadPresetSyntax("5th_cluedo.json")
    let descs = syntax.arrow!.parameterDescriptors()

    let ids = Set(descs.map(\.id))

    // Osc shapes
    #expect(ids.contains("osc1.shape"))
    #expect(ids.contains("osc2.shape"))
    #expect(ids.contains("osc3.shape"))

    // Amp envelope
    #expect(ids.contains("ampEnv.attack"))
    #expect(ids.contains("ampEnv.decay"))
    #expect(ids.contains("ampEnv.sustain"))
    #expect(ids.contains("ampEnv.release"))

    // Filter envelope
    #expect(ids.contains("filterEnv.attack"))

    // Oscillator mixes
    #expect(ids.contains("osc1Mix"))
    #expect(ids.contains("osc2Mix"))
    #expect(ids.contains("osc3Mix"))

    // Choruser params
    #expect(ids.contains("osc1Choruser.centRadius"))
    #expect(ids.contains("osc1Choruser.numVoices"))

    // freq should be excluded
    #expect(!ids.contains("freq"))
  }

  @Test("auroraBorealis descriptors include crossfade-specific params")
  func auroraDescriptors() throws {
    let syntax = try loadPresetSyntax("auroraBorealis.json")
    let descs = syntax.arrow!.parameterDescriptors()
    let ids = Set(descs.map(\.id))

    #expect(ids.contains("osc1Mix"))
    #expect(ids.contains("ampEnv.attack"))
    #expect(!ids.contains("freq"))
  }

  @Test("No duplicate descriptor IDs")
  func noDuplicateIds() throws {
    let syntax = try loadPresetSyntax("5th_cluedo.json")
    let descs = syntax.arrow!.parameterDescriptors()
    let ids = descs.map(\.id)
    #expect(ids.count == Set(ids).count, "Found duplicate descriptor IDs")
  }

  @Test("Descriptors are grouped correctly")
  func descriptorGrouping() throws {
    let syntax = try loadPresetSyntax("5th_cluedo.json")
    let handler = ArrowHandler(syntax: syntax.arrow!)
    let groups = handler.groupedDescriptors()
    let groupNames = groups.map(\.0)

    #expect(groupNames.contains("Oscillator 1"))
    #expect(groupNames.contains("Amp Envelope"))
  }

  @Test("Shape descriptors have non-nil defaultShape")
  func shapeDescriptorDefaults() throws {
    let syntax = try loadPresetSyntax("5th_cluedo.json")
    let descs = syntax.arrow!.parameterDescriptors()
    let shapeDescs = descs.filter { if case .oscShape = $0.kind { return true } else { return false } }

    #expect(!shapeDescs.isEmpty)
    for desc in shapeDescs {
      #expect(desc.defaultShape != nil, "Shape descriptor \(desc.id) should have a defaultShape")
    }
  }
}

// MARK: - Write-Through Tests

@Suite("ArrowHandler Write-Through", .serialized)
@MainActor
struct ArrowHandlerWriteThroughTests {

  @Test("setFloat propagates to all handle instances for a const")
  func setFloatConst() throws {
    let (handler, handles) = try buildHandlerWithHandles()
    let newValue: CoreFloat = 0.42

    handler.setFloat("osc1Mix", to: newValue)

    // Verify storage
    #expect(handler.floatValues["osc1Mix"] == newValue)

    // Verify all handle instances got the value
    let consts = handles.namedConsts["osc1Mix"]!
    for c in consts {
      #expect(c.val == newValue, "Handle const osc1Mix should be \(newValue), got \(c.val)")
    }
  }

  @Test("setFloat propagates envelope attack to all ADSR instances")
  func setFloatEnvelopeAttack() throws {
    let (handler, handles) = try buildHandlerWithHandles()
    let newValue: CoreFloat = 1.75

    handler.setFloat("ampEnv.attack", to: newValue)

    #expect(handler.floatValues["ampEnv.attack"] == newValue)

    let envs = handles.namedADSREnvelopes["ampEnv"]!
    for env in envs {
      #expect(env.env.attackTime == newValue)
    }
  }

  @Test("setFloat propagates choruser centRadius to all instances")
  func setFloatChorusCentRadius() throws {
    let (handler, handles) = try buildHandlerWithHandles()

    handler.setFloat("osc1Choruser.centRadius", to: 15)

    let chorusers = handles.namedChorusers["osc1Choruser"]!
    for ch in chorusers {
      #expect(ch.chorusCentRadius == 15)
    }
  }

  @Test("setShape propagates to all osc instances")
  func setShapeOsc() throws {
    let (handler, handles) = try buildHandlerWithHandles()

    handler.setShape("osc1.shape", to: .triangle)

    #expect(handler.shapeValues["osc1.shape"] == .triangle)

    let oscs = handles.namedBasicOscs["osc1"]!
    for osc in oscs {
      #expect(osc.shape == .triangle)
    }
  }
}

// MARK: - ReadFromHandles Tests

@Suite("ArrowHandler ReadFromHandles", .serialized)
@MainActor
struct ArrowHandlerReadFromHandlesTests {

  @Test("readFromHandles populates float values from compiled handles")
  func readFloats() throws {
    let (handler, handles) = try buildHandlerWithHandles()

    // Directly mutate a handle to simulate DSP-side changes
    let osc1MixConsts = handles.namedConsts["osc1Mix"]!
    for c in osc1MixConsts {
      c.val = 0.777
    }

    handler.readFromHandles()

    #expect(handler.floatValues["osc1Mix"] == 0.777)
  }

  @Test("readFromHandles populates shape values from compiled handles")
  func readShapes() throws {
    let (handler, handles) = try buildHandlerWithHandles()

    let oscs = handles.namedBasicOscs["osc1"]!
    for osc in oscs {
      osc.shape = .square
    }

    handler.readFromHandles()

    #expect(handler.shapeValues["osc1.shape"] == .square)
  }

  @Test("Initial attachment reads correct values from preset defaults")
  func initialAttachmentReadsDefaults() throws {
    let syntax = try loadPresetSyntax("5th_cluedo.json")
    let arrowSyntax = syntax.arrow!

    let preset = Preset(arrowSyntax: arrowSyntax, numVoices: 1, initEffects: false)
    let handles = ArrowWithHandles(ArrowIdentity())
    if let h = preset.handles {
      let _ = handles.withMergeDictsFromArrow(h)
    }

    let handler = ArrowHandler(syntax: arrowSyntax)
    handler.attachHandles(handles)

    // After attachment, values should match what the compiled preset has
    if let firstConst = handles.namedConsts["osc1Mix"]?.first {
      #expect(handler.floatValues["osc1Mix"] == firstConst.val)
    }
    if let firstOsc = handles.namedBasicOscs["osc1"]?.first {
      #expect(handler.shapeValues["osc1.shape"] == firstOsc.shape)
    }
  }
}
