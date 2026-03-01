//
//  ArrowSyntax+Compile.swift
//  Orbital
//
//  Runtime compilation and tree operations for ArrowSyntax.
//  Extracted from ArrowSyntax.swift.
//

import Foundation

// MARK: - ArrowSyntax Compilation & Tree Operations

extension ArrowSyntax {

  // see https://www.compilenrun.com/docs/language/swift/swift-enumerations/swift-recursive-enumerations/
  // swiftlint:disable:next cyclomatic_complexity
  func compile(library: [String: ArrowSyntax] = [:]) -> ArrowWithHandles {
    if !library.isEmpty {
      return resolveLibrary(library).compile()
    }
    switch self {
    case .rand(let min, let max):
      let rand = ArrowRandom(min: min, max: max)
      return ArrowWithHandles(rand)
    case .exponentialRand(let min, let max):
      let expRand = ArrowExponentialRandom(min: min, max: max)
      return ArrowWithHandles(expRand)
    case .noiseSmoothStep(let noiseFreq, let min, let max):
      let noise = NoiseSmoothStep(noiseFreq: noiseFreq, min: min, max: max)
      return ArrowWithHandles(noise)
    case .line(let duration, let min, let max):
      let line = ArrowLine(start: min, end: max, duration: duration)
      return ArrowWithHandles(line)
    case .compose(let specs):
      // it seems natural to me for the chain to be listed from innermost to outermost (first-to-last)
      let arrows = specs.map({$0.compile()})
      var composition: ArrowWithHandles?
      for arrow in arrows {
        arrow.wrappedArrow.innerArr = composition
        if composition != nil {
          _ = arrow.withMergeDictsFromArrow(composition!) // provide each step of composition with all the handles
        }
        composition = arrow
      }
      return composition!
    case .osc(let oscName, let oscShape, let widthArr):
      let osc = BasicOscillator(shape: oscShape, widthArr: widthArr.compile())
      let arr = ArrowWithHandles(osc)
      arr.namedBasicOscs[oscName] = [osc]
      return arr
    case .control:
      return ArrowWithHandles(ControlArrow11())
    case .identity:
      return ArrowWithHandles(ArrowIdentity())
    case .prod(let arrows):
      let lowerArrs = arrows.map({$0.compile()})
      return ArrowWithHandles(
        ArrowProd(
          innerArrs: ContiguousArray<Arrow11>(lowerArrs)
        )).withMergeDictsFromArrows(lowerArrs)
    case .sum(let arrows):
      let lowerArrs = arrows.map({$0.compile()})
      return ArrowWithHandles(
        ArrowSum(
          innerArrs: lowerArrs
        )
      ).withMergeDictsFromArrows(lowerArrs)
    case .crossfade(let arrows, let name, let mixPointArr):
      let lowerArrs = arrows.map({$0.compile()})
      let arr = ArrowCrossfade(
        innerArrs: lowerArrs,
        mixPointArr: mixPointArr.compile()
      )
      let arrH = ArrowWithHandles(arr).withMergeDictsFromArrows(lowerArrs)
      if var crossfaders = arrH.namedCrossfaders[name] {
        crossfaders.append(arr)
      } else {
        arrH.namedCrossfaders[name] = [arr]
      }
      return arrH
    case .crossfadeEqPow(let arrows, let name, let mixPointArr):
      let lowerArrs = arrows.map({$0.compile()})
      let arr = ArrowEqualPowerCrossfade(
        innerArrs: lowerArrs,
        mixPointArr: mixPointArr.compile()
      )
      let arrH = ArrowWithHandles(arr).withMergeDictsFromArrows(lowerArrs)
      if var crossfaders = arrH.namedCrossfadersEqPow[name] {
        crossfaders.append(arr)
      } else {
        arrH.namedCrossfadersEqPow[name] = [arr]
      }
      return arrH
    case .const(let name, let val):
      let arr = ArrowConst(value: val) // separate copy, even if same name as a node elsewhere
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedConsts[name] = [arr]
      return handleArr
    case .constOctave(let name, let val):
      let arr = ArrowConstOctave(value: val) // separate copy, even if same name as a node elsewhere
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedConsts[name] = [arr]
      return handleArr
    case .constCent(let name, let val):
      let arr = ArrowConstCent(value: val) // separate copy, even if same name as a node elsewhere
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedConsts[name] = [arr]
      return handleArr
    case .lowPassFilter(let name, let cutoff, let resonance):
      let cutoffArrow = cutoff.compile()
      let resonanceArrow = resonance.compile()
      let arr = LowPassFilter2(
        cutoff: cutoffArrow,
        resonance: resonanceArrow
      )
      let handleArr = ArrowWithHandles(arr)
        .withMergeDictsFromArrow(cutoffArrow)
        .withMergeDictsFromArrow(resonanceArrow)
      if var filters = handleArr.namedLowPassFilter[name] {
        filters.append(arr)
      } else {
        handleArr.namedLowPassFilter[name] = [arr]
      }
      return handleArr

    case .combFilter(let name, let frequency, let feedback):
      let frequencyArrow = frequency.compile()
      let feedbackArrow = feedback.compile()
      let arr = CombFilter(
        frequency: frequencyArrow,
        feedback: feedbackArrow
      )
      let handleArr = ArrowWithHandles(arr)
        .withMergeDictsFromArrow(frequencyArrow)
        .withMergeDictsFromArrow(feedbackArrow)
      handleArr.namedCombFilters[name] = [arr]
      return handleArr

    case .choruser(let name, let valueToChorus, let chorusCentRadius, let chorusNumVoices):
      let choruser = Choruser(
        chorusCentRadius: chorusCentRadius,
        chorusNumVoices: chorusNumVoices,
        valueToChorus: valueToChorus
      )
      let handleArr = ArrowWithHandles(choruser)
      if var chorusers = handleArr.namedChorusers[name] {
        chorusers.append(choruser)
      } else {
        handleArr.namedChorusers[name] = [choruser]
      }
      return handleArr

    case .envelope(let name, let attack, let decay, let sustain, let release, let scale):
      let env = ADSR(envelope: EnvelopeData(
        attackTime: attack,
        decayTime: decay,
        sustainLevel: sustain,
        releaseTime: release,
        scale: scale
      ))
      let handleArr = ArrowWithHandles(env.asControl())
      if var envs = handleArr.namedADSREnvelopes[name] {
        envs.append(env)
      } else {
        handleArr.namedADSREnvelopes[name] = [env]
      }
      return handleArr

    case .reciprocalConst(let name, let val):
      let arr = ArrowConstReciprocal(value: val)
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedConsts[name] = [arr]
      return handleArr

    case .reciprocal(of: let inner):
      let innerCompiled = inner.compile()
      let arr = ArrowReciprocal()
      arr.innerArr = innerCompiled.wrappedArrow
      return ArrowWithHandles(arr).withMergeDictsFromArrow(innerCompiled)

    case .eventNote:
      let arr = EventUsingArrow(ofEvent: { event, _ in
        CoreFloat(event.notes[0].note)
      })
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedEventUsing[""] = [arr]
      return handleArr

    case .eventVelocity:
      let arr = EventUsingArrow(ofEvent: { event, _ in
        CoreFloat(event.notes[0].velocity) / 127.0
      })
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedEventUsing[""] = [arr]
      return handleArr

    case .libraryArrow(let name):
      fatalError("libraryArrow '\(name)' was not resolved — call resolveLibrary() before compile()")

    case .emitterValue(let name):
      let arr = ArrowConst(value: 0)
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedEmitterValues[name] = [arr]
      return handleArr

    case .quickExpression(let expr):
      // Parse the expression into an ArrowSyntax tree, then compile that tree.
      // If the expression is invalid, fall back to a zero constant so
      // playback doesn't crash — the UI validates before saving.
      guard let parsed = try? QuickParser.parse(expr) else {
        print("QuickParser: failed to parse '\(expr)', falling back to 0")
        return ArrowSyntax.const(name: "_error", val: 0).compile()
      }
      return parsed.compile()
    }
  }

