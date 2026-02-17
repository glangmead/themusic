//
//  PatternEditorPreview.swift
//  ProgressionPlayer
//
//  Pattern Editor UI mockup with Liquid Glass design language.
//  This file contains renderable SwiftUI previews demonstrating
//  the key UI components of the Pattern Editor.
//
//  Requires iOS 26+ for Liquid Glass APIs.
//

import Charts
import SwiftUI

// MARK: - Data Models for the Editor

/// Note name lookup table, extracted to avoid type-checker issues in preview thunks.
private let kNoteNames: [String] = {
  ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
}()

/// A single note in the piano roll, suitable for editing.
struct EditableNote: Identifiable {
  let id = UUID()
  var midiNote: Int        // 0-127
  var startBeat: Double    // in beats from beginning
  var durationBeats: Double
  var velocity: Int        // 0-127
  var isSelected: Bool = false
  
  var noteName: String {
    let octave = (midiNote / 12) - 1
    return "\(kNoteNames[midiNote % 12])\(octave)"
  }
}

/// Time signature representation.
enum PatternTimeSignature: String, CaseIterable, Identifiable {
  case fourFour = "4/4"
  case threeFour = "3/4"
  case sixEight = "6/8"
  case fiveFour = "5/4"
  
  var id: String { rawValue }
  var beatsPerBar: Int {
    switch self {
    case .fourFour: 4
    case .threeFour: 3
    case .sixEight: 6
    case .fiveFour: 5
    }
  }
}

/// Configuration for the editable pattern.
struct EditablePattern {
  var name: String = "Pattern 1"
  var tempo: Double = 120
  var timeSignature: PatternTimeSignature = .fourFour
  var notes: [EditableNote] = []
  var modulatorKeys: [String] = ["overallAmp", "vibratoFreq", "overallCentDetune"]
  var sustainMin: Double = 5.0
  var sustainMax: Double = 10.0
  var gapMin: Double = 5.0
  var gapMax: Double = 10.0
  var totalBars: Int = 8
}

// MARK: - Sample Data

extension EditablePattern {
  static var samplePattern: EditablePattern {
    var pattern = EditablePattern()
    pattern.notes = [
      EditableNote(midiNote: 72, startBeat: 0, durationBeats: 2, velocity: 100),
      EditableNote(midiNote: 67, startBeat: 0.5, durationBeats: 1.5, velocity: 80),
      EditableNote(midiNote: 64, startBeat: 2, durationBeats: 3, velocity: 110),
      EditableNote(midiNote: 60, startBeat: 4, durationBeats: 2, velocity: 90),
      EditableNote(midiNote: 69, startBeat: 6, durationBeats: 1, velocity: 70),
      EditableNote(midiNote: 71, startBeat: 8, durationBeats: 2, velocity: 100),
      EditableNote(midiNote: 76, startBeat: 10, durationBeats: 1, velocity: 85),
      EditableNote(midiNote: 74, startBeat: 12, durationBeats: 4, velocity: 95),
      EditableNote(midiNote: 65, startBeat: 14, durationBeats: 2, velocity: 75),
      EditableNote(midiNote: 62, startBeat: 16, durationBeats: 3, velocity: 105),
      EditableNote(midiNote: 79, startBeat: 20, durationBeats: 1.5, velocity: 60),
      EditableNote(midiNote: 55, startBeat: 22, durationBeats: 4, velocity: 100),
      EditableNote(midiNote: 67, startBeat: 24, durationBeats: 2, velocity: 90),
      EditableNote(midiNote: 72, startBeat: 28, durationBeats: 3, velocity: 110),
      EditableNote(midiNote: 60, startBeat: 30, durationBeats: 2, velocity: 80),
    ]
    return pattern
  }
}

// MARK: - Theme Extensions for Pattern Editor

