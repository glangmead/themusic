//
//  RoseSceneView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/19/26.
//

import RealityKit
import SwiftUI

/// Mutable camera state shared between gestures and the render loop.
/// Using a class avoids triggering SwiftUI view updates on every gesture frame.
private final class CameraState {
    var yaw: Float = -0.5
    var pitch: Float = 0.55
    var distance: Float = 12.0
    // Gesture-start snapshots
    var baseYaw: Float = -0.5
    var basePitch: Float = 0.55
    var baseDistance: Float = 12.0
}

/// A 3D RealityKit view that animates a dot along a Rose (Lissajous) curve
/// inside a translucent wireframe cube. The Rose object's live parameters
/// (amp, freq, leafFactor) are read each frame so slider changes appear instantly.
struct RoseSceneView: View {
    let rose: Rose
    @Environment(\.colorScheme) private var colorScheme

    /// Trigger for update closure when color scheme changes
    @State private var isDark = false

    /// Camera state read by the render loop — not @State so gestures don't
    /// trigger SwiftUI re-renders.
    @State private var cam = CameraState()

    var body: some View {
        RealityView { content in
            content.camera = .virtual

            // -- Camera --
            let cameraEntity = Entity()
            cameraEntity.name = "camera"
            cameraEntity.components.set(
                PerspectiveCameraComponent(
                    near: 0.01,
                    far: 100,
                    fieldOfViewInDegrees: 50
                )
            )
            content.add(cameraEntity)

            // Position camera using spherical coordinates
            let camRef = cam
            Self.positionCamera(cameraEntity, state: camRef)

            // -- Lighting --
            let keyLight = Entity()
            keyLight.name = "keyLight"
            var directional = DirectionalLightComponent()
            directional.intensity = 2000
            directional.color = .white
            keyLight.components.set(directional)
            keyLight.look(at: .zero, from: SIMD3(5, 8, 8), relativeTo: nil)
            content.add(keyLight)

            let fillLight = Entity()
            fillLight.name = "fillLight"
            var fill = DirectionalLightComponent()
            fill.intensity = 800
            fill.color = .white
            fillLight.components.set(fill)
            fillLight.look(at: .zero, from: SIMD3(-4, 2, -6), relativeTo: nil)
            content.add(fillLight)

            // -- Root entity to hold all scene content --
            let root = Entity()
            root.name = "sceneRoot"
            content.add(root)

            let amp = Float(rose.amp.val)
            let side = amp * 2
            let dark = colorScheme == .dark

            // -- Translucent cube faces --
            let faceEntity = Self.makeFacesCube(side: side, isDark: dark)
            faceEntity.name = "faces"
            root.addChild(faceEntity)

            // -- Edge-only wireframe --
            let edgeEntity = Self.makeEdgesCube(side: side, isDark: dark)
            edgeEntity.name = "edges"
            root.addChild(edgeEntity)

            // -- Axis gizmo --
            let axisEntity = Self.makeAxisGizmo(amp: amp, isDark: dark)
            axisEntity.name = "axes"
            root.addChild(axisEntity)

            // -- Abstract head at origin --
            let headEntity = Self.makeHead(side: side, isDark: dark)
            headEntity.name = "head"
            root.addChild(headEntity)

            // -- Dot --
            let dotEntity = Self.makeDot(isDark: dark)
            dotEntity.name = "dot"
            root.addChild(dotEntity)

            // -- Trail --
            let trailEntity = Self.makeTrail(isDark: dark)
            trailEntity.name = "trail"
            root.addChild(trailEntity)

            // -- Per-frame animation --
            let roseRef = rose
            var elapsed: TimeInterval = 0
            let trailCount = 60
            var initialAmp = amp

            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                // Reposition camera each frame from gesture state
                Self.positionCamera(cameraEntity, state: camRef)

                elapsed += event.deltaTime
                let t = elapsed

                let currentAmp = Float(roseRef.amp.val)
                _ = roseRef.freq.val
                _ = roseRef.leafFactor.val

                // Compute Rose position (upper-hemisphere spherical)
                let (rx, ry, rz) = roseRef.of(t)
                let pos = SIMD3<Float>(Float(rx), Float(ry), Float(rz))

                // Move dot
                dotEntity.position = pos

                // Shift trail
                let trailChildren = trailEntity.children
                if trailChildren.count == trailCount {
                    for i in stride(from: trailCount - 1, through: 1, by: -1) {
                        trailChildren[i].position = trailChildren[i - 1].position
                        trailChildren[i].isEnabled = trailChildren[i - 1].isEnabled
                    }
                    trailChildren[0].position = pos
                    trailChildren[0].isEnabled = true
                }

                // Resize cube if amplitude changed
                let newSide = currentAmp * 2
                if abs(newSide - (initialAmp * 2)) > 0.01 {
                    // Update faces
                    faceEntity.components[ModelComponent.self]?.mesh = MeshResource.generateBox(size: newSide)
                    // Update edges
                    edgeEntity.components[ModelComponent.self]?.mesh = MeshResource.generateBox(size: newSide)
                    // Scale axes and head proportionally
                    if initialAmp > 0 {
                        let s = currentAmp / initialAmp
                        axisEntity.scale = SIMD3<Float>(repeating: s)
                        headEntity.scale = SIMD3<Float>(repeating: s)
                    }
                    initialAmp = currentAmp
                }
            }
        } update: { content in
            // Respond to color scheme changes
            guard let root = content.entities.first(where: { $0.name == "sceneRoot" }) else { return }
            let dark = isDark

            // Update face material
            if let faces = root.findEntity(named: "faces") {
                faces.components[ModelComponent.self]?.materials = [Self.faceMaterial(isDark: dark)]
            }
            // Update edge material
            if let edges = root.findEntity(named: "edges") {
                edges.components[ModelComponent.self]?.materials = [Self.edgeMaterial(isDark: dark)]
            }
            // Update head materials
            if let head = root.findEntity(named: "head") {
                Self.applyHeadMaterials(to: head, isDark: dark)
            }
            // Update dot material
            if let dot = root.findEntity(named: "dot") {
                dot.components[ModelComponent.self]?.materials = [Self.dotMaterial(isDark: dark)]
            }
            // Update trail materials
            if let trail = root.findEntity(named: "trail") {
                for (i, child) in trail.children.enumerated() {
                    let opacity = Float(1.0) - (Float(i) / 60.0)
                    child.components[ModelComponent.self]?.materials = [Self.trailMaterial(isDark: dark, opacity: opacity * 0.6)]
                }
            }
            // Update axis materials
            if let axes = root.findEntity(named: "axes") {
                Self.applyAxisMaterials(to: axes, isDark: dark)
            }
        }
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    let sensitivity: Float = 0.008
                    cam.yaw = cam.baseYaw - Float(value.translation.width) * sensitivity
                    cam.pitch = max(-Float.pi / 2 + 0.1,
                                    min(Float.pi / 2 - 0.1,
                                        cam.basePitch + Float(value.translation.height) * sensitivity))
                }
                .onEnded { _ in
                    cam.baseYaw = cam.yaw
                    cam.basePitch = cam.pitch
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let scale = Float(value.magnification)
                    cam.distance = max(3, min(40, cam.baseDistance / scale))
                }
                .onEnded { _ in
                    cam.baseDistance = cam.distance
                }
        )
        .onAppear {
            isDark = colorScheme == .dark
        }
        .onChange(of: colorScheme) { _, newValue in
            isDark = newValue == .dark
        }
    }

    // MARK: - Camera Helpers

    /// Position a camera entity on a sphere looking at the origin.
    private static func positionCamera(_ camera: Entity, state: CameraState) {
        let x = state.distance * cos(state.pitch) * sin(state.yaw)
        let y = state.distance * sin(state.pitch)
        let z = state.distance * cos(state.pitch) * cos(state.yaw)
        camera.look(at: .zero, from: SIMD3(x, y, z), relativeTo: nil)
    }

    // MARK: - Material Factories

    private static func faceMaterial(isDark: Bool) -> UnlitMaterial {
        var mat = UnlitMaterial()
        if isDark {
            mat.color = .init(tint: UIColor(white: 0.4, alpha: 1.0))
        } else {
            mat.color = .init(tint: UIColor(white: 0.8, alpha: 1.0))
        }
        mat.blending = .transparent(opacity: .init(floatLiteral: isDark ? 0.75 : 0.7))
        // Don't write depth so interior objects (head, dot, trail) remain visible
        mat.writesDepth = false
        return mat
    }

    private static func edgeMaterial(isDark: Bool) -> UnlitMaterial {
        var mat = UnlitMaterial()
        if isDark {
            mat.color = .init(tint: .white.withAlphaComponent(0.4))
        } else {
            mat.color = .init(tint: .black)
        }
        mat.triangleFillMode = .lines
        return mat
    }

    private static func headMaterial(isDark: Bool) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        if isDark {
            mat.baseColor = .init(tint: UIColor(white: 0.7, alpha: 1.0))
        } else {
            mat.baseColor = .init(tint: UIColor(white: 0.55, alpha: 1.0))
        }
        mat.roughness = .init(floatLiteral: 0.5)
        mat.metallic = .init(floatLiteral: 0.1)
        mat.blending = .transparent(opacity: .init(floatLiteral: isDark ? 0.5 : 0.7))
        return mat
    }

    private static func noseMaterial(isDark: Bool) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        if isDark {
            mat.baseColor = .init(tint: UIColor(white: 0.7, alpha: 1.0))
        } else {
            mat.baseColor = .init(tint: UIColor(white: 0.45, alpha: 1.0))
        }
        mat.roughness = .init(floatLiteral: 0.4)
        mat.metallic = .init(floatLiteral: 0.1)
        mat.blending = .transparent(opacity: .init(floatLiteral: isDark ? 0.6 : 0.8))
        return mat
    }

    private static func earMaterial(isDark: Bool) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        if isDark {
            mat.baseColor = .init(tint: UIColor(white: 0.65, alpha: 1.0))
        } else {
            mat.baseColor = .init(tint: UIColor(white: 0.5, alpha: 1.0))
        }
        mat.roughness = .init(floatLiteral: 0.5)
        mat.metallic = .init(floatLiteral: 0.1)
        mat.blending = .transparent(opacity: .init(floatLiteral: isDark ? 0.45 : 0.65))
        return mat
    }

    private static let cyan = UIColor(red: 0.31, green: 0.74, blue: 0.83, alpha: 1.0)

    private static func eyeMaterial(isDark: Bool) -> UnlitMaterial {
        var mat = UnlitMaterial()
        if isDark {
            mat.color = .init(tint: cyan)
        } else {
            mat.color = .init(tint: .black)
        }
        return mat
    }

    private static func dotMaterial(isDark: Bool) -> UnlitMaterial {
        var mat = UnlitMaterial()
        if isDark {
            mat.color = .init(tint: cyan)
        } else {
            mat.color = .init(tint: .black)
        }
        return mat
    }

    private static func trailMaterial(isDark: Bool, opacity: Float) -> UnlitMaterial {
        var mat = UnlitMaterial()
        let tint: UIColor = isDark ? cyan : .black
        mat.color = .init(tint: tint)
        mat.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return mat
    }

    private static func axisMaterial(color: UIColor, isDark: Bool) -> UnlitMaterial {
        var mat = UnlitMaterial()
        if isDark {
            mat.color = .init(tint: color.withAlphaComponent(0.7))
        } else {
            mat.color = .init(tint: color)
        }
        return mat
    }

    // MARK: - Entity Factories

    private static func makeFacesCube(side: Float, isDark: Bool) -> Entity {
        let entity = Entity()
        let mesh = MeshResource.generateBox(size: side)
        entity.components.set(ModelComponent(mesh: mesh, materials: [faceMaterial(isDark: isDark)]))
        return entity
    }

    private static func makeEdgesCube(side: Float, isDark: Bool) -> Entity {
        let entity = Entity()
        let mesh = MeshResource.generateBox(size: side)
        entity.components.set(ModelComponent(mesh: mesh, materials: [edgeMaterial(isDark: isDark)]))
        // Slightly larger so wireframe edges render on top of the faces cube
        entity.scale = SIMD3<Float>(repeating: 1.005)
        return entity
    }

    private static func makeDot(isDark: Bool) -> Entity {
        let entity = Entity()
        let mesh = MeshResource.generateSphere(radius: 0.2)
        entity.components.set(ModelComponent(mesh: mesh, materials: [dotMaterial(isDark: isDark)]))
        return entity
    }

    private static func makeTrail(isDark: Bool) -> Entity {
        let container = Entity()
        let trailCount = 60
        let mesh = MeshResource.generateSphere(radius: 0.06)
        for i in 0..<trailCount {
            let opacity = Float(1.0) - (Float(i) / Float(trailCount))
            let entity = Entity()
            entity.components.set(ModelComponent(mesh: mesh, materials: [trailMaterial(isDark: isDark, opacity: opacity * 0.6)]))
            entity.isEnabled = false
            container.addChild(entity)
        }
        return container
    }

    private static func makeAxisGizmo(amp: Float, isDark: Bool) -> Entity {
        let container = Entity()
        let axisLength = amp + 1.0

        let axisConfigs: [(direction: SIMD3<Float>, color: UIColor, label: String)] = [
            (SIMD3(1, 0, 0), .systemRed, "X"),
            (SIMD3(0, 1, 0), .systemGreen, "Y"),
            (SIMD3(0, 0, 1), .systemBlue, "Z"),
        ]

        for config in axisConfigs {
            let mat = axisMaterial(color: config.color, isDark: isDark)
            let endpoint = config.direction * axisLength

            // Shaft (thin cylinder)
            let shaftMesh = MeshResource.generateCylinder(height: axisLength, radius: 0.03)
            let shaft = Entity()
            shaft.name = "shaft_\(config.label)"
            shaft.components.set(ModelComponent(mesh: shaftMesh, materials: [mat]))
            // Position at midpoint and rotate to align with axis
            shaft.position = endpoint / 2
            if config.label == "X" {
                shaft.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 0, 1))
            } else if config.label == "Z" {
                shaft.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            }
            // Y needs no rotation (cylinder is along Y by default)
            container.addChild(shaft)

            // Arrowhead (cone)
            let coneMesh = MeshResource.generateCone(height: 0.3, radius: 0.1)
            let cone = Entity()
            cone.name = "cone_\(config.label)"
            cone.components.set(ModelComponent(mesh: coneMesh, materials: [mat]))
            cone.position = endpoint
            if config.label == "X" {
                cone.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 0, 1))
            } else if config.label == "Z" {
                cone.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            }
            container.addChild(cone)

            // Label text
            let textEntity = Entity()
            textEntity.name = "label_\(config.label)"
            let textMesh = MeshResource.generateText(
                config.label,
                extrusionDepth: 0.01,
                font: .systemFont(ofSize: 0.3, weight: .bold)
            )
            var textMat = UnlitMaterial()
            textMat.color = .init(tint: isDark ? config.color.withAlphaComponent(0.7) : config.color)
            textEntity.components.set(ModelComponent(mesh: textMesh, materials: [textMat]))
            textEntity.position = endpoint * 1.15
            container.addChild(textEntity)
        }

        return container
    }

    private static func makeHead(side: Float, isDark: Bool) -> Entity {
        let container = Entity()
        let headDiameter = side / 4
        let headRadius = headDiameter / 2

        // Cranium (slightly taller than wide)
        let craniumMesh = MeshResource.generateSphere(radius: headRadius)
        let cranium = Entity()
        cranium.name = "cranium"
        cranium.components.set(ModelComponent(mesh: craniumMesh, materials: [headMaterial(isDark: isDark)]))
        cranium.scale = SIMD3(1.0, 1.15, 1.0)
        container.addChild(cranium)

        // Nose: small sphere protruding from front (-Z direction)
        let noseRadius = headRadius * 0.3
        let noseMesh = MeshResource.generateSphere(radius: noseRadius)
        let nose = Entity()
        nose.name = "nose"
        nose.components.set(ModelComponent(mesh: noseMesh, materials: [noseMaterial(isDark: isDark)]))
        nose.position = SIMD3(0, -headRadius * 0.15, -headRadius * 0.9)
        container.addChild(nose)

        // Ears
        let earRadius = headRadius * 0.25
        let earMesh = MeshResource.generateSphere(radius: earRadius)
        let leftEar = Entity()
        leftEar.name = "leftEar"
        leftEar.components.set(ModelComponent(mesh: earMesh, materials: [earMaterial(isDark: isDark)]))
        leftEar.position = SIMD3(-headRadius * 0.95, 0, 0)
        leftEar.scale = SIMD3(0.4, 0.7, 0.5)
        container.addChild(leftEar)

        let rightEar = Entity()
        rightEar.name = "rightEar"
        rightEar.components.set(ModelComponent(mesh: earMesh, materials: [earMaterial(isDark: isDark)]))
        rightEar.position = SIMD3(headRadius * 0.95, 0, 0)
        rightEar.scale = SIMD3(0.4, 0.7, 0.5)
        container.addChild(rightEar)

        // Eyes
        let eyeRadius = headRadius * 0.15
        let eyeMesh = MeshResource.generateSphere(radius: eyeRadius)
        let leftEye = Entity()
        leftEye.name = "leftEye"
        leftEye.components.set(ModelComponent(mesh: eyeMesh, materials: [eyeMaterial(isDark: isDark)]))
        leftEye.position = SIMD3(-headRadius * 0.35, headRadius * 0.15, -headRadius * 0.85)
        container.addChild(leftEye)

        let rightEye = Entity()
        rightEye.name = "rightEye"
        rightEye.components.set(ModelComponent(mesh: eyeMesh, materials: [eyeMaterial(isDark: isDark)]))
        rightEye.position = SIMD3(headRadius * 0.35, headRadius * 0.15, -headRadius * 0.85)
        container.addChild(rightEye)

        return container
    }

    // MARK: - Material Update Helpers

    private static func applyHeadMaterials(to head: Entity, isDark: Bool) {
        head.findEntity(named: "cranium")?.components[ModelComponent.self]?.materials = [headMaterial(isDark: isDark)]
        head.findEntity(named: "nose")?.components[ModelComponent.self]?.materials = [noseMaterial(isDark: isDark)]
        head.findEntity(named: "leftEar")?.components[ModelComponent.self]?.materials = [earMaterial(isDark: isDark)]
        head.findEntity(named:  "rightEar")?.components[ModelComponent.self]?.materials = [earMaterial(isDark: isDark)]
        head.findEntity(named: "leftEye")?.components[ModelComponent.self]?.materials = [eyeMaterial(isDark: isDark)]
        head.findEntity(named: "rightEye")?.components[ModelComponent.self]?.materials = [eyeMaterial(isDark: isDark)]
    }

    private static func applyAxisMaterials(to axes: Entity, isDark: Bool) {
        let configs: [(label: String, color: UIColor)] = [
            ("X", .systemRed),
            ("Y", .systemGreen),
            ("Z", .systemBlue),
        ]
        for config in configs {
            let mat = axisMaterial(color: config.color, isDark: isDark)
            axes.findEntity(named: "shaft_\(config.label)")?.components[ModelComponent.self]?.materials = [mat]
            axes.findEntity(named: "cone_\(config.label)")?.components[ModelComponent.self]?.materials = [mat]
            if let textEntity = axes.findEntity(named: "label_\(config.label)") {
                var textMat = UnlitMaterial()
                textMat.color = .init(tint: isDark ? config.color.withAlphaComponent(0.7) : config.color)
                textEntity.components[ModelComponent.self]?.materials = [textMat]
            }
        }
    }
}

#Preview {
    RoseSceneView(rose: Rose(
        amp: ArrowConst(value: 3),
        leafFactor: ArrowConst(value: 4),
        freq: ArrowConst(value: 1.25),
        phase: 0
    ))
    .frame(height: 600)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding()
}
