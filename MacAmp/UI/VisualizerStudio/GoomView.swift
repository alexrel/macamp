import AppKit
import CGoom
import SceneKit
import os

final class GoomView: NSView {
    private static let log = Logger(subsystem: "alexrel.MacAmp", category: "GOOM")
    private static let pcmFrames = 512
    static let cubeTextureSize = 256
    private static let encoreLength = 32 * 60
    private static let titleDuration = 200
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    private var samples = [Float](repeating: 0, count: pcmFrames * 2)
    private var sampleCount = 0
    private var dimensions: (width: Int, height: Int, cinemascope: Bool)?
    private var effect: Int32 = 0
    private(set) var lastForcedEffect: Int?
    private var lastTitle: String?
    private let unicodeTitle = NSTextField(labelWithString: "")
    private var unicodeTitleFrames = 0
    private var messageIndex = 0
    private var encore = 0
    private var dismissCredits = false
    private var frameCount = 0
    private var fps: Float = 0
    private var measurementStart = CACurrentMediaTime()

    private var sceneView: SCNView?
    private let cube = SCNNode()
    private let camera = SCNNode()
    private let texture = SCNMaterial()
    private var cameraDistance: CGFloat = 5
    private var creditsRotationFrames = 0
    private var creditsRotationStart: CGFloat = 0
    private var displayActivity: NSObjectProtocol?

    var isCube: Bool { sceneView != nil }
    var isShowingCredits: Bool { encore > 0 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest
        unicodeTitle.alignment = .center
        unicodeTitle.lineBreakMode = .byTruncatingTail
        unicodeTitle.isHidden = true
        addSubview(unicodeTitle)
        setAccessibilityLabel("What A Goom!")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        if let displayActivity { ProcessInfo.processInfo.endActivity(displayActivity) }
        if dimensions != nil { macamp_goom_stop() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let title = bounds.insetBy(dx: 12, dy: 0)
        unicodeTitle.frame = NSRect(x: title.minX, y: title.midY - 10, width: title.width, height: 20)
    }

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
    func showCredits() { encore = Self.encoreLength }

    func hideCredits() {
        encore = 0
        dismissCredits = true
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
        addSubview(view, positioned: .below, relativeTo: unicodeTitle)
        sceneView = view
        creditsRotationFrames = 0
    }

    func renderFrame(playing: Bool, trackTitle: String?) {
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
        var message: String?
        if dismissCredits {
            message = ""
            dismissCredits = false
        } else if encore == Self.encoreLength {
            let messages = [
                "What a GOOM! version 1.99.4\n\n\n\n\n\n\n\nan iOS software production.\n\n\n\nhttp://ios.free.fr",
                macamp_goom_credits().map { String(cString: $0) } ?? "",
                "copyright (c)2000-2003, by jeko"
            ]
            message = messages[messageIndex]
            messageIndex = (messageIndex + 1) % messages.count
        }

        let titleUpdate = updateTitle(options.showTitle ? trackTitle : nil)
        let pixels = samples.withUnsafeBufferPointer {
            macamp_goom_render($0.baseAddress, UInt32(sampleCount), effect, options.showFPS ? fps : -1,
                               titleUpdate, message)
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
        encore = max(0, encore - 1)
        frameCount += 1
        let now = CACurrentMediaTime()
        if now - measurementStart >= 1 {
            fps = Float(Double(frameCount) / (now - measurementStart))
            measurementStart = now
            frameCount = 0
        }
    }

    private func updateTitle(_ title: String?) -> String? {
        defer {
            unicodeTitle.isHidden = unicodeTitleFrames == 0
            if unicodeTitleFrames > 0 { unicodeTitleFrames -= 1 }
        }
        guard title != lastTitle else { return nil }
        lastTitle = title
        // The original bitmap font only handles ASCII. Use AppKit's font fallback for other titles.
        if let title, title.utf8.contains(where: { $0 >= 0x80 }) {
            unicodeTitle.attributedStringValue = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .bold),
                .foregroundColor: NSColor.white,
                .strokeColor: NSColor.black,
                .strokeWidth: -3
            ])
            unicodeTitleFrames = Self.titleDuration
            return ""
        }
        unicodeTitleFrames = 0
        return title ?? ""
    }

    private func updateCube() {
        let radians = CGFloat.pi / 180
        let creditFrames = [32 * 15, 32 * 20, 32 * 35]
        if isShowingCredits && encore > Self.encoreLength - creditFrames[messageIndex] {
            if creditsRotationFrames == 0 { creditsRotationStart = cube.eulerAngles.z }
            creditsRotationFrames = min(60, creditsRotationFrames + 1)
            let progress = CGFloat(creditsRotationFrames) / 60
            cube.eulerAngles = SCNVector3(0, 0, creditsRotationStart + (-90 * radians - creditsRotationStart) * progress)
            camera.position.z = cameraDistance + (4 - cameraDistance) * progress
        } else {
            creditsRotationFrames = 0
            cube.eulerAngles.x += 0.3 * radians
            cube.eulerAngles.y += 0.2 * radians
            cube.eulerAngles.z += 0.4 * radians
            camera.position.z = cameraDistance
        }
    }
}
