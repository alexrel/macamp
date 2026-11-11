import Cocoa
import Foundation
import AVFoundation
import CoreMedia
import Network
import UniformTypeIdentifiers
import SwiftUI
import CGoom
@testable import MacAmp

/// The checkout these tests were compiled from (this file is scripts/tests/Support.swift).
let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let fixtures = repositoryRoot.appendingPathComponent("scripts/fixtures")

/// Test groups run on the main thread, where the app's UI and coordinator live.
func testGroup(_ name: String, _ block: @MainActor () throws -> Void) {
    print("\n📦 Test Suite: \(name)")
    do {
        try MainActor.assumeIsolated { try block() }
        print("  ✅ All tests in '\(name)' passed successfully.")
    } catch {
        print("  ❌ Test suite '\(name)' FAILED: \(error)")
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("    ❌ Assertion Failed: \(message) [\(file):\(line)]")
        exit(1)
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("    ❌ Assertion Failed: Expected [\(expected)], got [\(actual)]. \(message) [\(file):\(line)]")
        exit(1)
    }
}

// MARK: - Playback regression helpers
/// Runs async work on the main actor and waits for its result, pumping the run loop meanwhile.
@MainActor
func awaitValue<T>(_ work: @escaping @MainActor () async -> T) -> T {
    var result: T?
    Task { @MainActor in result = await work() }
    _ = spinRunLoop(until: { result != nil }, timeout: 30)
    return result!
}

func spinRunLoop(until condition: () -> Bool, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}

func makeTestWAV(named name: String, seconds: Double) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    let frames = AVAudioFrameCount(seconds * 44100)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for ch in 0..<Int(format.channelCount) {
        let data = buffer.floatChannelData![ch]
        for i in 0..<Int(frames) { data[i] = 0.001 * sinf(Float(i) * 0.05) } // near-silent tone
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
}

func loadSync(_ engine: AudioEngine, _ url: URL) throws -> TrackMetadata {
    var result: Result<TrackMetadata, Error>?
    Task { @MainActor in
        do { result = .success(try await engine.load(url: url)) } catch { result = .failure(error) }
    }
    guard spinRunLoop(until: { result != nil }, timeout: 5) else { throw NSError(domain: "test", code: 1) }
    return try result!.get()
}

// 18. Internet radio through the engine (§5): ICY demux, decode, EQ path, reconnect
final class TestRadioServer {
    let listener: NWListener
    private(set) var connections = 0
    private let body: Data
    private let queue = DispatchQueue(label: "test.radio")
    var port: UInt16 { listener.port?.rawValue ?? 0 }
    
    init(audio: Data, metaInt: Int, title: String) throws {
        // Interleave ICY metadata after every metaInt audio bytes
        var out = Data()
        var offset = 0
        var first = true
        while offset < audio.count {
            let end = min(audio.count, offset + metaInt)
            out.append(audio[offset..<end])
            offset = end
            if end - (end - metaInt) == metaInt && offset <= audio.count {
                var meta = first ? Data("StreamTitle='\(title)';".utf8) : Data()
                first = false
                let blocks = (meta.count + 15) / 16
                meta.append(Data(count: blocks * 16 - meta.count))
                out.append(UInt8(blocks))
                out.append(meta)
            }
        }
        body = out
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] conn in self?.serve(conn) }
        listener.start(queue: queue)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in if case .ready = state { ready.signal() } }
        _ = ready.wait(timeout: .now() + 2)
    }
    
    private func serve(_ conn: NWConnection) {
        connections += 1
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [body, queue] _, _, _, _ in
          // Answer a moment later so the client has pressed Play before the burst ends
          queue.asyncAfter(deadline: .now() + 0.4) {
            let header = "HTTP/1.0 200 OK\r\nContent-Type: audio/aac\r\nicy-metaint: 4096\r\nicy-name: Test Radio\r\nicy-genre: Rock\r\n\r\n"
            conn.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in
                // Drop the connection after the burst, like a flaky server
                conn.cancel()
            })
          }
        }
    }
    
    func stop() { listener.cancel() }
}

func makeTestADTS(seconds: Double) throws -> Data {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("radio.aac")
    try? FileManager.default.removeItem(at: url)
    do {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128000]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * 44100)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        for c in 0..<2 { for i in 0..<Int(frames) { buf.floatChannelData![c][i] = 0.002 * sinf(Float(i) * 0.05) } }
        try file.write(from: buf)
    } // file closed here
    return try Data(contentsOf: url)
}

// 21. File types: associations, Info.plist, Finder integration
final class FakeLaunchServices: DefaultAppProvider {
    var defaults: [String: URL] = [:]
    var installed: [URL] = []
    var setCalls: [(String, URL)] = []
    func defaultApplication(for type: UTType) -> URL? { defaults[type.identifier] }
    func applications(for type: UTType) -> [URL] { installed }
    func setDefaultApplication(_ app: URL, for type: UTType) async throws {
        setCalls.append((type.identifier, app))
        defaults[type.identifier] = app
    }
}

func runMain(_ work: @escaping @MainActor () async -> Void) {
    var done = false
    Task { @MainActor in await work(); done = true }
    _ = spinRunLoop(until: { done }, timeout: 10)
}

// 22. Document icon chooser, Setup page settings
final class RecordingInstaller: BundleIconInstaller {
    let real = SystemBundleIconInstaller()
    var registered: [URL] = []
    func install(icon: URL, as target: URL) throws { try real.install(icon: icon, as: target) }
    func resign(bundle: URL) throws { try real.resign(bundle: bundle) }
    func register(bundle: URL) { registered.append(bundle) } // never touch Launch Services in tests
    func verify(bundle: URL) -> Bool { real.verify(bundle: bundle) }
}

// 23. Playlists from other players, drag & drop into the playlist
final class FakeDrop: NSObject, NSDraggingInfo {
    let pasteboard: NSPasteboard
    let location: NSPoint
    init(urls: [URL], location: NSPoint) {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("macamp-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        self.location = location
    }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation { get { .default } set {} }
    var animatesToDestination: Bool { get { false } set {} }
    var numberOfValidItemsForDrop: Int { get { 0 } set {} }
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}
