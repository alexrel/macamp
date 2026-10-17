import SwiftUI
import AppKit

public class JumpToTimeViewModel: ObservableObject {
    @Published public var minutes: Int = 0
    @Published public var seconds: Int = 0
    
    public let totalDuration: TimeInterval
    public let trackTitle: String
    public var onClose: (() -> Void)?
    
    public init() {
        let coord = PlayerCoordinator.shared
        let curTime = coord.audioEngine.currentTime
        let total = coord.playlist.currentTrack?.duration ?? 0
        
        self.minutes = max(0, Int(curTime) / 60)
        self.seconds = max(0, Int(curTime) % 60)
        self.totalDuration = total
        self.trackTitle = coord.playlist.currentTrack?.title ?? "No track playing"
    }
    
    public func performJump() {
        let target = TimeInterval(max(0, minutes * 60 + seconds))
        let clamped = max(0, min(totalDuration > 0 ? totalDuration : target, target))
        PlayerCoordinator.shared.seek(to: clamped)
        let minStr = String(format: "%02d", minutes)
        let secStr = String(format: "%02d", seconds)
        PlayerCoordinator.shared.mainView?.marquee.showTemporaryMessage("SEEK TO \(minStr):\(secStr)")
        onClose?()
    }
}

public struct JumpToTimeView: View {
    @ObservedObject public var viewModel: JumpToTimeViewModel
    public var onClose: () -> Void
    
    public init(viewModel: JumpToTimeViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Track Info
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.trackTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Win32Colors.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                let totalMin = Int(viewModel.totalDuration) / 60
                let totalSec = Int(viewModel.totalDuration) % 60
                Text("Track length: \(String(format: "%02d:%02d", totalMin, totalSec))")
                    .font(.system(size: 11))
                    .foregroundColor(Win32Colors.textDisabled)
            }
            
            // Jump Time Input
            Win32GroupBox("Jump to:") {
                HStack(spacing: 8) {
                    Spacer()
                    
                    Text("Minutes:")
                        .font(.system(size: 11))
                        .foregroundColor(Win32Colors.text)
                    
                    Win32NumberField(value: $viewModel.minutes, width: 44)
                    
                    Text("Seconds:")
                        .font(.system(size: 11))
                        .foregroundColor(Win32Colors.text)
                    
                    Win32NumberField(value: $viewModel.seconds, width: 44)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 8) {
                Spacer()
                
                Win32Button("Jump", width: 75) {
                    viewModel.performJump()
                }
                
                Win32Button("Cancel", width: 75) {
                    onClose()
                }
            }
        }
        .padding(12)
        .background(Win32Colors.dialogBg)
    }
}