extension Color {
  /// Note color based on velocity (brighter = louder).
  static func noteColor(velocity: Int) -> Color {
    let brightness = Double(velocity) / 127.0
    return Color(
      hue: 0.52,  // matches Theme.colorHighlight hue
      saturation: 0.7,
      brightness: 0.4 + brightness * 0.6
    )
  }
}

// MARK: - Transport Bar View

/// The bottom transport bar with play/stop/loop controls, using Liquid Glass.
@available(iOS 26.0, macCatalyst 26.0, *)
struct TransportBarView: View {
  @Binding var isPlaying: Bool
  @Binding var isLooping: Bool
  @Binding var currentBeat: Double
  let totalBeats: Double
  let sustainMin: Double
  let sustainMax: Double
  let gapMin: Double
  let gapMax: Double
  
  private var timeString: String {
    let seconds = currentBeat / 2.0  // approximate at 120 BPM
    let mins = Int(seconds) / 60
    let secs = seconds - Double(mins * 60)
    return String(format: "%d:%05.2f", mins, secs)
  }
  
  private var totalTimeString: String {
    let seconds = totalBeats / 2.0
    let mins = Int(seconds) / 60
    let secs = seconds - Double(mins * 60)
    return String(format: "%d:%05.2f", mins, secs)
  }
  
