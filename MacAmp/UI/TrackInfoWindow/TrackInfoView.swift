import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Track Info View Model
public class TrackInfoViewModel: ObservableObject {
    @Published public var metadata: AudioFileMetadata
    @Published public var initialMetadata: AudioFileMetadata
    @Published public var selectedTab: InfoTab = .id3v2
    @Published public var statusMessage: String?
    @Published public var isErrorMessage: Bool = false
    
    public let trackIndex: Int
    public let totalTracks: Int
    public var onTrackChanged: ((Int) -> Void)?
    public var onMetadataUpdated: ((AudioFileMetadata) -> Void)?
    
    public enum InfoTab: String, CaseIterable, Identifiable {
        case id3v2 = "ID3v2 Tag"
        case id3v1 = "ID3v1 Tag"
        case artwork = "Artwork"
        
        public var id: String { rawValue }
    }
    
    public init(
        url: URL,
        trackIndex: Int = 0,
        totalTracks: Int = 1,
        onTrackChanged: ((Int) -> Void)? = nil,
        onMetadataUpdated: ((AudioFileMetadata) -> Void)? = nil
    ) {
        let meta = AudioMetadataService.shared.readMetadata(from: url)
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
            if let data = try? Data(contentsOf: fileURL) {
                let mime = fileURL.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
                metadata.artwork = ArtworkInfo(imageData: data, mimeType: mime)
                metadata.id3v2.hasTag = true
                statusMessage = "Cover Art loaded: \(fileURL.lastPathComponent)"
                isErrorMessage = false
            }
        }
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

// MARK: - Track Info View (Winamp MPEG Info Box)
public struct TrackInfoView: View {
    @ObservedObject public var viewModel: TrackInfoViewModel
    public var onClose: (() -> Void)?
    
    /// Width of the right-aligned field labels
    private let labelWidth: CGFloat = 80
    
    public init(viewModel: TrackInfoViewModel, onClose: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onClose = onClose
    }
    
    // Classic Win32 dialog, like Winamp 2.9's "MPEG file info box + ID3 tag editor"
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            techInfoSection
                .fixedSize(horizontal: false, vertical: true)
            
            // Property-sheet style tabs with a raised page underneath
            VStack(spacing: 0) {
                Win32TabHeader(tabs: TrackInfoViewModel.InfoTab.allCases, selectedTab: $viewModel.selectedTab)
                ZStack(alignment: .topLeading) {
                    switch viewModel.selectedTab {
                    case .id3v2:
                        id3v2Section
                    case .id3v1:
                        id3v1Section
                    case .artwork:
                        artworkSection
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .win32Raised()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if let msg = viewModel.statusMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(viewModel.isErrorMessage ? .red : Win32Colors.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            bottomButtonBar
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 490, maxHeight: .infinity)
        .background(Win32Colors.dialogBg)
    }
    
    // MARK: - Section 1: Audio Technical Info
    private var techInfoSection: some View {
        Win32GroupBox("MPEG Audio Stream Information") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("File:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Win32Colors.text)
                    Text(viewModel.metadata.url.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundColor(Win32Colors.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if viewModel.metadata.isReadOnly {
                        Text("[Read-Only]")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
                
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        infoRow(label: "Payload:", value: "\(viewModel.metadata.techInfo.fileSize) bytes")
                        infoRow(label: "Header at:", value: "\(viewModel.metadata.techInfo.headerOffset) bytes")
                        infoRow(label: "Length:", value: viewModel.metadata.techInfo.formattedDuration)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        infoRow(label: "Format:", value: viewModel.metadata.techInfo.formatDescription)
                        infoRow(label: "Bitrate:", value: "\(viewModel.metadata.techInfo.bitrate) kbps")
                        infoRow(label: "Rate:", value: "\(Int(viewModel.metadata.techInfo.sampleRate)) Hz")
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        infoRow(label: "Mode:", value: viewModel.metadata.techInfo.channelMode)
                        infoRow(label: "CRCs:", value: viewModel.metadata.techInfo.hasCRC ? "Yes" : "No")
                        infoRow(label: "Original:", value: viewModel.metadata.techInfo.isOriginal ? "Yes" : "No")
                    }
                }
            }
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Win32Colors.text)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Win32Colors.text)
        }
    }
    