  /// Replace every `.libraryArrow` reference with its definition from the
  /// library dictionary. The dictionary values should already be resolved
  /// (no remaining `.libraryArrow` nodes), which is guaranteed when the
  /// caller builds the dict in order and resolves each entry against the
  /// dict-so-far.
  /// Applies `transform` to every ArrowSyntax child, returning a structurally
  /// identical node with transformed children. Leaf cases return self unchanged.
  func mapChildren(_ transform: (ArrowSyntax) -> ArrowSyntax) -> ArrowSyntax {
    switch self {
    case .prod(let arrows):
      return .prod(of: arrows.map(transform))
    case .compose(let arrows):
      return .compose(arrows: arrows.map(transform))
    case .sum(let arrows):
      return .sum(of: arrows.map(transform))
    case .crossfade(let arrows, let name, let mixPoint):
      return .crossfade(of: arrows.map(transform), name: name, mixPoint: transform(mixPoint))
    case .crossfadeEqPow(let arrows, let name, let mixPoint):
      return .crossfadeEqPow(of: arrows.map(transform), name: name, mixPoint: transform(mixPoint))
    case .lowPassFilter(let name, let cutoff, let resonance):
      return .lowPassFilter(name: name, cutoff: transform(cutoff), resonance: transform(resonance))
    case .combFilter(let name, let frequency, let feedback):
      return .combFilter(name: name, frequency: transform(frequency), feedback: transform(feedback))
    case .osc(let name, let shape, let width):
      return .osc(name: name, shape: shape, width: transform(width))
    case .reciprocal(let inner):
      return .reciprocal(of: transform(inner))
    case .const, .constOctave, .constCent, .reciprocalConst,
         .identity, .control, .envelope, .choruser,
         .noiseSmoothStep, .rand, .exponentialRand, .line,
         .eventNote, .eventVelocity, .libraryArrow, .emitterValue,
         .quickExpression:
      return self
    }
  }

  // This pattern is going to *copy* each referenced library arrow whenever it is asked for later
  // In future we may want to make the compiled arrow into a DAG.
  // But that will require more design around how to handle a node being called twice by other nodes.
  func resolveLibrary(_ library: [String: ArrowSyntax]) -> ArrowSyntax {
    switch self {
    case .libraryArrow(let name):
      guard let definition = library[name] else {
        fatalError("Unknown library arrow '\(name)'. Available: \(library.keys.sorted())")
      }
      return definition
    default:
      return mapChildren { $0.resolveLibrary(library) }
    }
  }
}
