import SceneKit
import SpriteKit

/// Tools modelled in 3D and pre-rendered as frames of a slow swivel, so they look like objects rather than icons.
/// A swivel rather than a full turn keeps them from ever being seen end-on.
enum ToolModels {
    static func swivel(_ tool: DeskScene.Tool, frames: Int = 48, side: CGFloat = 60) -> [SKTexture] {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let spin = SCNNode()
        spin.addChildNode(model(of: tool))
        scene.rootNode.addChildNode(spin)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 30
        camera.position = SCNVector3(0, 0.3, 3.05)
        camera.eulerAngles.x = -0.13
        scene.rootNode.addChildNode(camera)
        light(scene, .omni, at: SCNVector3(2.5, 3, 3), intensity: 1000)
        light(scene, .omni, at: SCNVector3(-3, 1, -2.5), intensity: 600)
        light(scene, .ambient, at: SCNVector3(0, 0, 0), intensity: 380)

        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let size = CGSize(width: side * 2, height: side * 2)
        return (0..<frames).map { i in
            spin.eulerAngles.y = 0.6 + 0.8 * sin(CGFloat(i) / CGFloat(frames) * 2 * .pi)
            return SKTexture(image: renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X))
        }
    }

    /// A tool drawn as a mouse pointer: tilted so it reaches the pointer from the lower right. `hotspot` is where it
    /// strikes or fires and `grip` where a hand would hold it, both in points from the texture's bottom-left.
    struct CursorArt {
        let frames: [SKTexture]
        let size: CGSize
        let hotspot: CGPoint
        let grip: CGPoint
        /// Where spent cases fly out.
        let eject: CGPoint
    }

    static func cursor(_ tool: DeskScene.Tool, side: CGFloat = 72) -> CursorArt {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let yaw = SCNNode(), roll = SCNNode()
        yaw.eulerAngles.y = tool == .hammer ? 0.45 : 0.35
        roll.eulerAngles.z = tool == .hammer ? 0.78 : 0.72
        let body = SCNNode()
        tool == .hammer ? buildHammer(in: body) : buildMinigun(in: body)
        roll.addChildNode(body)
        yaw.addChildNode(roll)
        scene.rootNode.addChildNode(yaw)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 30
        camera.position = SCNVector3(0, 0, 3.6)
        scene.rootNode.addChildNode(camera)
        light(scene, .omni, at: SCNVector3(2.5, 3, 3), intensity: 1000)
        light(scene, .omni, at: SCNVector3(-3, 1, -2.5), intensity: 600)
        light(scene, .ambient, at: SCNVector3(0, 0, 0), intensity: 380)

        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let pixels = CGSize(width: side * 2, height: side * 2)
        let barrels = body.childNode(withName: "barrels", recursively: false)
        // Six barrels repeat every 60°, so six frames across that arc make a seamless spin.
        let frameCount = barrels == nil ? 1 : 6
        let frames = (0..<frameCount).map { i -> SKTexture in
            barrels?.eulerAngles.y = CGFloat(i) / CGFloat(frameCount) * .pi / 3
            return SKTexture(image: renderer.snapshot(atTime: 0, with: pixels, antialiasingMode: .multisampling4X))
        }
        func project(_ local: SCNVector3) -> CGPoint {
            let p = renderer.projectPoint(body.convertPosition(local, to: nil))
            return CGPoint(x: p.x / 2, y: p.y / 2)
        }
        let tip = tool == .hammer ? SCNVector3(-0.39, 0.66, 0) : SCNVector3(0, 0.95, 0)
        let grip = tool == .hammer ? SCNVector3(0, -0.7, 0) : SCNVector3(0.3, -0.32, 0)
        return CursorArt(frames: frames, size: CGSize(width: side, height: side), hotspot: project(tip), grip: project(grip),
                         eject: project(SCNVector3(0.24, -0.08, 0)))
    }

    private static func light(_ scene: SCNScene, _ type: SCNLight.LightType, at position: SCNVector3, intensity: CGFloat) {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = type
        node.light?.intensity = intensity
        node.position = position
        scene.rootNode.addChildNode(node)
    }

    private static func model(of tool: DeskScene.Tool) -> SCNNode {
        let root = SCNNode()
        switch tool {
        case .hammer: buildHammer(in: root)
        case .minigun: buildMinigun(in: root)
        }
        root.eulerAngles.z = tool == .minigun ? -1.0 : -0.62
        return root
    }

    private static func material(_ color: NSColor, shine: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = color
        m.specular.contents = NSColor(white: shine, alpha: 1)
        m.shininess = 0.35 + shine * 0.5
        return m
    }

    private static func add(_ geometry: SCNGeometry, _ material: SCNMaterial, to parent: SCNNode,
                            at position: SCNVector3, rotation: SCNVector3 = SCNVector3(0, 0, 0)) {
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = position
        node.eulerAngles = rotation
        parent.addChildNode(node)
    }

    private static func buildHammer(in root: SCNNode) {
        let wood = material(NSColor(red: 0.58, green: 0.37, blue: 0.2, alpha: 1), shine: 0.25)
        let grip = material(NSColor(red: 0.12, green: 0.05, blue: 0.05, alpha: 1), shine: 0.1)
        let steel = material(NSColor(white: 0.62, alpha: 1), shine: 1)
        add(SCNCylinder(radius: 0.06, height: 1.5), wood, to: root, at: SCNVector3(0, -0.12, 0))
        add(SCNCylinder(radius: 0.078, height: 0.5), grip, to: root, at: SCNVector3(0, -0.62, 0))
        add(SCNBox(width: 0.6, height: 0.22, length: 0.22, chamferRadius: 0.03), steel, to: root, at: SCNVector3(0, 0.66, 0))
        add(SCNCylinder(radius: 0.13, height: 0.1), steel, to: root, at: SCNVector3(-0.34, 0.66, 0),
            rotation: SCNVector3(0, 0, CGFloat.pi / 2))
        for side in [-1.0, 1.0] as [CGFloat] {
            add(SCNBox(width: 0.32, height: 0.07, length: 0.07, chamferRadius: 0.02), steel, to: root,
                at: SCNVector3(0.42, 0.6, side * 0.05), rotation: SCNVector3(0, 0, -0.55))
        }
    }

    private static func buildMinigun(in root: SCNNode) {
        let gunmetal = material(NSColor(red: 0.5, green: 0.52, blue: 0.56, alpha: 1), shine: 0.9)
        let dark = material(NSColor(white: 0.26, alpha: 1), shine: 0.5)
        let brass = material(NSColor(red: 0.78, green: 0.58, blue: 0.24, alpha: 1), shine: 0.9)
        let barrels = SCNNode()
        barrels.name = "barrels"
        root.addChildNode(barrels)
        for k in 0..<6 {
            let angle = CGFloat(k) / 6 * 2 * .pi
            add(SCNCylinder(radius: 0.045, height: 1.3), gunmetal, to: barrels,
                at: SCNVector3(cos(angle) * 0.12, 0.3, sin(angle) * 0.12))
        }
        add(SCNCylinder(radius: 0.19, height: 0.06), dark, to: barrels, at: SCNVector3(0, 0.82, 0))
        add(SCNCylinder(radius: 0.19, height: 0.06), dark, to: barrels, at: SCNVector3(0, 0.28, 0))
        add(SCNCylinder(radius: 0.23, height: 0.5), dark, to: root, at: SCNVector3(0, -0.22, 0))
        add(SCNTorus(ringRadius: 0.23, pipeRadius: 0.025), brass, to: root, at: SCNVector3(0, -0.05, 0))
        add(SCNCone(topRadius: 0.23, bottomRadius: 0.1, height: 0.18), gunmetal, to: root, at: SCNVector3(0, -0.56, 0))
        add(SCNBox(width: 0.08, height: 0.34, length: 0.1, chamferRadius: 0.02), dark, to: root,
            at: SCNVector3(0.3, -0.32, 0), rotation: SCNVector3(0, 0, 0.25))
        add(SCNBox(width: 0.07, height: 0.42, length: 0.07, chamferRadius: 0.02), gunmetal, to: root,
            at: SCNVector3(-0.29, -0.15, 0))
    }
}
