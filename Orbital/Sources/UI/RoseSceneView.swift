//
//  RoseSceneView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/19/26.
//

import SceneKit
import SwiftUI

/// A 3D SceneKit view that animates a dot along a Rose (Lissajous) curve
/// inside a translucent wireframe cube. The Rose object's live parameters
/// (amp, freq, leafFactor) are read each frame so slider changes appear instantly.
struct RoseSceneView: UIViewRepresentable {
    let rose: Rose
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(rose: rose, isDark: colorScheme == .dark)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = context.coordinator.scene
        scnView.delegate = context.coordinator
        scnView.allowsCameraControl = true
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.isPlaying = true  // Keep the render loop running
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.rose = rose
        context.coordinator.applyColorScheme(isDark: colorScheme == .dark)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, SCNSceneRendererDelegate {
        var rose: Rose
        let scene = SCNScene()

        private let dotNode: SCNNode
        private let cubeNode: SCNNode
        private let edgeNode: SCNNode
        private let axisNode: SCNNode
        private let headNode: SCNNode
        private let initialAmp: Float
        private var trailNodes: [SCNNode] = []
        private let trailCount = 60
        private var startTime: TimeInterval = 0

        // Materials that adapt to light/dark mode
        private let faceMaterial: SCNMaterial
        private let edgeMaterial: SCNMaterial
        private let headMaterial: SCNMaterial
        private let noseMaterial: SCNMaterial
        private let earMaterial: SCNMaterial
        private let dotMaterial: SCNMaterial
        private let eyeMaterial: SCNMaterial
        private var axisMaterials: [(material: SCNMaterial, color: UIColor)] = []
        private var isDark: Bool

        init(rose: Rose, isDark: Bool) {
            self.rose = rose
            self.isDark = isDark

            // -- Camera --
            // Elevated angle showing three faces of the cube
            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(-4, 5, -7)
            cameraNode.camera?.usesOrthographicProjection = false
            cameraNode.camera?.fieldOfView = 50
            // Look at the origin
            let cameraTarget = SCNNode()
            cameraTarget.position = SCNVector3Zero
            let lookAt = SCNLookAtConstraint(target: cameraTarget)
            lookAt.isGimbalLockEnabled = true
            cameraNode.constraints = [lookAt]

            // -- Ambient light --
            let ambientNode = SCNNode()
            ambientNode.light = SCNLight()
            ambientNode.light?.type = .ambient
            ambientNode.light?.color = UIColor.white.withAlphaComponent(0.3)

            // -- Wireframe cube --
            let amp = Float(rose.amp.val)
            let side = CGFloat(amp * 2)
            let box = SCNBox(width: side, height: side, length: side, chamferRadius: 0)
            let fm = SCNMaterial()
            fm.lightingModel = .constant
            fm.isDoubleSided = true
            fm.writesToDepthBuffer = false
            fm.readsFromDepthBuffer = true
            box.materials = [fm]
            faceMaterial = fm
            let faceNode = SCNNode(geometry: box)

            // Edge-only wireframe overlaid on the faces (no face diagonals)
            let em = SCNMaterial()
            em.lightingModel = .constant
            edgeMaterial = em
            let edgeGeo = Coordinator.cubeEdgeGeometry(side: side)
            edgeGeo.materials = [em]
            edgeNode = SCNNode(geometry: edgeGeo)

            cubeNode = SCNNode()
            cubeNode.addChildNode(faceNode)
            cubeNode.addChildNode(edgeNode)

            // -- Dot --
            let sphere = SCNSphere(radius: 0.2)
            let dm = SCNMaterial()
            dm.lightingModel = .constant
            sphere.materials = [dm]
            dotMaterial = dm
            dotNode = SCNNode(geometry: sphere)

            // -- Axis gizmo (fixed to cube) --
            let axisLength = Float(amp) + 1.0
            let axes: [(SCNVector3, SCNVector4, UIColor, String)] = [
                // (direction endpoint, cylinder rotation, color, label)
                (SCNVector3(axisLength, 0, 0), SCNVector4(0, 0, 1, -Float.pi / 2), .systemRed, "X"),
                (SCNVector3(0, axisLength, 0), SCNVector4(0, 0, 0, 0), .systemGreen, "Y"),
                (SCNVector3(0, 0, axisLength), SCNVector4(1, 0, 0, Float.pi / 2), .systemBlue, "Z"),
            ]
            let axisContainer = SCNNode()
            var axisMatEntries: [(material: SCNMaterial, color: UIColor)] = []
            for (endpoint, rotation, color, label) in axes {
                let axisMat = SCNMaterial()
                axisMat.lightingModel = .constant
                axisMat.diffuse.contents = color.withAlphaComponent(0.7)
                axisMatEntries.append((material: axisMat, color: color))

                // Shaft
                let shaft = SCNCylinder(radius: 0.03, height: CGFloat(axisLength))
                shaft.materials = [axisMat]
                let shaftNode = SCNNode(geometry: shaft)
                // Cylinder is along Y by default; position at midpoint, then rotate
                shaftNode.position = SCNVector3(endpoint.x / 2, endpoint.y / 2, endpoint.z / 2)
                shaftNode.rotation = rotation
                axisContainer.addChildNode(shaftNode)

                // Arrowhead
                let cone = SCNCone(topRadius: 0, bottomRadius: 0.1, height: 0.3)
                cone.materials = [axisMat]
                let coneNode = SCNNode(geometry: cone)
                coneNode.position = endpoint
                coneNode.rotation = rotation
                axisContainer.addChildNode(coneNode)

                // Label
                let text = SCNText(string: label, extrusionDepth: 0)
                text.font = UIFont.systemFont(ofSize: 0.5, weight: .bold)
                text.flatness = 0.1
                text.materials = [axisMat]
                let textNode = SCNNode(geometry: text)
                // Center the text bounding box, then offset past the arrowhead
                let (textMin, textMax) = textNode.boundingBox
                let textW = textMax.x - textMin.x
                let textH = textMax.y - textMin.y
                textNode.pivot = SCNMatrix4MakeTranslation(textW / 2, textH / 2, 0)
                textNode.position = SCNVector3(
                    endpoint.x * 1.15,
                    endpoint.y * 1.15,
                    endpoint.z * 1.15
                )
                // Billboard constraint so labels always face the camera
                let billboard = SCNBillboardConstraint()
                billboard.freeAxes = .all
                textNode.constraints = [billboard]
                axisContainer.addChildNode(textNode)
            }

            axisNode = axisContainer
            axisMaterials = axisMatEntries
            initialAmp = amp

            // -- Abstract head (listener) at origin --
            // Diameter = 1/4 of cube edge. Oriented per AVAudioEnvironmentNode
            // defaults: forward = (0, 0, -1), up = (0, 1, 0).
            let headDiameter = side / 4
            let headRadius = headDiameter / 2

            let hm = SCNMaterial()
            hm.lightingModel = .constant
            hm.isDoubleSided = true
            headMaterial = hm

            // Cranium: slightly taller than wide (egg shape)
            let cranium = SCNSphere(radius: headRadius)
            cranium.segmentCount = 24
            cranium.materials = [hm]
            let craniumNode = SCNNode(geometry: cranium)
            craniumNode.scale = SCNVector3(1.0, 1.15, 1.0) // taller

            // Nose: small sphere protruding from front face to show facing direction
            // AVAudioEnvironmentNode default forward is (0, 0, -1)
            let noseRadius = headRadius * 0.3
            let nose = SCNSphere(radius: noseRadius)
            let nm = SCNMaterial()
            nm.lightingModel = .constant
            noseMaterial = nm
            nose.materials = [nm]
            let noseNode = SCNNode(geometry: nose)
            noseNode.position = SCNVector3(0, Float(-headRadius * 0.15), Float(-headRadius * 0.9))

            // Ears: small flattened spheres on left and right
            let earRadius = headRadius * 0.25
            let ear = SCNSphere(radius: earRadius)
            let eam = SCNMaterial()
            eam.lightingModel = .constant
            earMaterial = eam
            ear.materials = [eam]
            let leftEarNode = SCNNode(geometry: ear)
            leftEarNode.position = SCNVector3(Float(-headRadius * 0.95), 0, 0)
            leftEarNode.scale = SCNVector3(0.4, 0.7, 0.5)
            let rightEarNode = SCNNode(geometry: ear)
            rightEarNode.position = SCNVector3(Float(headRadius * 0.95), 0, 0)
            rightEarNode.scale = SCNVector3(0.4, 0.7, 0.5)

            // Eyes: small spheres on the front face
            let eyeRadius = headRadius * 0.15
            let eyeGeo = SCNSphere(radius: eyeRadius)
            let em2 = SCNMaterial()
            em2.lightingModel = .constant
            eyeGeo.materials = [em2]
            eyeMaterial = em2
            let leftEyeNode = SCNNode(geometry: eyeGeo)
            leftEyeNode.position = SCNVector3(
                Float(-headRadius * 0.35),
                Float(headRadius * 0.15),
                Float(-headRadius * 0.85)
            )
            let rightEyeNode = SCNNode(geometry: eyeGeo)
            rightEyeNode.position = SCNVector3(
                Float(headRadius * 0.35),
                Float(headRadius * 0.15),
                Float(-headRadius * 0.85)
            )

            headNode = SCNNode()
            headNode.addChildNode(craniumNode)
            headNode.addChildNode(noseNode)
            headNode.addChildNode(leftEarNode)
            headNode.addChildNode(rightEarNode)
            headNode.addChildNode(leftEyeNode)
            headNode.addChildNode(rightEyeNode)
            headNode.position = SCNVector3Zero  // listener at origin

            super.init()

            scene.rootNode.addChildNode(cameraTarget)
            scene.rootNode.addChildNode(cameraNode)
            scene.rootNode.addChildNode(ambientNode)
            scene.rootNode.addChildNode(cubeNode)
            cubeNode.addChildNode(axisNode)
            scene.rootNode.addChildNode(headNode)
            scene.rootNode.addChildNode(dotNode)

            // -- Trail spheres --
            for i in 0..<trailCount {
                let trailSphere = SCNSphere(radius: 0.06)
                let trailMat = SCNMaterial()
                trailMat.lightingModel = .constant
                let opacity = CGFloat(1.0) - (CGFloat(i) / CGFloat(trailCount))
                trailMat.transparency = opacity * 0.6
                trailSphere.materials = [trailMat]
                let node = SCNNode(geometry: trailSphere)
                node.isHidden = true  // Hidden until first positions are computed
                scene.rootNode.addChildNode(node)
                trailNodes.append(node)
            }

            applyColorScheme(isDark: isDark)
        }

        /// Updates all color-scheme-dependent materials for light or dark mode.
        func applyColorScheme(isDark: Bool) {
            self.isDark = isDark

            let cyan = UIColor(red: 0.31, green: 0.74, blue: 0.83, alpha: 1.0)

            if isDark {
                faceMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.12)
                faceMaterial.transparency = 0.7
                edgeMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.4)
                headMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.25)
                noseMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.35)
                earMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.2)
                dotMaterial.diffuse.contents = cyan
                dotMaterial.emission.contents = cyan
                eyeMaterial.diffuse.contents = cyan
                eyeMaterial.emission.contents = cyan.withAlphaComponent(0.5)
                for entry in axisMaterials {
                    entry.material.diffuse.contents = entry.color.withAlphaComponent(0.7)
                }
                for node in trailNodes {
                    node.geometry?.firstMaterial?.diffuse.contents = cyan
                    node.geometry?.firstMaterial?.emission.contents = cyan
                }
            } else {
                faceMaterial.diffuse.contents = UIColor(white: 0.82, alpha: 1.0)
                faceMaterial.transparency = 0.5
                edgeMaterial.diffuse.contents = UIColor.black
                headMaterial.diffuse.contents = UIColor(white: 0.7, alpha: 1.0)
                noseMaterial.diffuse.contents = UIColor(white: 0.6, alpha: 1.0)
                earMaterial.diffuse.contents = UIColor(white: 0.65, alpha: 1.0)
                dotMaterial.diffuse.contents = UIColor.black
                dotMaterial.emission.contents = UIColor.black
                eyeMaterial.diffuse.contents = UIColor.black
                eyeMaterial.emission.contents = UIColor.clear
                for entry in axisMaterials {
                    entry.material.diffuse.contents = entry.color
                }
                for node in trailNodes {
                    node.geometry?.firstMaterial?.diffuse.contents = UIColor.black
                    node.geometry?.firstMaterial?.emission.contents = UIColor.clear
                }
            }
        }

        // MARK: SCNSceneRendererDelegate

        func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
            if startTime == 0 { startTime = time }
            let t = time - startTime

            // Read live parameters from the Rose object
            let amp = rose.amp.val
            let freq = rose.freq.val
            let leafFactor = rose.leafFactor.val

            // Compute Rose position (same formula as Rose.of(t))
            let domain = freq * t + Double(rose.phase)
            let x = amp * sin(leafFactor * domain) * cos(domain)
            let y = amp * sin(leafFactor * domain) * sin(domain)
            let z = amp * sin(domain)

            let pos = SCNVector3(Float(x), Float(y), Float(z))

            // Update dot
            dotNode.position = pos

            // Shift trail: move each trail node to the position of the one before it
            for i in stride(from: trailCount - 1, through: 1, by: -1) {
                trailNodes[i].position = trailNodes[i - 1].position
                trailNodes[i].isHidden = trailNodes[i - 1].isHidden
            }
            trailNodes[0].position = pos
            trailNodes[0].isHidden = false

            // Resize cube faces, edges, and axes to match current amplitude
            let side = CGFloat(amp * 2)
            if let box = cubeNode.childNodes.first?.geometry as? SCNBox,
               abs(box.width - side) > 0.01 {
                box.width = side
                box.height = side
                box.length = side
                let newEdge = Coordinator.cubeEdgeGeometry(side: side)
                newEdge.materials = [edgeMaterial]
                edgeNode.geometry = newEdge
                if initialAmp > 0 {
                    let s = Float(amp) / initialAmp
                    axisNode.scale = SCNVector3(s, s, s)
                    headNode.scale = SCNVector3(s, s, s)
                }
            }
        }

        /// Creates an SCNGeometry containing only the 12 edges of a cube as line segments.
        static func cubeEdgeGeometry(side: CGFloat) -> SCNGeometry {
            let h = Float(side / 2)
            // 8 corners of the cube
            let corners: [SCNVector3] = [
                SCNVector3(-h, -h, -h), // 0
                SCNVector3( h, -h, -h), // 1
                SCNVector3( h,  h, -h), // 2
                SCNVector3(-h,  h, -h), // 3
                SCNVector3(-h, -h,  h), // 4
                SCNVector3( h, -h,  h), // 5
                SCNVector3( h,  h,  h), // 6
                SCNVector3(-h,  h,  h), // 7
            ]
            // 12 edges as pairs of vertex indices
            let edgeIndices: [Int32] = [
                0,1, 1,2, 2,3, 3,0,  // back face
                4,5, 5,6, 6,7, 7,4,  // front face
                0,4, 1,5, 2,6, 3,7,  // connecting edges
            ]
            let source = SCNGeometrySource(vertices: corners)
            let element = SCNGeometryElement(
                indices: edgeIndices,
                primitiveType: .line
            )
            let geometry = SCNGeometry(sources: [source], elements: [element])
            return geometry
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
    .frame(height: 300)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding()
}
