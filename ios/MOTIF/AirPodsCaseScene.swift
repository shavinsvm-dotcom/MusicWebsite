import Combine
import SceneKit
import SwiftUI
import UIKit

/// A small, self-contained 3D AirPods case: a glossy white shell, a hinged
/// lid, a dark opening and two buds that rise out of it. Everything is built
/// from SceneKit primitives so there are no external model files.
final class AirPodsCaseSceneController: ObservableObject {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let root = SCNNode()
    private let lidPivot = SCNNode()
    private let leftBud = SCNNode()
    private let rightBud = SCNNode()
    private let ledGlow = SCNNode()

    private let restLeft = SCNVector3(-0.16, 0.47, 0.02)
    private let restRight = SCNVector3(0.16, 0.47, 0.02)
    private let outLeft = SCNVector3(-0.27, 1.10, 0.04)
    private let outRight = SCNVector3(0.27, 1.10, 0.04)

    private static let spring = CAMediaTimingFunction(
        controlPoints: 0.20, 1.22, 0.34, 1.0
    )
    private static let lift = CAMediaTimingFunction(
        controlPoints: 0.22, 1.14, 0.36, 1.0
    )
    private static let settle = CAMediaTimingFunction(name: .easeOut)

    init() {
        build()
        reset()
    }

    // MARK: - Playback

    func reset() {
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        root.position = SCNVector3(0, -0.38, 0)
        root.scale = SCNVector3(0.94, 0.94, 0.94)
        root.opacity = 0
        lidPivot.eulerAngles = SCNVector3(0, 0, 0)
        leftBud.position = restLeft
        rightBud.position = restRight
        leftBud.eulerAngles = SCNVector3(0, 0, 0)
        rightBud.eulerAngles = SCNVector3(0, 0, 0)
        ledGlow.opacity = 0
        SCNTransaction.commit()
    }

    /// Jumps straight to a state, used for Reduce Motion and the open
    /// starting point of a disconnect. Pass `visible: false` to keep the
    /// case hidden until `appear()` brings it in.
    func present(open: Bool, visible: Bool = true) {
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        root.position = visible ? SCNVector3(0, 0, 0) : SCNVector3(0, -0.38, 0)
        root.scale = visible ? SCNVector3(1, 1, 1) : SCNVector3(0.94, 0.94, 0.94)
        root.opacity = visible ? 1 : 0
        lidPivot.eulerAngles.x = open ? -1.82 : 0
        leftBud.position = open ? outLeft : restLeft
        rightBud.position = open ? outRight : restRight
        leftBud.eulerAngles.z = open ? 0.12 : 0
        rightBud.eulerAngles.z = open ? -0.12 : 0
        ledGlow.opacity = open ? 1 : 0
        SCNTransaction.commit()
    }

    func appear() {
        animate(0.62, Self.spring) {
            root.position = SCNVector3(0, 0, 0)
            root.scale = SCNVector3(1, 1, 1)
            root.opacity = 1
        }
    }

    func openLid() {
        animate(0.62, Self.lift) {
            lidPivot.eulerAngles.x = -1.82
        }
    }

    func budsOut() {
        animate(0.72, Self.spring) {
            leftBud.position = outLeft
            rightBud.position = outRight
            leftBud.eulerAngles.z = 0.12
            rightBud.eulerAngles.z = -0.12
            ledGlow.opacity = 1
        }
    }

    func retractBuds() {
        animate(0.55, Self.settle) {
            leftBud.position = restLeft
            rightBud.position = restRight
            leftBud.eulerAngles.z = 0
            rightBud.eulerAngles.z = 0
            ledGlow.opacity = 0
        }
    }

    func closeLid() {
        animate(0.52, Self.lift) {
            lidPivot.eulerAngles.x = 0
        }
    }

    // MARK: - Build

    private func build() {
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = Self.environmentMap()
        scene.lightingEnvironment.intensity = 1.05

        addCamera()
        addLights()

        root.position = SCNVector3(0, -0.38, 0)
        root.scale = SCNVector3(0.94, 0.94, 0.94)
        root.opacity = 0
        scene.rootNode.addChildNode(root)

        addCase()
        addLid()
        addBuds()
        addLED()
    }