  var body: some View {
    GlassEffectContainer(spacing: 8) {
      VStack(spacing: 8) {
        // Progress slider
        Slider(value: $currentBeat, in: 0...max(totalBeats, 1))
          .tint(Color(hex: 0x4fbcd4))
          .padding(.horizontal)
        
        HStack(spacing: 16) {
          // Transport buttons
          HStack(spacing: 6) {
            Button(action: { currentBeat = 0 }) {
              Image(systemName: "backward.end.fill")
                .font(.title3)
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            
            Button(action: { isPlaying.toggle() }) {
              Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.glassProminent)
            
            Button(action: {
              isPlaying = false
              currentBeat = 0
            }) {
              Image(systemName: "stop.fill")
                .font(.title3)
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            
            Button(action: { isLooping.toggle() }) {
              Image(systemName: "repeat")
                .font(.title3)
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass(isLooping ? .regular.tint(.green) : .regular))
          }
          
          Spacer()
          
          // Time display
          Text("\(timeString) / \(totalTimeString)")
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(in: .capsule)
          
          Spacer()
          
          // Sustain/Gap range display
          HStack(spacing: 12) {
            VStack(spacing: 2) {
              Text("Sustain").font(.caption2)
              Text("\(sustainMin, specifier: "%.1f")-\(sustainMax, specifier: "%.1f")s")
                .font(.system(.caption, design: .monospaced))
            }
            VStack(spacing: 2) {
              Text("Gap").font(.caption2)
              Text("\(gapMin, specifier: "%.1f")-\(gapMax, specifier: "%.1f")s")
                .font(.system(.caption, design: .monospaced))
            }
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .glassEffect(in: .rect(cornerRadius: 10))
        }
        .padding(.horizontal)
      }
      .padding(.vertical, 8)
    }
  }
}

// MARK: - Piano Roll View

/// A piano-roll style grid showing notes on a time axis.
/// This view does NOT require iOS 26 -- it uses only standard Canvas drawing.
struct PianoRollView: View {
  let notes: [EditableNote]
  let totalBeats: Double
  let beatsPerBar: Int
  @Binding var currentBeat: Double
  let isPlaying: Bool
  
  // Display range (MIDI note numbers)
  let lowestNote: Int = 48   // C3
  let highestNote: Int = 84  // C6
  let rowHeight: CGFloat = 16
  let beatWidth: CGFloat = 40
  
  private var noteRange: [Int] {
    Array(stride(from: highestNote, through: lowestNote, by: -1))
  }
  
  private func noteName(_ note: Int) -> String {
    let octave = (note / 12) - 1
    return "\(kNoteNames[note % 12])\(octave)"
  }
  
  private func isBlackKey(_ note: Int) -> Bool {
    [1, 3, 6, 8, 10].contains(note % 12)
  }
  
  var body: some View {
    HStack(spacing: 0) {
      // Piano key labels (pinned left)
      VStack(spacing: 0) {
        ForEach(noteRange, id: \.self) { note in
          Text(noteName(note))
            .font(.system(size: 9, design: .monospaced))
            .frame(width: 36, height: rowHeight)
            .background(isBlackKey(note) ? Color(hex: 0x1a1a1a) : Color(hex: 0x2a2a2a))
            .foregroundColor(isBlackKey(note) ? Color(hex: 0x888888) : Color(hex: 0xbbbbbb))
        }
      }
      
      // Scrollable grid + notes
      ScrollView(.horizontal, showsIndicators: true) {
        ZStack(alignment: .topLeading) {
          // Grid background
          Canvas { context, size in
            let totalNotes = highestNote - lowestNote + 1
            
            // Row backgrounds (alternating for black keys)
            for (index, note) in noteRange.enumerated() {
              let y = CGFloat(index) * rowHeight
              let rect = CGRect(x: 0, y: y, width: size.width, height: rowHeight)
              if isBlackKey(note) {
                context.fill(Path(rect), with: .color(Color(hex: 0x1a1a1a)))
              } else {
                context.fill(Path(rect), with: .color(Color(hex: 0x222222)))
              }
            }
            
            // Beat grid lines
            let numBeats = Int(totalBeats)
            for beat in 0...numBeats {
              let x = CGFloat(beat) * beatWidth
              var path = Path()
              path.move(to: CGPoint(x: x, y: 0))
              path.addLine(to: CGPoint(x: x, y: CGFloat(totalNotes) * rowHeight))
              let isBarLine = beat % beatsPerBar == 0
              context.stroke(
                path,
                with: .color(isBarLine ? Color(hex: 0x555555) : Color(hex: 0x333333)),
                lineWidth: isBarLine ? 1.5 : 0.5
              )
            }
            
            // Row divider lines
            for i in 0...totalNotes {
              let y = CGFloat(i) * rowHeight
              var path = Path()
              path.move(to: CGPoint(x: 0, y: y))
              path.addLine(to: CGPoint(x: size.width, y: y))
              // Heavier line at C notes
              let noteAtRow = highestNote - i
              let isC = noteAtRow >= 0 && noteAtRow % 12 == 0
              context.stroke(
                path,
                with: .color(isC ? Color(hex: 0x444444) : Color(hex: 0x2d2d2d)),
                lineWidth: isC ? 1.0 : 0.3
              )
            }
          }
          .frame(
            width: CGFloat(totalBeats) * beatWidth,
            height: CGFloat(highestNote - lowestNote + 1) * rowHeight
          )
          
          // Note blocks
          ForEach(notes) { note in
            if note.midiNote >= lowestNote && note.midiNote <= highestNote {
              let row = highestNote - note.midiNote
              let x = CGFloat(note.startBeat) * beatWidth
              let y = CGFloat(row) * rowHeight + 1
              let width = CGFloat(note.durationBeats) * beatWidth - 2
              let height = rowHeight - 2
              
              RoundedRectangle(cornerRadius: 3)
                .fill(Color.noteColor(velocity: note.velocity))
                .overlay(
                  RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(
                      Color.white.opacity(0.3),
                      lineWidth: note.isSelected ? 2 : 0.5
                    )
                )
                .frame(width: max(width, 6), height: height)
                .offset(x: x + 1, y: y)
                .shadow(color: Color.noteColor(velocity: note.velocity).opacity(0.4), radius: 3)
            }
          }
          
          // Playhead
          if isPlaying || currentBeat > 0 {
            let playheadX = CGFloat(currentBeat) * beatWidth
            Rectangle()
              .fill(Color(hex: 0x4fbcd4))
              .frame(width: 2, height: CGFloat(highestNote - lowestNote + 1) * rowHeight)
              .offset(x: playheadX)
              .shadow(color: Color(hex: 0x4fbcd4).opacity(0.6), radius: 4)
              .animation(.linear(duration: 0.05), value: currentBeat)
          }
        }
      }
    }
    .background(Color.black)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

// MARK: - Modulation Lane View

/// A single modulation lane showing a parameter's automation curve.
@available(iOS 26.0, macCatalyst 26.0, *)
struct ModulationLanePreviewView: View {
  let parameterName: String
  let yMin: Double
  let yMax: Double
  @State private var isExpanded = true
  
  // Generate sample curve data
  private var curveData: [(Double, Double)] {
    (0..<64).map { i in
      let t = Double(i) / 2.0
      let value: Double
      switch parameterName {
      case "overallAmp":
        value = 0.3 + 0.3 * sin(t * 0.8) + 0.1 * sin(t * 2.3)
      case "vibratoFreq":
        value = 5 + 10 * max(0, sin(t * 0.5)) + 3 * sin(t * 1.7)
      default:
        value = sin(t * 0.3) * (yMax - yMin) / 2 + (yMax + yMin) / 2
      }
      return (t, min(yMax, max(yMin, value)))
    }
  }
  
  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      Chart {
        ForEach(curveData, id: \.0) { point in
          LineMark(
            x: .value("Beat", point.0),
            y: .value(parameterName, point.1)
          )
          .foregroundStyle(
            LinearGradient(
              colors: [Color(hex: 0x4fbcd4), Color(hex: 0x4fbcd4).opacity(0.5)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .lineStyle(StrokeStyle(lineWidth: 2))
          
          AreaMark(
            x: .value("Beat", point.0),
            y: .value(parameterName, point.1)
          )
          .foregroundStyle(
            LinearGradient(
              colors: [Color(hex: 0x4fbcd4).opacity(0.3), Color(hex: 0x4fbcd4).opacity(0.05)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
        }
      }
      .chartYScale(domain: yMin...yMax)
      .chartXAxis {
        AxisMarks(values: .stride(by: 4)) { _ in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Color(hex: 0x333333))
          AxisValueLabel()
            .foregroundStyle(Color(hex: 0x888888))
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading) { _ in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [4, 4]))
            .foregroundStyle(Color(hex: 0x333333))
          AxisValueLabel()
            .foregroundStyle(Color(hex: 0x888888))
        }
      }
      .chartPlotStyle { plotArea in
        plotArea
          .background(Color(hex: 0x111111))
          .border(Color(hex: 0x333333), width: 0.5)
      }
      .frame(height: 100)
    } label: {
      HStack {
        Image(systemName: "waveform.path")
          .foregroundStyle(Color(hex: 0x4fbcd4))
        Text(parameterName)
          .font(.system(.subheadline, design: .monospaced))
        Spacer()
        Text("\(yMin, specifier: "%.1f") - \(yMax, specifier: "%.1f")")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .glassEffect(in: .rect(cornerRadius: 12))
  }
}

// MARK: - Toolbar Bar View

/// The top toolbar with pattern name, preset selector, time sig, and tempo.
@available(iOS 26.0, macCatalyst 26.0, *)
struct ToolbarBarView: View {
  @Binding var patternName: String
  @Binding var timeSignature: PatternTimeSignature
  @Binding var tempo: Double
  
  var body: some View {
    GlassEffectContainer(spacing: 10) {
      HStack(spacing: 10) {
        // Back button
        Button(action: {}) {
          Image(systemName: "chevron.left")
            .font(.title3)
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.glass)
        
        // Pattern name
        TextField("Pattern Name", text: $patternName)
          .textFieldStyle(.plain)
          .font(.headline)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .glassEffect(in: .rect(cornerRadius: 8))
          .frame(maxWidth: 180)
        
        // Preset selector
        Menu {
          Button("Aurora Borealis") {}
          Button("5th Cluedo") {}
          Button("Saw") {}
          Button("Sine") {}
          Button("Square") {}
          Button("Triangle") {}
          Divider()
          Button("Edit Synth...") {}
        } label: {
          Label("Preset", systemImage: "pianokeys")
            .font(.subheadline)
        }
        .buttonStyle(.glass)
        
        Spacer()
        
        // Time signature
        Picker("Time Sig", selection: $timeSignature) {
          ForEach(PatternTimeSignature.allCases) { sig in
            Text(sig.rawValue).tag(sig)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)
        
        // Tempo
        HStack(spacing: 4) {
          Image(systemName: "metronome")
            .font(.caption)
          TextField("BPM", value: $tempo, format: .number)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .frame(width: 50)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(in: .capsule)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
    }
  }
}

// MARK: - Zoom Overlay

/// Floating zoom and snap controls overlaid on the piano roll.
@available(iOS 26.0, macCatalyst 26.0, *)
struct ZoomOverlayView: View {
  @Binding var snapDivision: Int
  
  var body: some View {
    HStack(spacing: 8) {
      Button(action: {}) {
        Image(systemName: "plus.magnifyingglass")
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.glass)
      
      Button(action: {}) {
        Image(systemName: "minus.magnifyingglass")
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.glass)
      
      Divider()
        .frame(height: 20)
      
      Text("Snap:")
        .font(.caption)
      Picker("Snap", selection: $snapDivision) {
        Text("1/4").tag(4)
        Text("1/8").tag(8)
        Text("1/16").tag(16)
        Text("Off").tag(0)
      }
      .pickerStyle(.segmented)
      .frame(width: 180)
    }
    .padding(8)
    .glassEffect(in: .rect(cornerRadius: 12))
  }
}

// MARK: - Full Pattern Editor View

/// The main Pattern Editor view, combining all zones.
@available(iOS 26.0, macCatalyst 26.0, *)
struct PatternEditorView: View {
  @State private var pattern = EditablePattern.samplePattern
  @State private var isPlaying = false
  @State private var isLooping = true
  @State private var currentBeat: Double = 4.0
  @State private var snapDivision: Int = 8
  
  var totalBeats: Double {
    Double(pattern.totalBars * pattern.timeSignature.beatsPerBar)
  }
  
  var body: some View {
    ZStack {
      // Dark background
      LinearGradient(
        colors: [Color(hex: 0x1a1a1a), Color.black],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
      
      VStack(spacing: 0) {
        // Zone 1: Toolbar
        ToolbarBarView(
          patternName: $pattern.name,
          timeSignature: $pattern.timeSignature,
          tempo: $pattern.tempo
        )
        .padding(.bottom, 4)
        
        // Zone 2: Piano Roll
        ZStack(alignment: .bottomTrailing) {
          PianoRollView(
            notes: pattern.notes,
            totalBeats: totalBeats,
            beatsPerBar: pattern.timeSignature.beatsPerBar,
            currentBeat: $currentBeat,
            isPlaying: isPlaying
          )
          
          // Floating zoom overlay
          ZoomOverlayView(snapDivision: $snapDivision)
            .padding(8)
        }
        .padding(.horizontal, 8)
        
        // Zone 3: Modulation Lanes
        GlassEffectContainer(spacing: 6) {
          ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
              ModulationLanePreviewView(
                parameterName: "overallAmp",
                yMin: 0.0,
                yMax: 1.0
              )
              ModulationLanePreviewView(
                parameterName: "vibratoFreq",
                yMin: 0.0,
                yMax: 30.0
              )
              ModulationLanePreviewView(
                parameterName: "overallCentDetune",
                yMin: -5.0,
                yMax: 5.0
              )
            }
            .padding(.horizontal, 8)
          }
          .frame(maxHeight: 250)
        }
        .padding(.vertical, 4)
        
        // Zone 4: Transport Bar
        TransportBarView(
          isPlaying: $isPlaying,
          isLooping: $isLooping,
          currentBeat: $currentBeat,
          totalBeats: totalBeats,
          sustainMin: pattern.sustainMin,
          sustainMax: pattern.sustainMax,
          gapMin: pattern.gapMin,
          gapMax: pattern.gapMax
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
      }
    }
  }
}

// MARK: - Isolated Component Previews

@available(iOS 26.0, macCatalyst 26.0, *)
#Preview("Full Pattern Editor") {
  PatternEditorView()
}

@available(iOS 26.0, macCatalyst 26.0, *)
#Preview("Transport Bar") {
  ZStack {
    Color.black.ignoresSafeArea()
    TransportBarView(
      isPlaying: .constant(true),
      isLooping: .constant(true),
      currentBeat: .constant(8.5),
      totalBeats: 32,
      sustainMin: 5.0,
      sustainMax: 10.0,
      gapMin: 5.0,
      gapMax: 10.0
    )
    .padding()
  }
}

@available(iOS 26.0, macCatalyst 26.0, *)
#Preview("Toolbar Bar") {
  ZStack {
    Color.black.ignoresSafeArea()
    ToolbarBarView(
      patternName: .constant("Aurora Pattern"),
      timeSignature: .constant(.fourFour),
      tempo: .constant(120)
    )
    .padding()
  }
}

#Preview("Piano Roll") {
  ZStack {
    Color.black.ignoresSafeArea()
    PianoRollView(
      notes: EditablePattern.samplePattern.notes,
      totalBeats: 32,
      beatsPerBar: 4,
      currentBeat: .constant(4.0),
      isPlaying: false
    )
    .frame(height: 400)
    .padding()
  }
}

@available(iOS 26.0, macCatalyst 26.0, *)
#Preview("Modulation Lanes") {
  ZStack {
    Color.black.ignoresSafeArea()
    GlassEffectContainer(spacing: 6) {
      VStack(spacing: 6) {
        ModulationLanePreviewView(
          parameterName: "overallAmp",
          yMin: 0.0,
          yMax: 1.0
        )
        ModulationLanePreviewView(
          parameterName: "vibratoFreq",
          yMin: 0.0,
          yMax: 30.0
        )
      }
      .padding()
    }
  }
}

@available(iOS 26.0, macCatalyst 26.0, *)
#Preview("Zoom Overlay") {
  ZStack {
    Color.black.ignoresSafeArea()
    ZoomOverlayView(snapDivision: .constant(8))
  }
}

@available(iOS 26.0, macCatalyst 26.0, *)
#Preview("Glass Button Showcase") {
  ZStack {
    LinearGradient(
      colors: [Color(hex: 0x1a1a1a), Color.black],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
    
    GlassEffectContainer(spacing: 12) {
      VStack(spacing: 20) {
        // Standard glass buttons
        HStack(spacing: 12) {
          Button("Glass") {}
            .buttonStyle(.glass)
          Button("Prominent") {}
            .buttonStyle(.glassProminent)
          Button("Tinted") {}
            .buttonStyle(.glass(.regular.tint(Color(hex: 0x4fbcd4))))
        }
        
        // Interactive glass panels
        HStack(spacing: 16) {
          Text("Panel A")
            .padding()
            .glassEffect(in: .rect(cornerRadius: 12))
          
          Text("Panel B")
            .padding()
            .glassEffect(.regular.tint(.orange), in: .rect(cornerRadius: 12))
          
          Text("Capsule")
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassEffect(in: .capsule)
        }
        
        // Transport-style buttons
        HStack(spacing: 8) {
          ForEach(["backward.end.fill", "play.fill", "pause.fill", "stop.fill", "repeat"], id: \.self) { icon in
            Button(action: {}) {
              Image(systemName: icon)
                .font(.title2)
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
          }
        }
      }
      .padding()
    }
  }
}
