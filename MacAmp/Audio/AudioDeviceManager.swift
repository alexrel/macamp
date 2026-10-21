import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

public enum AudioDeviceTransportType: String, Codable, CaseIterable {
    case builtIn = "Built-in"
    case bluetooth = "Bluetooth"
    case hdmi = "HDMI / DisplayPort"
    case usb = "USB"
    case airplay = "AirPlay"
    case virtual = "Virtual"
    case other = "Other"
    
    public var iconSymbol: String {
        switch self {
        case .builtIn: return "speaker.wave.2"
        case .bluetooth: return "headphones"
        case .hdmi: return "display"
        case .usb: return "cable.connector"
        case .airplay: return "airplayaudio"
        case .virtual: return "waveform.circle"
        case .other: return "speaker"
        }
    }
    
    public static func from(rawTransport: UInt32) -> AudioDeviceTransportType {
        switch rawTransport {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return .hdmi
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeAirPlay:
            return .airplay
        case kAudioDeviceTransportTypeVirtual:
            return .virtual
        default:
            return .other
        }
    }
}

public struct AudioOutputDevice: Identifiable, Equatable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let transportType: AudioDeviceTransportType
    public let isDefault: Bool
    public let channelCount: Int
    public let sampleRate: Double
    
    public init(id: AudioDeviceID, uid: String, name: String, transportType: AudioDeviceTransportType, isDefault: Bool, channelCount: Int, sampleRate: Double) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transportType = transportType
        self.isDefault = isDefault
        self.channelCount = channelCount
        self.sampleRate = sampleRate
    }
    
    public var displayName: String {
        "[\(transportType.rawValue)] \(name)"
    }
}

public final class AudioDeviceManager: ObservableObject {
    public static let shared = AudioDeviceManager()
    
    @Published public private(set) var availableDevices: [AudioOutputDevice] = []
    @Published public private(set) var defaultDevice: AudioOutputDevice? = nil
    @Published public private(set) var selectedDeviceUID: String? = nil
    @Published public private(set) var activeDevice: AudioOutputDevice? = nil
    
    public var onDevicesChanged: (([AudioOutputDevice]) -> Void)?
    public var onDefaultDeviceChanged: ((AudioOutputDevice?) -> Void)?
    public var onActiveDeviceChanged: ((AudioOutputDevice?) -> Void)?
    
    private var isListening: Bool = false
    
    public init() {
        self.selectedDeviceUID = PersistenceManager.shared.state.selectedAudioOutputDeviceUID
        refreshDevices()
        registerCoreAudioListeners()
    }
    
    deinit {
        unregisterCoreAudioListeners()
    }
    
    // MARK: - Device Enumeration
    
    public func refreshDevices() {
        let defaultID = fetchDefaultOutputDeviceID()
        let allIDs = fetchAllDeviceIDs()
        
        var outputs: [AudioOutputDevice] = []
        for devID in allIDs {
            let channels = fetchOutputChannelCount(deviceID: devID)
            guard channels > 0 else { continue }
            
            let name = fetchDeviceName(deviceID: devID)
            let uid = fetchDeviceUID(deviceID: devID)
            // Core Audio's private aggregates (e.g. "CADefaultDeviceAggregate-85254-0") and hidden devices
            // are implementation details, not choices for the user
            if uid.hasPrefix("CADefaultDeviceAggregate") || name.hasPrefix("CADefaultDeviceAggregate") || isHidden(deviceID: devID) {
                continue
            }
            let rawTransport = fetchTransportType(deviceID: devID)
            let transport = AudioDeviceTransportType.from(rawTransport: rawTransport)
            let isDef = (devID == defaultID)
            let sampleRate = fetchSampleRate(deviceID: devID)
            
            let device = AudioOutputDevice(
                id: devID,
                uid: uid,
                name: name,
                transportType: transport,
                isDefault: isDef,
                channelCount: channels,
                sampleRate: sampleRate
            )
            outputs.append(device)
        }
        
        self.availableDevices = outputs
        self.defaultDevice = outputs.first(where: { $0.id == defaultID }) ?? outputs.first
        
        // Re-evaluate active device
        updateActiveDevice()
    }
    
