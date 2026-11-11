import Cocoa
import Foundation
import AVFoundation
import CoreMedia
import Network
import UniformTypeIdentifiers
import SwiftUI
import CGoom
@testable import MacAmp

func pluginTests() {
    testGroup("Plug-ins: mechanism and in_ffmpeg commands (1.2)") {
        // A stand-in plug-in: shell scripts instead of FFmpeg
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/plugins-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("Stub.macampplugin")
        let macos = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let info: [String: Any] = ["MacAmpPluginKind": "converter", "MacAmpPluginTitle": "Stub [in_stub]",
                                   "MacAmpPluginAudioExtensions": ["xyz", "slow", "bad"], "MacAmpPluginVideoExtensions": ["vid"]]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        // ffprobe: one audio stream, 2 s; ffmpeg: progress lines then the output file (its last argument)
        try "#!/bin/sh\necho '{\"streams\":[{\"index\":0,\"codec_type\":\"audio\",\"codec_name\":\"wmav2\"}],\"format\":{\"duration\":\"2.0\"}}'\n"
            .write(to: macos.appendingPathComponent("ffprobe"), atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        for last; do :; done
        case "$*" in *.slow*) sleep 10 ;; *.bad*) echo "Invalid data found when processing input" >&2; exit 1 ;; esac
        echo out_time_us=1000000; echo out_time_us=2000000
        echo converted > "$last"
        """.write(to: macos.appendingPathComponent("ffmpeg"), atomically: true, encoding: .utf8)
        for tool in ["ffprobe", "ffmpeg"] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macos.appendingPathComponent(tool).path) }
        // As if downloaded: macOS marks it, MacAmp clears the mark on install (after the user's yes)
        setxattr(bundle.path, "com.apple.quarantine", "0081;00000000;Safari;", 21, 0, 0)
        assertTrue(!AppConstants.Audio.supportedExtensions.contains("xyz"), "Formats unknown before the install")
        let installed = try PluginManager.install(bundle)
        assertEqual(installed.title, "Stub [in_stub]", "Plug-in read")
        let target = PluginManager.folder.appendingPathComponent("Stub.macampplugin")
        assertTrue(getxattr(target.path, "com.apple.quarantine", nil, 0, 0, 0) < 0, "Quarantine mark removed")
        assertTrue(AppConstants.Audio.supportedExtensions.isSuperset(of: ["xyz", "vid"]), "Its formats are playable now")
        assertTrue(VideoController.isVideo(URL(fileURLWithPath: "/m/a.vid")) && !VideoController.isVideo(URL(fileURLWithPath: "/m/a.xyz")), "Video formats known")

        // Converting: once, with progress, cached
        let input = root.appendingPathComponent("song.xyz")
        try "data".write(to: input, atomically: true, encoding: .utf8)
        var fractions: [Double] = []
        PluginConversion.onProgress = { _, f in fractions.append(f) }
        let output = awaitValue { try? await PluginConversion.convert(input) }
        _ = spinRunLoop(until: { fractions.count >= 2 }, timeout: 2)
        PluginConversion.onProgress = nil
        assertEqual(output?.pathExtension, "flac", "Audio becomes FLAC")
        assertEqual(output.flatMap { try? String(contentsOf: $0, encoding: .utf8) }, "converted\n", "Plug-in output kept")
        assertEqual(fractions, [0.5, 1.0], "Progress from ffmpeg's out_time")
        assertEqual(PluginConversion.cachedOutput(for: input), output, "Cached for next time")
        // Errors come back with ffmpeg's message; cancelling stops ffmpeg and leaves nothing behind
        let bad = root.appendingPathComponent("broken.bad")
        try "x".write(to: bad, atomically: true, encoding: .utf8)
        let failure = awaitValue { () -> String in
            do { _ = try await PluginConversion.convert(bad); return "" } catch { return error.localizedDescription }
        }
        assertEqual(failure, "Invalid data found when processing input", "Plug-in error shown")
        let slow = root.appendingPathComponent("long.slow")
        try "x".write(to: slow, atomically: true, encoding: .utf8)
        let started = Date()
        let task = Task { try await PluginConversion.convert(slow) }
        _ = spinRunLoop(until: { false }, timeout: 0.5)
        task.cancel()
        let cancelled = awaitValue { (try? await task.value) == nil }
        assertTrue(cancelled && Date().timeIntervalSince(started) < 5, "Cancel stops ffmpeg at once")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: PluginConversion.cacheFolder.path)) ?? []
        assertTrue(!leftovers.contains { $0.contains("partial") }, "No partial file left")
        // Stop (handleStop → cancelAll) ends a running conversion too
        let other = root.appendingPathComponent("other.slow")
        try "y".write(to: other, atomically: true, encoding: .utf8)
        let stopped = Date()
        let running = Task { try await PluginConversion.convert(other) }
        _ = spinRunLoop(until: { false }, timeout: 0.5)
        PluginConversion.cancelAll()
        let ended = awaitValue { (try? await running.value) == nil }
        assertTrue(ended && Date().timeIntervalSince(stopped) < 5, "Stop ends the conversion")

        // The commands in_ffmpeg gets
        func probe(_ json: String) -> PluginConversion.Probe { try! JSONDecoder().decode(PluginConversion.Probe.self, from: Data(json.utf8)) }
        let mkv = probe(#"{"streams":[{"index":0,"codec_type":"video","codec_name":"h264","height":1080},{"index":1,"codec_type":"audio","codec_name":"aac"},{"index":2,"codec_type":"audio","codec_name":"opus"},{"index":3,"codec_type":"subtitle","codec_name":"subrip"},{"index":4,"codec_type":"subtitle","codec_name":"hdmv_pgs_subtitle"},{"index":5,"codec_type":"video","codec_name":"mjpeg","disposition":{"attached_pic":1}}],"format":{"duration":"60"}}"#)
        let (mkvArgs, mkvExt) = PluginConversion.arguments(for: mkv)
        assertEqual(mkvExt, "mp4", "Video becomes MP4")
        assertEqual(mkvArgs, ["-map", "0:0", "-c:v", "copy", "-map", "0:1", "-c:a:0", "copy", "-map", "0:2", "-c:a:1", "aac", "-b:a:1", "192k",
                              "-map", "0:3", "-c:s", "mov_text", "-map_metadata", "0"],
                    "H.264 and AAC copied, Opus to AAC, text subtitles kept, picture subtitles and cover art left out")
        let avi = probe(#"{"streams":[{"index":0,"codec_type":"video","codec_name":"mpeg4","height":480},{"index":1,"codec_type":"audio","codec_name":"mp3"}]}"#)
        assertEqual(Array(PluginConversion.arguments(for: avi).args.prefix(8)), ["-map", "0:0", "-c:v", "h264_videotoolbox", "-b:v", "2500k", "-pix_fmt", "yuv420p"],
                    "Xvid re-encoded with the hardware H.264 encoder")
        let hevc = probe(#"{"streams":[{"index":0,"codec_type":"video","codec_name":"hevc"}]}"#)
        assertTrue(PluginConversion.arguments(for: hevc).args.contains("hvc1"), "HEVC tagged so macOS plays it")
        let song = probe(#"{"streams":[{"index":0,"codec_type":"audio","codec_name":"ape"},{"index":1,"codec_type":"video","codec_name":"png","disposition":{"attached_pic":1}}]}"#)
        assertEqual(PluginConversion.arguments(for: song).ext, "flac", "Audio with cover art is still audio")

        try? FileManager.default.removeItem(at: target)
        PluginManager.reload()
        assertTrue(!AppConstants.Audio.supportedExtensions.contains("xyz"), "Formats gone with the plug-in")
    }

    testGroup("in_ffmpeg plug-in on real files (needs scripts/build_ffmpeg_plugin.sh)") {
        let built = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/plugins/MacAmp FFmpeg.macampplugin")
        guard FileManager.default.fileExists(atPath: built.path) else { print("  (skipped: plug-in not built)"); return }
        _ = try PluginManager.install(built)
        defer { try? FileManager.default.removeItem(at: PluginManager.folder.appendingPathComponent(built.lastPathComponent)); PluginManager.reload() }
        for name in ["plugin-test.wma", "plugin-test.wv"] {
            let flac = awaitValue { try? await PluginConversion.convert(fixtures.appendingPathComponent(name)) }
            let file = flac.flatMap { try? AVAudioFile(forReading: $0) }
            assertTrue(file.map { abs(Double($0.length) / $0.fileFormat.sampleRate - 2) < 0.1 } ?? false, "\(name) → FLAC, 2 s")
        }
        // MKV: H.264 copied, both audio tracks with languages, subtitles as text
        let mkv = awaitValue { try? await PluginConversion.convert(fixtures.appendingPathComponent("plugin-test.mkv")) }
        let asset = mkv.map { AVURLAsset(url: $0) }
        let video = awaitValue { (try? await asset?.loadTracks(withMediaType: .video).first?.load(.isPlayable)) ?? false }
        let audio = awaitValue { (try? await asset?.loadTracks(withMediaType: .audio).count) ?? 0 }
        let subs = awaitValue { (try? await asset?.loadMediaSelectionGroup(for: .legible)?.options.count) ?? 0 }
        assertTrue(video, "MKV picture plays")
        assertEqual(audio, 2, "Both audio tracks kept")
        assertTrue(subs >= 1, "Subtitles kept as text")
        let tracks = awaitValue { await VideoTracks.audioTracks(of: mkv!) }
        assertEqual(tracks.map(\.title), ["Russian (AAC, 1 ch)", "English (AAC, 1 ch)"], "Track languages carried over")
        // AVI with Xvid: re-encoded to H.264 that macOS plays
        let avi = awaitValue { try? await PluginConversion.convert(fixtures.appendingPathComponent("plugin-test.avi")) }
        let aviCodec = awaitValue { () -> String in
            guard let avi, let track = try? await AVURLAsset(url: avi).loadTracks(withMediaType: .video).first,
                  let format = try? await track.load(.formatDescriptions).first else { return "" }
            return VideoController.fourCC(CMFormatDescriptionGetMediaSubType(format))
        }
        assertEqual(aviCodec, "avc1", "Xvid became H.264")
        // Through the engine as any track
        let engine = AudioEngine.shared
        defer { engine.stop() }
        let meta = try loadSync(engine, fixtures.appendingPathComponent("plugin-test.mkv"))
        assertTrue(abs(meta.duration - 2) < 0.2, "Engine plays the MKV's sound (\(meta.duration) s)")
    }
}
