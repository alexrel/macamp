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
                                   "MacAmpPluginAudioExtensions": ["xyz", "slow", "bad"], "MacAmpPluginVideoExtensions": ["vid"],
                                   "MacAmpPluginEncoders": ["ogg", "mp3"]]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        // ffprobe: one audio stream, 2 s; ffmpeg: progress lines then the output file (its last argument)
        try "#!/bin/sh\necho '{\"streams\":[{\"index\":0,\"codec_type\":\"audio\",\"codec_name\":\"wmav2\"}],\"format\":{\"duration\":\"2.0\",\"tags\":{\"TITLE\":\"Stub Song\",\"Artist\":\"Stub Band\"}}}'\n"
            .write(to: macos.appendingPathComponent("ffprobe"), atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        for last; do :; done
        echo "$*" >> "${TMPDIR:-/tmp}/macamp-stub-ffmpeg-args"
        case "$*" in *.slow*) sleep 10 ;; *.bad*) echo "Invalid data found when processing input" >&2; exit 1 ;; esac
        echo out_time_us=1000000; echo out_time_us=2000000
        echo converted > "$last"
        """.write(to: macos.appendingPathComponent("ffmpeg"), atomically: true, encoding: .utf8)
        for tool in ["ffprobe", "ffmpeg"] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macos.appendingPathComponent(tool).path) }
        // As if downloaded: macOS marks it, MacAmp clears the mark on install (after the user's yes)
        setxattr(bundle.path, "com.apple.quarantine", "0081;00000000;Safari;", 21, 0, 0)
        assertTrue(!AppConstants.Audio.supportedExtensions.contains("xyz"), "Formats unknown before the install")
        assertTrue(!DiskWriterFormat.available.contains(.ogg) && !DiskWriterFormat.available.contains(.mp3), "No Ogg / MP3 to rip to without the plug-in")
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
        // CD Ripping / Disk Writer to Ogg and MP3 through the plug-in's ffmpeg: a WAV first, then encoded at the chosen bitrate
        assertTrue(DiskWriterFormat.available.contains(.ogg) && DiskWriterFormat.available.contains(.mp3), "Ogg Vorbis and MP3 offered with the plug-in")
        let argsLog = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("macamp-stub-ffmpeg-args")
        try? FileManager.default.removeItem(at: argsLog)
        let tone = root.appendingPathComponent("tone.wav")
        try writeTestTone(to: tone, seconds: 0.2)
        let ripFolder = root.appendingPathComponent("rip")
        let ogg = awaitValue { try? await DiskWriter.write(TrackItem(url: tone, title: "Tone"), to: ripFolder, name: "Album/01 - Tone", format: .ogg, aacKbps: 192) }
        assertEqual(ogg?.lastPathComponent, "01 - Tone.ogg", "Ripped under the template's name")
        let encodeArgs = (try? String(contentsOf: argsLog, encoding: .utf8)) ?? ""
        assertTrue(encodeArgs.contains("-c:a libvorbis -b:a 192k") && encodeArgs.contains(".wav"), "A WAV encoded by libvorbis at 192 kbps (\(encodeArgs))")
        let ripped = (try? FileManager.default.contentsOfDirectory(atPath: ripFolder.appendingPathComponent("Album").path)) ?? []
        assertEqual(ripped, ["01 - Tone.ogg"], "No partial or temporary file next to it")
        let mp3 = awaitValue { try? await DiskWriter.write(TrackItem(url: tone, title: "Tone"), to: ripFolder, name: "02 - Tone", format: .mp3, aacKbps: 320) }
        assertTrue(mp3?.pathExtension == "mp3" && ((try? String(contentsOf: argsLog, encoding: .utf8)) ?? "").contains("-c:a libmp3lame -b:a 320k"), "MP3 by LAME at 320 kbps")
        if let ogg {
            try? FileManager.default.removeItem(at: argsLog)
            _ = awaitValue { (try? await AudioTagWriter.write([.artist: "Band", .title: "Song", .track: "1/9"], to: ogg)) != nil }
            let tagArgs = (try? String(contentsOf: argsLog, encoding: .utf8)) ?? ""
            assertTrue(tagArgs.contains("-c copy") && tagArgs.contains("-metadata artist=Band") && tagArgs.contains("-metadata track=1/9"),
                       "Tags written by copying the audio, not encoding it again (\(tagArgs))")
        }

        // Before playing: length and tags from ffprobe, nothing converted
        let fresh = root.appendingPathComponent("fresh.xyz")
        try "new".write(to: fresh, atomically: true, encoding: .utf8)
        let freshMeta = awaitValue { await TrackItem.resolveMetadataAsync(from: fresh) }
        assertTrue(freshMeta.duration == 2 && freshMeta.artist == "Stub Band" && freshMeta.title == "Stub Song",
                   "Playlist gets 0:02 and the tags (any case of tag names) before the file plays (\(freshMeta))")
        assertTrue(PluginConversion.cachedOutput(for: fresh) == nil, "Reading tags converted nothing")
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
        let missing = awaitValue { () -> String in
            do { _ = try await DiskWriter.write(TrackItem(url: tone, title: "Tone"), to: ripFolder, name: "03", format: .ogg); return "" }
            catch { return error.localizedDescription }
        }
        assertEqual(missing, "Ogg Vorbis needs the FFmpeg plug-in (Preferences ▸ Plug-ins ▸ Input)", "Without the plug-in a rip to Ogg says why")
    }

    testGroup("Plug-ins: a renderer of its own (in_mod)") {
        // A stand-in for openmpt-render: progress lines, then the WAV at its second argument
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/renderer-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("StubMod.macampplugin")
        let macos = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let info: [String: Any] = ["MacAmpPluginKind": "converter", "MacAmpPluginTitle": "StubMod [in_stubmod]",
                                   "MacAmpPluginRenderer": "render", "MacAmpPluginAudioExtensions": ["tmod", "badmod"]]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        try """
        #!/bin/sh
        if [ "$1" = "--info" ]; then echo x >> "$(dirname "$2")/info-calls"; echo duration=12.5; echo "title=Stub Tune"; echo artist=Tracker; exit 0; fi
        case "$1" in *.badmod) echo "Not a module libopenmpt can play" >&2; exit 1 ;; esac
        echo progress=0.500; echo progress=1.000
        echo rendered > "$2"
        """.write(to: macos.appendingPathComponent("render"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macos.appendingPathComponent("render").path)
        let installed = try PluginManager.install(bundle)
        defer { try? FileManager.default.removeItem(at: PluginManager.folder.appendingPathComponent("StubMod.macampplugin")); PluginManager.reload() }
        assertEqual(installed.renderer?.lastPathComponent, "render", "Its own tool, no ffmpeg needed")

        let input = root.appendingPathComponent("tune.tmod")
        try "module".write(to: input, atomically: true, encoding: .utf8)
        // Before playing: length and tags from `--info`, asked once though the playlist reads them separately
        let meta = awaitValue { await TrackItem.resolveMetadataAsync(from: input) }
        assertTrue(meta.duration == 12.5 && meta.artist == "Tracker" && meta.title == "Stub Tune", "0:12 and the module's tags before playing (\(meta))")
        let calls = (try? String(contentsOf: root.appendingPathComponent("info-calls"), encoding: .utf8))?.split(separator: "\n").count
        assertEqual(calls, 1, "The plug-in is asked once per file")
        assertTrue(PluginConversion.cachedOutput(for: input) == nil, "Nothing rendered for the playlist")
        var fractions: [Double] = []
        PluginConversion.onProgress = { _, f in fractions.append(f) }
        let output = awaitValue { try? await PluginConversion.convert(input) }
        _ = spinRunLoop(until: { fractions.count >= 2 }, timeout: 2)
        PluginConversion.onProgress = nil
        assertEqual(output?.pathExtension, "wav", "Rendered to WAV")
        assertEqual(output.flatMap { try? String(contentsOf: $0, encoding: .utf8) }, "rendered\n", "The tool's output kept")
        assertEqual(fractions, [0.5, 1.0], "Progress from its progress= lines")
        assertEqual(PluginConversion.cachedOutput(for: input), output, "Cached for next time")
        let bad = root.appendingPathComponent("broken.badmod")
        try "x".write(to: bad, atomically: true, encoding: .utf8)
        let failure = awaitValue { () -> String in
            do { _ = try await PluginConversion.convert(bad); return "" } catch { return error.localizedDescription }
        }
        assertEqual(failure, "Not a module libopenmpt can play", "The tool's error shown")

        // A renderer name can't point outside the bundle
        var escaping = info
        escaping["MacAmpPluginRenderer"] = "../../../../bin/sh"
        try PropertyListSerialization.data(fromPropertyList: escaping, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        assertTrue(PluginManager.read(bundle)?.renderer == nil, "No renderer from a path")
        assertEqual(PluginManager.missingPlugin(for: "xm"), "Module", "Modules without the plug-in: the marquee names it")
        assertEqual(PluginManager.missingPlugin(for: "wma"), "FFmpeg")
    }

    testGroup("in_mod plug-in on a real module (needs scripts/build_mod_plugin.sh)") {
        let built = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/plugins/MacAmp Modules.macampplugin")
        guard FileManager.default.fileExists(atPath: built.path) else { print("  (skipped: plug-in not built)"); return }
        _ = try PluginManager.install(built)
        defer { try? FileManager.default.removeItem(at: PluginManager.folder.appendingPathComponent(built.lastPathComponent)); PluginManager.reload() }
        assertTrue(AppConstants.Audio.supportedExtensions.isSuperset(of: ["mod", "xm", "s3m", "it"]), "Module formats playable")
        // 16 rows at speed 6, 125 BPM: 1.92 s of music, then libopenmpt's own 0.1 s fade so the end doesn't click
        let wav = awaitValue { try? await PluginConversion.convert(fixtures.appendingPathComponent("plugin-test.mod")) }
        let file = wav.flatMap { try? AVAudioFile(forReading: $0) }
        assertTrue(file.map { abs(Double($0.length) / $0.fileFormat.sampleRate - 2.02) < 0.03 && $0.fileFormat.channelCount == 2 } ?? false,
                   "MOD → stereo WAV, 1.92 s + fade")
        let named = awaitValue { await TrackItem.resolveMetadataAsync(from: fixtures.appendingPathComponent("plugin-test.mod")) }
        assertTrue(named.title == "MacAmp test" && abs(named.duration - 1.92) < 0.01,
                   "Playlist: the module's own title and its length without the fade (\(named))")
        let played = try loadSync(AudioEngine.shared, fixtures.appendingPathComponent("plugin-test.mod"))
        AudioEngine.shared.stop()
        assertTrue(abs(played.duration - 2.02) < 0.03, "Playing: the rendered file's length, fade included (\(played.duration))")
        let notModule = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/\(UUID().uuidString).xm")
        try FileManager.default.createDirectory(at: notModule.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 300).write(to: notModule)
        let failure = awaitValue { () -> String in
            do { _ = try await PluginConversion.convert(notModule); return "" } catch { return error.localizedDescription }
        }
        assertTrue(failure.hasPrefix("Not a module libopenmpt can play"), "Junk with a module extension: libopenmpt's refusal shown (\(failure))")
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
        // Ogg Vorbis and MP3 really written by the plug-in's LAME / libvorbis, with tags macOS reads
        if PluginManager.encoder(for: "ogg") != nil {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/rip-\(UUID().uuidString)")
            let tone = folder.appendingPathComponent("tone.wav")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeTestTone(to: tone, seconds: 2)
            for format in [DiskWriterFormat.ogg, .mp3] {
                let file = awaitValue { try? await DiskWriter.write(TrackItem(url: tone, title: "Tone"), to: folder, name: "song", format: format, aacKbps: 192) }
                guard let file else { assertTrue(false, "\(format) written"); continue }
                _ = awaitValue { (try? await AudioTagWriter.write([.artist: "Band", .title: "Song"], to: file)) != nil }
                let length = awaitValue { await TrackItem.resolveDuration(from: file) }
                let tags = awaitValue { await TrackItem.resolveArtistAndTitle(from: file) }
                assertTrue(abs(length - 2) < 0.1 && tags.artist == "Band" && tags.title == "Song",
                           "\(format.title): 2 s, tagged Band / Song, read by macOS (\(length), \(tags))")
            }
        } else {
            print("  (Ogg / MP3: skipped, this FFmpeg plug-in build has no encoders yet)")
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

/// A quiet 440 Hz stereo WAV for the encoders
func writeTestTone(to url: URL, seconds: Double) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
                                                           AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16])
    let frames = AVAudioFrameCount(44100 * seconds)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for ch in 0..<2 { for i in 0..<Int(frames) { buffer.floatChannelData![ch][i] = 0.2 * sin(Float(i) * 2 * .pi * 440 / 44100) } }
    try file.write(from: buffer)
}