    public func updateActiveDevice() {
        if let selUID = selectedDeviceUID, let found = availableDevices.first(where: { $0.uid == selUID }) {
            self.activeDevice = found
        } else {
            // Falls back to system default
            self.activeDevice = defaultDevice
        }
        onActiveDeviceChanged?(self.activeDevice)
    }
    
    // MARK: - Device Selection
    
    public func selectDevice(uid: String?) {
        self.selectedDeviceUID = uid
        PersistenceManager.shared.state.selectedAudioOutputDeviceUID = uid
        PersistenceManager.shared.saveSession()
        
        let targetID: AudioDeviceID?
        if let uid = uid, let found = availableDevices.first(where: { $0.uid == uid }) {
            targetID = found.id
        } else {
            // System Default (nil routes to default in AudioEngine)
            targetID = nil
        }
        
        AudioEngine.shared.setOutputDevice(deviceID: targetID)
        updateActiveDevice()
        MainMenuManager.shared.updateStates()
    }
    
    public func activeOutputDeviceID() -> AudioDeviceID? {
        if let selUID = selectedDeviceUID, let found = availableDevices.first(where: { $0.uid == selUID }) {
            return found.id
        }
        return nil // System Default
    }
    
    public func device(for uid: String) -> AudioOutputDevice? {
        availableDevices.first(where: { $0.uid == uid })
    }
    
    public func device(for id: AudioDeviceID) -> AudioOutputDevice? {
        availableDevices.first(where: { $0.id == id })
    }
    
    // MARK: - CoreAudio Property Listeners
    
    private func registerCoreAudioListeners() {
        guard !isListening else { return }
        
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            guard let self = self else { return }
            self.refreshDevices()
            self.onDevicesChanged?(self.availableDevices)
            
            // Re-apply route if needed
            let targetID = self.activeOutputDeviceID()
            AudioEngine.shared.setOutputDevice(deviceID: targetID)
        }
        
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            guard let self = self else { return }
            self.refreshDevices()
            self.onDefaultDeviceChanged?(self.defaultDevice)
            
            // If following system default, update output unit
            if self.selectedDeviceUID == nil {
                AudioEngine.shared.setOutputDevice(deviceID: nil)
            }
        }
        
        isListening = true
    }
    
    private func unregisterCoreAudioListeners() {
        // Observers run for application lifecycle
        isListening = false
    }
    
    // MARK: - CoreAudio Low-Level Helpers
    
    private func fetchAllDeviceIDs() -> [AudioDeviceID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let fetchStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard fetchStatus == noErr else { return [] }
        return deviceIDs
    }
    
    private func isHidden(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIsHidden,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var hidden: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &hidden) == noErr else { return false }
        return hidden != 0
    }
    
    private func fetchDefaultOutputDeviceID() -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultDeviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size, &defaultDeviceID)
        return status == noErr ? defaultDeviceID : 0
    }
    
    private func fetchDeviceName(deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, ptr)
        }
        return (status == noErr && name != nil) ? (name! as String) : "Audio Device #\(deviceID)"
    }
    
    private func fetchDeviceUID(deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, ptr)
        }
        return (status == noErr && uid != nil) ? (uid! as String) : "device_\(deviceID)"
    }
    
    private func fetchTransportType(deviceID: AudioDeviceID) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &transport)
        return status == noErr ? transport : 0
    }
    
    private func fetchOutputChannelCount(deviceID: AudioDeviceID) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &size)
        guard status == noErr, size > 0 else { return 0 }
        
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferList.deallocate() }
        let err = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, bufferList)
        guard err == noErr else { return 0 }
        
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
    
    private func fetchSampleRate(deviceID: AudioDeviceID) -> Double {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &sampleRate)
        return status == noErr ? Double(sampleRate) : 44100.0
    }
}
