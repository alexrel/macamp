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
    
    // Classic Retro Dialog Palette
    private let winampGray = Color(red: 0.88, green: 0.86, blue: 0.83)
    private let darkBorder = Color(red: 0.55, green: 0.55, blue: 0.55)
    
    public init(viewModel: TrackInfoViewModel, onClose: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 10) {
            // 1. Technical Audio Stream Information Box
            techInfoSection
            
            // 2. Tab Strip (ID3v2, ID3v1, Artwork)
            Picker("", selection: $viewModel.selectedTab) {
                ForEach(TrackInfoViewModel.InfoTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 2)
            
            // 3. Active Tab Content
            ZStack {
                switch viewModel.selectedTab {
                case .id3v2:
                    id3v2Section
                case .id3v1:
                    id3v1Section
                case .artwork:
                    artworkSection
                }
            }
            .frame(maxHeight: .infinity)
            
            // 4. Status message
            if let msg = viewModel.statusMessage {
                Text(msg)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(viewModel.isErrorMessage ? .red : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            
            // 5. Bottom Navigation & Action Buttons
            bottomButtonBar
        }
        .padding(14)
        .frame(width: 530, height: 530)
        .background(winampGray)
    }
    
    // MARK: - Section 1: Audio Technical Info
    private var techInfoSection: some View {
        GroupBox(label: Text("Audio Stream Information").font(.system(size: 11, weight: .bold))) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("File:")
                        .font(.system(size: 11, weight: .bold))
                    Text(viewModel.metadata.url.lastPathComponent)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if viewModel.metadata.isReadOnly {
                        Text("[Read-Only]")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
                
                Divider()
                
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
            .padding(4)
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Section 2: ID3v2 Tag Editor
    private var id3v2Section: some View {
        GroupBox(
            label: Toggle("Include ID3v2 Tag", isOn: $viewModel.metadata.id3v2.hasTag)
                .font(.system(size: 11, weight: .bold))
        ) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 6) {
                    labeledInput(label: "Title:", text: $viewModel.metadata.id3v2.title)
                    labeledInput(label: "Artist:", text: $viewModel.metadata.id3v2.artist)
                    labeledInput(label: "Album:", text: $viewModel.metadata.id3v2.album)
                    
                    HStack(spacing: 12) {
                        labeledInput(label: "Year:", text: $viewModel.metadata.id3v2.year, width: 80)
                        labeledInput(label: "Track #:", text: $viewModel.metadata.id3v2.trackNumber, width: 70)
                        labeledInput(label: "Disc #:", text: $viewModel.metadata.id3v2.discNumber, width: 70)
                        Spacer()
                    }
                    
                    HStack(spacing: 8) {
                        Text("Genre:")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 80, alignment: .trailing)
                        TextField("", text: $viewModel.metadata.id3v2.genre)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                        
                        Menu {
                            ForEach(ID3Genre.allGenres, id: \.self) { g in
                                Button(g) {
                                    viewModel.metadata.id3v2.genre = g
                                }
                            }
                        } label: {
                            Text("Standard ▼")
                                .font(.system(size: 10))
                        }
                        .frame(width: 95)
                    }
                    
                    labeledInput(label: "Composer:", text: $viewModel.metadata.id3v2.composer)
                    labeledInput(label: "Orig. Artist:", text: $viewModel.metadata.id3v2.originalArtist)
                    labeledInput(label: "Copyright:", text: $viewModel.metadata.id3v2.copyright)
                    labeledInput(label: "Encoded by:", text: $viewModel.metadata.id3v2.encodedBy)
                    labeledInput(label: "URL:", text: $viewModel.metadata.id3v2.url)
                    
                    HStack(alignment: .top, spacing: 8) {
                        Text("Comment:")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 80, alignment: .trailing)
                            .padding(.top, 4)
                        TextField("", text: $viewModel.metadata.id3v2.comment)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                    }
                }
                .padding(4)
            }
            .opacity(viewModel.metadata.id3v2.hasTag ? 1.0 : 0.4)
            .disabled(!viewModel.metadata.id3v2.hasTag)
        }
    }
    
    // MARK: - Section 3: ID3v1 Tag Editor
    private var id3v1Section: some View {
        GroupBox(
            label: Toggle("Include ID3v1 Tag", isOn: $viewModel.metadata.id3v1.hasTag)
                .font(.system(size: 11, weight: .bold))
        ) {
            VStack(spacing: 8) {
                labeledInput(label: "Title (30):", text: $viewModel.metadata.id3v1.title, maxLen: 30)
                labeledInput(label: "Artist (30):", text: $viewModel.metadata.id3v1.artist, maxLen: 30)
                labeledInput(label: "Album (30):", text: $viewModel.metadata.id3v1.album, maxLen: 30)
                
                HStack(spacing: 12) {
                    labeledInput(label: "Year (4):", text: $viewModel.metadata.id3v1.year, width: 80, maxLen: 4)
                    
                    HStack(spacing: 4) {
                        Text("Track #:")
                            .font(.system(size: 11, weight: .medium))
                        TextField("", value: $viewModel.metadata.id3v1.trackNumber, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .frame(width: 50)
                    }
                    Spacer()
                }
                
                HStack(spacing: 8) {
                    Text("Genre:")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 80, alignment: .trailing)
                    
                    Picker("", selection: $viewModel.metadata.id3v1.genreIndex) {
                        Text("(None)").tag(UInt8(255))
                        ForEach(0..<ID3Genre.allGenres.count, id: \.self) { i in
                            Text(ID3Genre.allGenres[i]).tag(UInt8(i))
                        }
                    }
                    .labelsHidden()
                }
                
                labeledInput(label: "Comment (28):", text: $viewModel.metadata.id3v1.comment, maxLen: 28)
                
                Spacer()
                
                HStack {
                    Button("Sync with ID3v2 ➜") {
                        viewModel.copyFromID3v1()
                    }
                    .font(.system(size: 11))
                    
                    Spacer()
                }
            }
            .padding(6)
            .opacity(viewModel.metadata.id3v1.hasTag ? 1.0 : 0.4)
            .disabled(!viewModel.metadata.id3v1.hasTag)
        }
    }
    
    // MARK: - Section 4: Artwork / Cover Art
    private var artworkSection: some View {
        GroupBox(label: Text("Album Cover Artwork").font(.system(size: 11, weight: .bold))) {
            HStack(spacing: 20) {
                // Cover preview
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .frame(width: 160, height: 160)
                        .overlay(Rectangle().stroke(darkBorder, lineWidth: 1))
                    
                    if let art = viewModel.metadata.artwork, let nsImg = art.image {
                        Image(nsImage: nsImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 156, height: 156)
                    } else {
                        VStack(spacing: 4) {
                            Text("No Artwork")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                            Text("Embedded cover absent")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Artwork Details and Actions
                VStack(alignment: .leading, spacing: 10) {
                    if let art = viewModel.metadata.artwork {
                        Text("Type: \(art.mimeType)")
                            .font(.system(size: 11))
                        Text("Size: \(art.imageData.count / 1024) KB")
                            .font(.system(size: 11))
                        if let nsImg = art.image {
                            Text("Dimensions: \(Int(nsImg.size.width)) × \(Int(nsImg.size.height)) px")
                                .font(.system(size: 11))
                        }
                    } else {
                        Text("No embedded picture in ID3 tag.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Button("Load Artwork...") {
                            viewModel.loadArtwork()
                        }
                        .font(.system(size: 11))
                        
                        Button("Export Artwork...") {
                            viewModel.exportArtwork()
                        }
                        .font(.system(size: 11))
                        .disabled(viewModel.metadata.artwork == nil)
                        
                        Button("Remove") {
                            viewModel.removeArtwork()
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .disabled(viewModel.metadata.artwork == nil)
                    }
                }
                Spacer()
            }
            .padding(10)
        }
    }
    
    // MARK: - Bottom Controls Bar
    private var bottomButtonBar: some View {
        HStack(spacing: 8) {
            // Track navigation
            Button("◄ Prev") {
                viewModel.prevTrack()
            }
            .font(.system(size: 11))
            .disabled(viewModel.trackIndex <= 0)
            
            Button("Next ►") {
                viewModel.nextTrack()
            }
            .font(.system(size: 11))
            .disabled(viewModel.trackIndex + 1 >= viewModel.totalTracks)
            
            Text("Track \(viewModel.trackIndex + 1) of \(viewModel.totalTracks)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Copy to ID3v1") {
                viewModel.copyToID3v1()
            }
            .font(.system(size: 11))
            
            Button("Undo") {
                viewModel.undo()
            }
            .font(.system(size: 11))
            
            Button("Cancel") {
                onClose?()
            }
            .font(.system(size: 11))
            
            Button("Update") {
                if viewModel.save() {
                    onClose?()
                }
            }
            .font(.system(size: 11, weight: .bold))
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.metadata.isReadOnly)
        }
        .padding(.top, 4)
    }
    
    // MARK: - Helper Views
    private func labeledInput(label: String, text: Binding<String>, width: CGFloat? = nil, maxLen: Int? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 80, alignment: .trailing)
            
            TextField("", text: Binding(
                get: { text.wrappedValue },
                set: { val in
                    if let max = maxLen, val.count > max {
                        text.wrappedValue = String(val.prefix(max))
                    } else {
                        text.wrappedValue = val
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .frame(width: width)
        }
    }
}
