import SwiftUI
import AppKit

public protocol JumpToFileKeyDelegate: AnyObject {
    func moveSelectionUp()
    func moveSelectionDown()
    func performJump()
    func performEnqueue()
}

public class JumpToFileViewModel: ObservableObject, JumpToFileKeyDelegate {
    @Published public var searchText: String = "" {
        didSet {
            filterTracks()
        }
    }
    
    @Published public var selectedRow: Int = 0
    @Published public var filteredTracks: [(playlistIndex: Int, track: TrackItem)] = []
    
    public var onClose: (() -> Void)?
    
    public init() {
        filterTracks()
    }
    
    public func filterTracks() {
        let allTracks = PlayerCoordinator.shared.playlist.tracks
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        if query.isEmpty {
            self.filteredTracks = allTracks.enumerated().map { ($0.offset, $0.element) }
        } else {
            self.filteredTracks = allTracks.enumerated().compactMap { idx, track in
                let titleMatch = track.title.lowercased().contains(query)
                let artistMatch = track.artist.lowercased().contains(query)
                let fileMatch = track.url.lastPathComponent.lowercased().contains(query)
                if titleMatch || artistMatch || fileMatch {
                    return (idx, track)
                }
                return nil
            }
        }
        
        if selectedRow >= filteredTracks.count {
            selectedRow = max(0, filteredTracks.count - 1)
        }
    }
    
    public func moveSelectionUp() {
        guard !filteredTracks.isEmpty else { return }
        selectedRow = max(0, selectedRow - 1)
    }
    
    public func moveSelectionDown() {
        guard !filteredTracks.isEmpty else { return }
        selectedRow = min(filteredTracks.count - 1, selectedRow + 1)
    }
    
    public func performJump() {
        guard selectedRow >= 0, selectedRow < filteredTracks.count else { return }
        let item = filteredTracks[selectedRow]
        let coord = PlayerCoordinator.shared
        coord.playlist.currentIndex = item.playlistIndex
        coord.playlist.selectedIndices = [item.playlistIndex]
        coord.loadAndPlay(track: item.track)
        onClose?()
    }
    
    public func performEnqueue() {
        guard selectedRow >= 0, selectedRow < filteredTracks.count else { return }
        let item = filteredTracks[selectedRow]
        let coord = PlayerCoordinator.shared
        coord.playlist.selectedIndices.insert(item.playlistIndex)
        coord.mainView?.marquee.showTemporaryMessage("ENQUEUED: \(item.track.title)")
    }
}

public struct JumpToFileView: View {
    @ObservedObject public var viewModel: JumpToFileViewModel
    public var onClose: () -> Void
    
    public init(viewModel: JumpToFileViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search Input Row
            HStack(spacing: 8) {
                Text("Search for file:")
                    .font(.system(size: 11))
                    .foregroundColor(Win32Colors.text)
                
                SearchInputField(text: $viewModel.searchText)
                    .frame(height: 20)
            }
            .padding(.top, 4)
            
            // Results Table inside Win32 sunken frame
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if viewModel.filteredTracks.isEmpty {
                            Text("No tracks found")
                                .font(.system(size: 11))
                                .foregroundColor(Win32Colors.textDisabled)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        } else {
                            ForEach(0..<viewModel.filteredTracks.count, id: \.self) { idx in
                                let item = viewModel.filteredTracks[idx]
                                JumpTrackRowView(
                                    displayIndex: item.playlistIndex + 1,
                                    track: item.track,
                                    isSelected: viewModel.selectedRow == idx,
                                    onSelect: {
                                        viewModel.selectedRow = idx
                                    },
                                    onDoubleClick: {
                                        viewModel.selectedRow = idx
                                        viewModel.performJump()
                                    }
                                )
                                .id(idx)
                            }
                        }
                    }
                }
                .background(Color.white)
                .win32Sunken()
                .onChange(of: viewModel.selectedRow) { newRow in
                    proxy.scrollTo(newRow, anchor: .center)
                }
            }
            
            // Bottom Bar: Status on left, action buttons on right
            HStack(alignment: .center, spacing: 8) {
                let total = PlayerCoordinator.shared.playlist.tracks.count
                let matched = viewModel.filteredTracks.count
                Text(viewModel.searchText.isEmpty ? "\(total) files in playlist" : "\(matched) / \(total) files matching")
                    .font(.system(size: 11))
                    .foregroundColor(Win32Colors.textDisabled)
                
                Spacer()
                
                Win32Button("Jump", width: 70) {
                    viewModel.performJump()
                }
                .disabled(viewModel.filteredTracks.isEmpty)
                
                Win32Button("Enqueue", width: 70) {
                    viewModel.performEnqueue()
                }
                .disabled(viewModel.filteredTracks.isEmpty)
                
                Win32Button("Close", width: 70) {
                    onClose()
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(Win32Colors.dialogBg)
    }
}

// MARK: - Row View
private struct JumpTrackRowView: View {
    let displayIndex: Int
    let track: TrackItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            let label = "\(displayIndex). \(track.displayName)"
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(isSelected ? .white : Win32Colors.text)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            Text(track.formattedDuration)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isSelected ? .white : Color(red: 0.2, green: 0.2, blue: 0.2))
        }
        .padding(.horizontal, 6)
        .frame(height: 19)
        .background(isSelected ? Win32Colors.selectionBlue : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
    }
}

// MARK: - Auto-focusing NSTextField wrapper
private struct SearchInputField: NSViewRepresentable {
    @Binding var text: String
    
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.font = NSFont.systemFont(ofSize: 11)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        
        // Auto focus when window appears
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchInputField
        
        init(_ parent: SearchInputField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}