    private func addCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 36
        camera.zNear = 0.1
        camera.zFar = 40
        camera.wantsHDR = true
        camera.bloomIntensity = 0.10
        camera.bloomThreshold = 0.90

        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0.20, 1.02, 3.55)

        let target = SCNNode()
        target.position = SCNVector3(0, 0.70, 0)
        scene.rootNode.addChildNode(target)

        let look = SCNLookAtConstraint(target: target)
        look.isGimbalLockEnabled = true
        cameraNode.constraints = [look]
        scene.rootNode.addChildNode(cameraNode)
    }

    private func addLights() {
        let key = SCNLight()
        key.type = .directional
        key.intensity = 720
        key.color = UIColor(white: 1.0, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 6
        key.shadowSampleCount = 16
        key.shadowBias = 0.004
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.95, 0.62, 0)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 260
        fill.color = UIColor(white: 1.0, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.30, -0.85, 0)
        scene.rootNode.addChildNode(fillNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 170
        ambient.color = UIColor(white: 0.96, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

    private func addCase() {
        let bodyGeometry = SCNBox(
            width: 1.02,
            height: 0.86,
            length: 0.48,
            chamferRadius: 0.19
        )
        bodyGeometry.materials = [Self.whitePlastic]
        let body = SCNNode(geometry: bodyGeometry)
        body.position = SCNVector3(0, 0.43, 0)
        root.addChildNode(body)

        // The dark recess that the lid is sitting on top of.
        let rimGeometry = SCNBox(
            width: 0.84,
            height: 0.12,
            length: 0.40,
            chamferRadius: 0.045
        )
        rimGeometry.materials = [Self.blackMatte]
        let rim = SCNNode(geometry: rimGeometry)
        rim.position = SCNVector3(0, 0.92, 0)
        root.addChildNode(rim)

        let seamGeometry = SCNBox(
            width: 0.92,
            height: 0.006,
            length: 0.006,
            chamferRadius: 0.002
        )
        seamGeometry.materials = [Self.darkMatte]
        let seam = SCNNode(geometry: seamGeometry)
        seam.position = SCNVector3(0, 0.86, 0.241)
        root.addChildNode(seam)

        let hingeGeometry = SCNCylinder(radius: 0.032, height: 0.88)
        hingeGeometry.materials = [Self.greyMetal]
        let hinge = SCNNode(geometry: hingeGeometry)
        hinge.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        hinge.position = SCNVector3(0, 0.98, -0.243)
        root.addChildNode(hinge)

        let ledBase = SCNNode(geometry: SCNSphere(radius: 0.014))
        ledBase.geometry?.materials = [Self.darkMatte]
        ledBase.position = SCNVector3(0, 0.62, 0.243)
        root.addChildNode(ledBase)
    }

    private func addLid() {
        lidPivot.position = SCNVector3(0, 0.98, -0.24)
        root.addChildNode(lidPivot)

        let geometry = SCNBox(
            width: 1.02,
            height: 0.56,
            length: 0.48,
            chamferRadius: 0.19
        )
        geometry.materials = [Self.whitePlastic]
        let mesh = SCNNode(geometry: geometry)
        mesh.position = SCNVector3(0, 0.16, 0.24)
        lidPivot.addChildNode(mesh)
    }

    private func addBuds() {
        leftBud.addChildNode(makeBud(side: -1))
        leftBud.position = restLeft
        root.addChildNode(leftBud)

        rightBud.addChildNode(makeBud(side: 1))
        rightBud.position = restRight
        root.addChildNode(rightBud)
    }

    private func makeBud(side: CGFloat) -> SCNNode {
        let node = SCNNode()
        let offset = Float(side)

        let head = SCNNode(geometry: SCNSphere(radius: 0.135))
        head.geometry?.materials = [Self.whitePlastic]
        head.scale = SCNVector3(1.0, 1.04, 0.90)
        head.position = SCNVector3(0, 0.17, 0)
        node.addChildNode(head)

        let stem = SCNNode(geometry: SCNCapsule(capRadius: 0.042, height: 0.36))
        stem.geometry?.materials = [Self.whitePlastic]
        stem.position = SCNVector3(offset * 0.015, -0.06, 0)
        stem.eulerAngles = SCNVector3(0, 0, offset * -0.10)
        node.addChildNode(stem)

        // Speaker mesh on the side that faces the other bud.
        let mesh = SCNNode(geometry: SCNSphere(radius: 0.05))
        mesh.geometry?.materials = [Self.blackMatte]
        mesh.scale = SCNVector3(1.0, 1.0, 0.25)
        mesh.position = SCNVector3(-offset * 0.095, 0.19, 0.072)
        node.addChildNode(mesh)

        let tip = SCNNode(geometry: SCNCapsule(capRadius: 0.044, height: 0.05))
        tip.geometry?.materials = [Self.greyMetal]
        tip.position = SCNVector3(offset * 0.028, -0.25, 0)
        node.addChildNode(tip)

        return node
    }

    private func addLED() {
        ledGlow.geometry = SCNSphere(radius: 0.014)
        ledGlow.geometry?.materials = [Self.ledMaterial]
        ledGlow.position = SCNVector3(0, 0.62, 0.245)
        ledGlow.opacity = 0
        root.addChildNode(ledGlow)
    }

    // MARK: - Helpers

    private func animate(
        _ duration: TimeInterval,
        _ timing: CAMediaTimingFunction?,
        _ changes: () -> Void
    ) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = timing
        changes()
        SCNTransaction.commit()
    }

    private static func environmentMap() -> UIImage {
        let size = CGSize(width: 64, height: 256)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [
                UIColor.white.cgColor,
                UIColor(white: 0.62, alpha: 1).cgColor,
                UIColor(white: 0.10, alpha: 1).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.55, 1]
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }

    private static let whitePlastic: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(white: 0.97, alpha: 1)
        material.roughness.contents = 0.24
        material.metalness.contents = 0.0
        material.clearCoat.contents = 0.65
        material.clearCoatRoughness.contents = 0.10
        return material
    }()

    private static let blackMatte: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(white: 0.035, alpha: 1)
        material.roughness.contents = 0.85
        material.metalness.contents = 0.0
        return material
    }()

    private static let darkMatte: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(white: 0.16, alpha: 1)
        material.roughness.contents = 0.55
        return material
    }()

    private static let greyMetal: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(white: 0.58, alpha: 1)
        material.roughness.contents = 0.28
        material.metalness.contents = 0.9
        return material
    }()

    private static let ledMaterial: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: 0.49, green: 0.96, blue: 0.78, alpha: 1)
        material.emission.contents = UIColor(red: 0.38, green: 1.0, blue: 0.72, alpha: 1)
        material.emission.intensity = 2.2
        return material
    }()
}

struct AirPodsCaseSceneView: UIViewRepresentable {
    let controller: AirPodsCaseSceneController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = controller.scene
        view.pointOfView = controller.cameraNode
        view.backgroundColor = .clear
        view.isOpaque = false
        view.layer.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = controller.scene
        uiView.pointOfView = controller.cameraNode
    }
}
