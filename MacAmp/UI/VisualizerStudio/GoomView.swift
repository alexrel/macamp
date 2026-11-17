import AppKit
import CGoom
import SceneKit
import os

final class GoomView: NSView {
    private static let log = Logger(subsystem: "alexrel.MacAmp", category: "GOOM")
    private static let pcmFrames = 512
    static let cubeTextureSize = 256
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    private var samples = [Float](repeating: 0, count: pcmFrames * 2)
    private var sampleCount = 0
    private var dimensions: (width: Int, height: Int, cinemascope: Bool)?
    private var effect: Int32 = 0
    private(set) var lastForcedEffect: Int?
    private var frameCount = 0
    private(set) var fps: Float = 0
    private var measurementStart = CACurrentMediaTime()

    private var sceneView: SCNView?
    private let cube = SCNNode()
    private let camera = SCNNode()
    private let texture = SCNMaterial()
    private var cameraDistance: CGFloat = 5
    private var displayActivity: NSObjectProtocol?

    var isCube: Bool { sceneView != nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest
        setAccessibilityLabel("What A Goom!")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        if let displayActivity { ProcessInfo.processInfo.endActivity(displayActivity) }
        if dimensions != nil { macamp_goom_stop() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setVisible(_ visible: Bool) {
        if visible && displayActivity == nil {
            measurementStart = CACurrentMediaTime()
            frameCount = 0
            displayActivity = ProcessInfo.processInfo.beginActivity(options: .idleDisplaySleepDisabled,
                                                                    reason: "GOOM visualization is visible")
        } else if !visible, let displayActivity {
            ProcessInfo.processInfo.endActivity(displayActivity)
            self.displayActivity = nil
            sampleCount = 0
        }
    }

    func forceEffect(_ number: Int) {
        effect = Int32(number)
        lastForcedEffect = number
    }
    func moveCamera(by step: CGFloat) {
        cameraDistance = min(100, max(2, cameraDistance + step))
    }

    func toggleCube() {
        if let sceneView {
            sceneView.removeFromSuperview()
            self.sceneView = nil
            return
        }
        layer?.contents = nil
        let scene = SCNScene()
        scene.background.contents = NSColor.black
        let geometry = SCNBox(width: 2, height: 2, length: 2, chamferRadius: 0)
        texture.lightingModel = .constant
        geometry.materials = [texture]
        cube.geometry = geometry
        cube.eulerAngles = SCNVector3Zero
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 45
        camera.position = SCNVector3(0, 0, cameraDistance)
        scene.rootNode.addChildNode(camera)
        scene.rootNode.addChildNode(cube)

        let view = SCNView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        view.scene = scene
        view.pointOfView = camera
        view.antialiasingMode = .none
        addSubview(view)
        sceneView = view
    }

    /// The title and the frame rate are the Studio's hints now, shown the same way over every visualizer
    func renderFrame(playing: Bool) {
        let options = PersistenceManager.shared.state.goomOptions
        let width = isCube ? Self.cubeTextureSize : options.renderWidth
        let height = isCube ? Self.cubeTextureSize : options.renderHeight
        if dimensions?.width != width || dimensions?.height != height || dimensions?.cinemascope != options.cinemascope {
            let configure = dimensions == nil ? macamp_goom_start : macamp_goom_resize
            guard configure(UInt32(width), UInt32(height), options.cinemascope) else {
                Self.log.error("Could not configure GOOM at \(width)×\(height)")
                return
            }
            dimensions = (width, height, options.cinemascope)
        }

        if playing {
            VisualizerPCMFeed.consume { source, count in
                sampleCount = min(count, Self.pcmFrames)
                samples.withUnsafeMutableBufferPointer {
                    $0.baseAddress?.update(from: source.advanced(by: (count - sampleCount) * 2), count: sampleCount * 2)
                }
            }
        } else {
            sampleCount = 0
        }
        let pixels = samples.withUnsafeBufferPointer {
            macamp_goom_render($0.baseAddress, UInt32(sampleCount), effect, -1, nil, nil)
        }
        effect = 0
        if let pixels {
            let bytes = Data(bytes: pixels, count: width * height * 4)
            if let provider = CGDataProvider(data: bytes as CFData),
               let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: width * 4, space: Self.colorSpace,
                                   bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)],
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
                if let sceneView {
                    texture.diffuse.contents = image
                    updateCube()
                    sceneView.needsDisplay = true
                } else {
                    layer?.contents = image
                }
            }
        }
        frameCount += 1
        let now = CACurrentMediaTime()
        if now - measurementStart >= 1 {
            fps = Float(Double(frameCount) / (now - measurementStart))
            measurementStart = now
            frameCount = 0
        }
    }

    private func updateCube() {
        let radians = CGFloat.pi / 180
        cube.eulerAngles.x += 0.3 * radians
        cube.eulerAngles.y += 0.2 * radians
        cube.eulerAngles.z += 0.4 * radians
        camera.position.z = cameraDistance
    }
}
