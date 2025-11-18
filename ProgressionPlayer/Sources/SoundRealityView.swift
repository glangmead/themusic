//
//  RealityView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 11/15/25.
//

import RealityKit
import SwiftUI
import ARKit

struct SoundRealityView: View {
  let soundSource: AnchorEntity
  var soundResource: AudioResource? = nil
  init() {
    soundSource = AnchorEntity(.camera)
    soundSource.components.set(SpatialAudioComponent(gain: -5))
    soundSource.spatialAudio?.directivity = .beam(focus: 0)
    soundSource.spatialAudio?.distanceAttenuation = .rolloff(factor: 1)
    //soundSource.orientation = .init(angle: .pi, axis: [0, 1, 0])
    do {
      soundResource = try AudioFileResource.load(
        named: "beat.aiff",
        configuration: .init(shouldLoop: true)
      )
    } catch {
      print("Error loading audio file: \(error.localizedDescription)")
    }
    
  }
  var body: some View {
    ZStack {
      Color.black
      RealityView { content in
        content.add(soundSource)
      }
    }
    //ARViewContainer(entity: soundSource).edgesIgnoringSafeArea(.all)
    Button("Play") {
      soundSource.playAudio(soundResource!)
    }
    Spacer()
    Button("Move it") {
      let currentTransform = soundSource.transform
      soundSource.move(
        to: Transform(
          scale: currentTransform.scale,
          rotation: currentTransform.rotation,
          translation: SIMD3<Float>(
            x: currentTransform.translation.x - 0.1,
            y: currentTransform.translation.y,
            z: currentTransform.translation.z)
        ),
        relativeTo: soundSource.parent,
        duration: 0.5
      )
    }
    Spacer()
    Button("Stop") {
      soundSource.stopAllAudio()
    }
  }
}

struct ARViewContainer: UIViewRepresentable {
  let entity: AnchorEntity
  init(entity: AnchorEntity) {
    self.entity = entity
  }
  func makeUIView(context: Context) -> ARView {
    let arView = ARView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
    arView.automaticallyConfigureSession = true
    arView.cameraMode = .nonAR
    //arView.audioEnvironmentNode.renderingAlgorithm = .HRTFHQ
    // configure arView
    return arView
  }
  func updateUIView(_ uiView: ARView, context: Context) {}
}

#Preview {
  SoundRealityView()
}
