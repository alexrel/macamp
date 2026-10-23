import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Track Info View Model
public class TrackInfoViewModel: ObservableObject {
    @Published public var metadata: AudioFileMetadata
    @Published public var initialMetadata: AudioFileMetadata
    @Published public var statusMessage: String?
    @Published public var isErrorMessage: Bool = false
    
    public let trackIndex: Int
    public let totalTracks: Int
    public var onTrackChanged: ((Int) -> Void)?
    public var onMetadataUpdated: ((AudioFileMetadata) -> Void)?
    
    public init(
        metadata meta: AudioFileMetadata,
        trackIndex: Int = 0,
        totalTracks: Int = 1,
        onTrackChanged: ((Int) -> Void)? = nil,
        onMetadataUpdated: ((AudioFileMetadata) -> Void)? = nil
    ) {
        self.metadata = meta
        self.initialMetadata = meta
        self.trackIndex = trackIndex
        self.totalTracks = totalTracks
        self.onTrackChanged = onTrackChanged
        self.onMetadataUpdated = onMetadataUpdated
    }
    
    public func copyToID3v1() {
        metadata.copyToID3v1()
        statusMessage = "Copied ID3v2 fields to ID3v1"
        isErrorMessage = false
    }
    
    public func copyFromID3v1() {
        metadata.copyFromID3v1()
        statusMessage = "Copied ID3v1 fields to ID3v2"
        isErrorMessage = false
    }
    
    public func undo() {
        metadata = initialMetadata
        statusMessage = "Reverted all unsaved changes"
        isErrorMessage = false
    }
    
    public func save() -> Bool {
        do {
            try AudioMetadataService.shared.writeMetadata(metadata, to: metadata.url)
            initialMetadata = metadata
            statusMessage = "Tags saved successfully!"
            isErrorMessage = false
            onMetadataUpdated?(metadata)
            return true
        } catch {
            statusMessage = "Save error: \(error.localizedDescription)"
            isErrorMessage = true
            return false
        }
    }
    
    public func loadArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select Cover Art image (JPEG or PNG)"
        if panel.runModal() == .OK, let fileURL = panel.url {
            setArtwork(from: fileURL)
        }
    }
    
    /// Load / drop a JPEG or PNG as the cover picture.
    @discardableResult
    public func setArtwork(from fileURL: URL) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        guard ["jpg", "jpeg", "png"].contains(ext), let data = try? Data(contentsOf: fileURL) else { return false }
        metadata.artwork = ArtworkInfo(imageData: data, mimeType: ext == "png" ? "image/png" : "image/jpeg")
        metadata.id3v2.hasTag = true
        statusMessage = "Cover Art loaded: \(fileURL.lastPathComponent)"
        isErrorMessage = false
        return true
    }
    
    public func exportArtwork() {
        guard let art = metadata.artwork, !art.imageData.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (metadata.id3v2.album.isEmpty ? "cover" : metadata.id3v2.album) + (art.mimeType == "image/png" ? ".png" : ".jpg")
        panel.allowedContentTypes = art.mimeType == "image/png" ? [.png] : [.jpeg]
        
        if panel.runModal() == .OK, let targetURL = panel.url {
            do {
                try art.imageData.write(to: targetURL)
                statusMessage = "Saved artwork to \(targetURL.lastPathComponent)"
                isErrorMessage = false
            } catch {
                statusMessage = "Failed to export: \(error.localizedDescription)"
                isErrorMessage = true
            }
        }
    }
    
    public func removeArtwork() {
        metadata.artwork = nil
        statusMessage = "Cover Art removed"
        isErrorMessage = false
    }
    
    public func prevTrack() {
        guard trackIndex > 0 else { return }
        onTrackChanged?(trackIndex - 1)
    }
    
    public func nextTrack() {
        guard trackIndex + 1 < totalTracks else { return }
        onTrackChanged?(trackIndex + 1)
    }
}

// MARK: - Track Info View
/// Winamp 2.95 "MPEG file info box + ID3 tag editor" on one screen (docs/UI-screens/file meta editor.png):
/// path on top, ID3v1 and MPEG info on the left, ID3v2 on the right, Update / Cancel / Undo Changes below.
/// MacAmp additions: cover picture next to the ID3v2 comment, Disc #, Prev / Next track.
public struct TrackInfoView: View {
    @ObservedObject public var viewModel: TrackInfoViewModel
    public var onClose: (() -> Void)?
    
    public init(viewModel: TrackInfoViewModel, onClose: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onClose = onClose
    }
    
