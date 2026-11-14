import AppKit
import CoreAudio
import OSLog

/// Detects apps that are currently producing or capturing audio, so they are not
/// quit while a call or playback is in progress.
@MainActor
final class AudioActivityMonitor {
    private let logger = Logger(subsystem: "com.swiftquit.SwiftQuit", category: "Audio")

    func activeBundleIDs() -> Set<String> {
        guard let objects = processObjects() else { return [] }

        var result = Set<String>()
        for object in objects {
            guard isRunning(object, selector: kAudioProcessPropertyIsRunningOutput)
                || isRunning(object, selector: kAudioProcessPropertyIsRunningInput)
            else { continue }
            guard let pid = pid(of: object),
                  let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier
            else { continue }
            result.insert(bundleID)
        }
        return result
    }

    private func processObjects() -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr,
              size > 0
        else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        let status: OSStatus = objects.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return OSStatus(-1) }
            return AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, base)
        }
        guard status == noErr else {
            logger.error("Could not read the audio process list")
            return nil
        }
        return objects
    }

    private func isRunning(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    private func pid(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid)
        return status == noErr ? pid : nil
    }
}