    // MARK: - Section 2: ID3v2 Tag Editor
    private var id3v2Section: some View {
        VStack(alignment: .leading, spacing: 6) {
            Win32Checkbox("Include ID3v2 tag", isOn: $viewModel.metadata.id3v2.hasTag)
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 6) {
                    labeledInput(label: "Title:", text: $viewModel.metadata.id3v2.title)
                    labeledInput(label: "Artist:", text: $viewModel.metadata.id3v2.artist)
                    labeledInput(label: "Album:", text: $viewModel.metadata.id3v2.album)
                    
                    HStack(spacing: 6) {
                        fieldLabel("Year:")
                        Win32TextField(text: $viewModel.metadata.id3v2.year).frame(width: 60)
                        Text("Track #:").font(.system(size: 11)).foregroundColor(Win32Colors.text).padding(.leading, 8)
                        Win32TextField(text: $viewModel.metadata.id3v2.trackNumber).frame(width: 50)
                        Text("Disc #:").font(.system(size: 11)).foregroundColor(Win32Colors.text).padding(.leading, 8)
                        Win32TextField(text: $viewModel.metadata.id3v2.discNumber).frame(width: 50)
                        Spacer()
                    }
                    
                    HStack(spacing: 6) {
                        fieldLabel("Genre:")
                        Win32TextField(text: $viewModel.metadata.id3v2.genre)
                        Win32ComboBox(
                            selection: Binding(
                                get: { viewModel.metadata.id3v2.genre },
                                set: { viewModel.metadata.id3v2.genre = $0 }
                            ),
                            options: [(value: viewModel.metadata.id3v2.genre, title: "Standard...")] +
                                ID3Genre.allGenres.map { (value: $0, title: $0) },
                            width: 110
                        )
                    }
                    
                    labeledInput(label: "Composer:", text: $viewModel.metadata.id3v2.composer)
                    labeledInput(label: "Orig. Artist:", text: $viewModel.metadata.id3v2.originalArtist)
                    labeledInput(label: "Copyright:", text: $viewModel.metadata.id3v2.copyright)
                    labeledInput(label: "Encoded by:", text: $viewModel.metadata.id3v2.encodedBy)
                    labeledInput(label: "URL:", text: $viewModel.metadata.id3v2.url)
                    labeledInput(label: "Comment:", text: $viewModel.metadata.id3v2.comment)
                }
                .padding(.vertical, 2)
            }
            .disabled(!viewModel.metadata.id3v2.hasTag)
        }
    }
    
    // MARK: - Section 3: ID3v1 Tag Editor
    private var id3v1Section: some View {
        VStack(alignment: .leading, spacing: 6) {
            Win32Checkbox("Include ID3v1 tag", isOn: $viewModel.metadata.id3v1.hasTag)
            
            VStack(spacing: 6) {
                labeledInput(label: "Title:", text: $viewModel.metadata.id3v1.title, maxLen: 30)
                labeledInput(label: "Artist:", text: $viewModel.metadata.id3v1.artist, maxLen: 30)
                labeledInput(label: "Album:", text: $viewModel.metadata.id3v1.album, maxLen: 30)
                
                HStack(spacing: 6) {
                    labeledInput(label: "Year:", text: $viewModel.metadata.id3v1.year, width: 60, maxLen: 4)
                    Text("Track #:").font(.system(size: 11)).foregroundColor(Win32Colors.text).padding(.leading, 8)
                    Win32NumberField(value: Binding(
                        get: { Int(viewModel.metadata.id3v1.trackNumber) },
                        set: { viewModel.metadata.id3v1.trackNumber = UInt8(clamping: $0) }
                    ), width: 40)
                    Spacer()
                }
                
                HStack(spacing: 6) {
                    fieldLabel("Genre:")
                    Win32ComboBox(
                        selection: $viewModel.metadata.id3v1.genreIndex,
                        options: [(value: UInt8(255), title: "(None)")] +
                            ID3Genre.allGenres.indices.map { (value: UInt8($0), title: ID3Genre.allGenres[$0]) },
                        width: 200
                    )
                    Spacer()
                }
                
                labeledInput(label: "Comment:", text: $viewModel.metadata.id3v1.comment, maxLen: 28)
                
                HStack {
                    Spacer().frame(width: labelWidth + 6)
                    Win32Button("Copy to ID3v2", width: 120) {
                        viewModel.copyFromID3v1()
                    }
                    Spacer()
                }
                .padding(.top, 4)
                
                Spacer()
            }
            .disabled(!viewModel.metadata.id3v1.hasTag)
        }
    }
    
    // MARK: - Section 4: Artwork / Cover Art
    private var artworkSection: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 152, height: 152)
                    .win32Sunken()
                
                if let art = viewModel.metadata.artwork, let nsImg = art.image {
                    Image(nsImage: nsImg)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 146, maxHeight: 146)
                } else {
                    Text("(no picture)")
                        .font(.system(size: 11))
                        .foregroundColor(Win32Colors.textDisabled)
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    if let art = viewModel.metadata.artwork {
                        artworkRow("Format:", art.mimeType)
                        artworkRow("File size:", formatArtworkSize(art.imageData.count))
                        if let nsImg = art.image {
                            artworkRow("Dimensions:", "\(Int(nsImg.size.width)) × \(Int(nsImg.size.height))")
                        }
                    } else {
                        Text("No picture embedded in the ID3 tag.")
                            .font(.system(size: 11))
                            .foregroundColor(Win32Colors.text)
                    }
                }
                .frame(height: 50, alignment: .topLeading)
                
                Win32Button("Load...", width: 100) { viewModel.loadArtwork() }
                Win32Button("Export...", width: 100) { viewModel.exportArtwork() }
                    .disabled(viewModel.metadata.artwork == nil)
                Win32Button("Remove", width: 100) { viewModel.removeArtwork() }
                    .disabled(viewModel.metadata.artwork == nil)
                Spacer()
            }
            Spacer()
        }
    }
    
    private func artworkRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Win32Colors.text)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(Win32Colors.text)
        }
    }
    
    // MARK: - Bottom Controls Bar
    private var bottomButtonBar: some View {
        HStack(spacing: 6) {
            Win32Button("◄ Prev", width: 60) { viewModel.prevTrack() }
                .disabled(viewModel.trackIndex <= 0)
            Win32Button("Next ►", width: 60) { viewModel.nextTrack() }
                .disabled(viewModel.trackIndex + 1 >= viewModel.totalTracks)
            
            Text("\(viewModel.trackIndex + 1) of \(viewModel.totalTracks)")
                .font(.system(size: 11))
                .foregroundColor(Win32Colors.text)
                .padding(.leading, 4)
            
            Spacer()
            
            Win32Button("Copy to ID3v1", width: 95) { viewModel.copyToID3v1() }
            Win32Button("Undo", width: 60) { viewModel.undo() }
            Win32Button("Cancel") { onClose?() }
            Win32Button("Update", isDefault: true) {
                if viewModel.save() {
                    onClose?()
                }
            }
            .disabled(viewModel.metadata.isReadOnly)
        }
    }
    
    // MARK: - Helper Views & Formatting
    private func formatArtworkSize(_ bytes: Int) -> String {
        if bytes <= 0 { return "0 bytes" }
        if bytes < 1024 { return "\(bytes) bytes" }
        if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        }
        return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
    }
    
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Win32Colors.text)
            .frame(width: labelWidth, alignment: .trailing)
    }
    
    private func labeledInput(label: String, text: Binding<String>, width: CGFloat? = nil, maxLen: Int? = nil) -> some View {
        HStack(spacing: 6) {
            fieldLabel(label)
            Win32TextField(text: Binding(
                get: { text.wrappedValue },
                set: { val in
                    if let max = maxLen, val.count > max {
                        text.wrappedValue = String(val.prefix(max))
                    } else {
                        text.wrappedValue = val
                    }
                }
            ))
            .frame(width: width)
        }
    }
}