    private var meta: AudioFileMetadata { viewModel.metadata }
    /// ID3v1 lives at the end of MPEG files only; other formats get just the tag editor
    private var isMPEG: Bool { meta.techInfo.isMPEG }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meta.url.path)
                .font(.system(size: 11))
                .foregroundColor(Win32Colors.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .win32Sunken()
            
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    if isMPEG { id3v1Group }
                    infoGroup
                }
                .frame(width: 250)
                id3v2Group
            }
            
            if let msg = viewModel.statusMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(viewModel.isErrorMessage ? .red : Win32Colors.text)
                    .lineLimit(1)
            }
            
            bottomButtons
        }
        .padding(10)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 600)
        .background(Win32Colors.dialogBg)
    }
    
    // MARK: ID3v1 (left)
    private var id3v1Group: some View {
        Win32GroupBox("ID3v1") {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Win32Checkbox("ID3v1 Tag", isOn: $viewModel.metadata.id3v1.hasTag)
                    Spacer()
                    label("Track #")
                    Win32NumberField(value: Binding(
                        get: { Int(viewModel.metadata.id3v1.trackNumber) },
                        set: { viewModel.metadata.id3v1.trackNumber = UInt8(clamping: $0) }
                    ), width: 28)
                    .disabled(!viewModel.metadata.id3v1.hasTag)
                }
                .frame(height: headerHeight)
                Group {
                    field("Title", $viewModel.metadata.id3v1.title, labelWidth: 46, maxLen: 30)
                    field("Artist", $viewModel.metadata.id3v1.artist, labelWidth: 46, maxLen: 30)
                    field("Album", $viewModel.metadata.id3v1.album, labelWidth: 46, maxLen: 30)
                    HStack(spacing: 6) {
                        field("Year", $viewModel.metadata.id3v1.year, labelWidth: 46, width: 36, maxLen: 4)
                        label("Genre")
                        Win32ComboBox(
                            selection: $viewModel.metadata.id3v1.genreIndex,
                            options: [(value: UInt8(255), title: "")] +
                                ID3Genre.allGenres.indices
                                    .map { (value: UInt8($0), title: ID3Genre.allGenres[$0]) }
                                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                        )
                    }
                    field("Comment", $viewModel.metadata.id3v1.comment, labelWidth: 46, maxLen: 28)
                }
                .disabled(!viewModel.metadata.id3v1.hasTag)
            }
        }
    }
    
    // MARK: MPEG info / file info (left)
    private var infoGroup: some View {
        let tech = meta.techInfo
        let lines: [String]
        if isMPEG {
            lines = [
                "Size: \(tech.fileSize) bytes",
                "Header found at: \(tech.headerOffset) bytes",
                "Length: \(Int(tech.duration.rounded())) seconds",
                tech.formatDescription,
                "\(tech.bitrate)kbit\(tech.isVBR ? " VBR" : ""), \(tech.frameCount) frames",
                "\(Int(tech.sampleRate))Hz \(tech.channelMode)",
                "CRCs: \(tech.hasCRC ? "Yes" : "No")",
                "Copyrighted: \(tech.isCopyrighted ? "Yes" : "No")",
                "Original: \(tech.isOriginal ? "Yes" : "No")",
                "Emphasis: \(tech.emphasis)"
            ]
        } else {
            lines = [
                "Size: \(tech.fileSize) bytes",
                "Length: \(Int(tech.duration.rounded())) seconds",
                tech.formatDescription,
                "\(tech.bitrate)kbit",
                "\(Int(tech.sampleRate))Hz \(tech.channelMode)"
            ]
        }
        return Win32GroupBox(isMPEG ? "MPEG info" : "File info") {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundColor(Win32Colors.text)
                        .lineLimit(1)
                }
                if meta.isReadOnly {
                    Text("Read-only file")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: ID3v2 (right)
    private var id3v2Group: some View {
        Win32GroupBox(isMPEG ? "ID3v2" : "Tags") {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Win32Checkbox(isMPEG ? "ID3v2 Tag" : "Tag", isOn: $viewModel.metadata.id3v2.hasTag)
                    Spacer()
                    Group {
                        label("Disc #")
                        Win32TextField(text: $viewModel.metadata.id3v2.discNumber).frame(width: 36)
                        label("Track #")
                        Win32TextField(text: $viewModel.metadata.id3v2.trackNumber).frame(width: 40)
                    }
                    .disabled(!viewModel.metadata.id3v2.hasTag)
                }
                .frame(height: headerHeight)
                Group {
                    field("Title", $viewModel.metadata.id3v2.title)
                    field("Artist", $viewModel.metadata.id3v2.artist)
                    field("Album", $viewModel.metadata.id3v2.album)
                    HStack(spacing: 6) {
                        field("Year", $viewModel.metadata.id3v2.year, width: 44)
                        label("Genre")
                        HStack(spacing: 2) {
                            Win32TextField(text: $viewModel.metadata.id3v2.genre)
                            Win32ComboBox(
                                selection: $viewModel.metadata.id3v2.genre,
                                options: ID3Genre.allGenres.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                                    .map { (value: $0, title: $0) },
                                width: 20, // just the drop-down arrow: the text field next to it is the editable part
                                label: ""
                            )
                        }
                    }
                    HStack(alignment: .top, spacing: 6) {
                        label("Comment").frame(width: v2LabelWidth, alignment: .trailing).padding(.top, 3)
                        CommentEditor(text: $viewModel.metadata.id3v2.comment)
                        artworkThumbnail
                    }
                    field("Composer", $viewModel.metadata.id3v2.composer)
                    field("Orig. Artist", $viewModel.metadata.id3v2.originalArtist)
                    field("Copyright", $viewModel.metadata.id3v2.copyright)
                    field("URL", $viewModel.metadata.id3v2.url)
                    field("Encoded by", $viewModel.metadata.id3v2.encodedBy)
                }
                .disabled(!viewModel.metadata.id3v2.hasTag)
                
                if isMPEG {
                    HStack(spacing: 6) {
                        Win32Button("Copy to ID3v1", width: 96) { viewModel.copyToID3v1() }
                        Win32Button("Copy from ID3v1", width: 106) { viewModel.copyFromID3v1() }
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
    
    /// Cover picture (MacAmp addition): click for Load / Save / Remove, or drop a JPEG / PNG on it.
    private var artworkThumbnail: some View {
        Button(action: showArtworkMenu) {
            ZStack {
                Rectangle().fill(Color.white)
                if let image = meta.artwork?.image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(2)
                } else {
                    Text("No\npicture")
                        .font(.system(size: 9))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Win32Colors.textDisabled)
                }
            }
            .frame(width: 52, height: 52)
            .win32Sunken()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Cover picture: click to load, save or remove; drop a JPEG or PNG here")
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { viewModel.setArtwork(from: url) }
            }
            return true
        }
    }
    
    private func showArtworkMenu() {
        let menu = NSMenu()
        menu.addItem(Win32ClosureMenuItem(title: "Load picture...") { viewModel.loadArtwork() })
        let save = Win32ClosureMenuItem(title: "Save picture...") { viewModel.exportArtwork() }
        let remove = Win32ClosureMenuItem(title: "Remove picture") { viewModel.removeArtwork() }
        save.isEnabled = meta.artwork != nil
        remove.isEnabled = meta.artwork != nil
        menu.autoenablesItems = false
        menu.addItem(save)
        menu.addItem(remove)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    // MARK: Bottom buttons
    private var bottomButtons: some View {
        HStack(spacing: 6) {
            Win32Button("Update", width: 84, isDefault: true) {
                if viewModel.save() { onClose?() }
            }
            .disabled(meta.isReadOnly)
            Win32Button("Cancel", width: 84) { onClose?() }
            Win32Button("Undo Changes", width: 96) { viewModel.undo() }
            Spacer()
            // MacAmp addition: step through the playlist without closing the box
            Win32ArrowButton("Prev", direction: .left, width: 62) { viewModel.prevTrack() }
                .disabled(viewModel.trackIndex <= 0)
            Text("\(viewModel.trackIndex + 1) of \(viewModel.totalTracks)")
                .font(.system(size: 11))
                .foregroundColor(Win32Colors.text)
                .fixedSize()
            Win32ArrowButton("Next", direction: .right, width: 62) { viewModel.nextTrack() }
                .disabled(viewModel.trackIndex + 1 >= viewModel.totalTracks)
        }
    }
    
    // MARK: Helpers
    private let v2LabelWidth: CGFloat = 62
    /// Both tag groups start with a checkbox row of this height, so their field rows line up
    private let headerHeight: CGFloat = 22
    
    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Win32Colors.text)
            .fixedSize()
    }
    
    private func field(_ title: String, _ text: Binding<String>, labelWidth: CGFloat = 62, width: CGFloat? = nil, maxLen: Int? = nil) -> some View {
        HStack(spacing: 6) {
            label(title).frame(width: labelWidth, alignment: .trailing)
            Win32TextField(text: Binding(
                get: { text.wrappedValue },
                set: { value in
                    // ID3v1 fields are fixed-size (30 / 28 / 4 bytes)
                    if let maxLen, value.count > maxLen { text.wrappedValue = String(value.prefix(maxLen)) } else { text.wrappedValue = value }
                }
            ))
            .frame(width: width)
        }
    }
}

/// Multi-line ID3v2 comment box; grey when disabled, like the single-line Win32 fields.
private struct CommentEditor: View {
    @Binding var text: String
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 11))
            .foregroundColor(isEnabled ? Win32Colors.text : Win32Colors.textDisabled)
            .scrollContentBackground(.hidden)
            .background(isEnabled ? Color.white : Win32Colors.dialogBg)
            .frame(height: 52)
            .win32Sunken()
    }
}
