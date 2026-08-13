// create_multi_output.swift
// Creates (or reuses) a CoreAudio Multi-Output device containing the current
// default output device + BlackHole 2ch, so meeting audio plays normally AND
// gets mirrored into BlackHole for recording.
//
// Modern macOS SDKs no longer expose AudioDeviceCreateAggregateDevice, so we
// use the supported workaround: write the aggregate device definition into the
// "Audio Device Preferences" plist. The device becomes visible after the
// coreaudiod service restarts (handled by setup_audio.sh).
//
// Usage: swift create_multi_output.swift "Device Name"

import Foundation
import CoreAudio

let deviceName = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "PhysicsClass Multi-Output"

func check(_ status: OSStatus, _ what: String) {
    if status != noErr {
        FileHandle.standardError.write("ERROR (\(what)): OSStatus \(status)\n".data(using: .utf8)!)
        exit(1)
    }
}

func deviceName(_ id: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceNameCFString,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name)
    return status == noErr ? (name as String) : ""
}

func deviceUID(_ id: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var uid: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &uid)
    return status == noErr ? (uid as String) : ""
}

func defaultOutputDevice() -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var device: AudioDeviceID = kAudioObjectUnknown
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                    0, nil, &size, &device), "get default output")
    return device
}

func findDevice(named name: String) -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &size), "device list size")
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: kAudioObjectUnknown, count: count)
    check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                     0, nil, &size, &devices), "device list")
    return devices.first { deviceName($0).lowercased().contains(name.lowercased()) }
}

guard let bh = findDevice(named: "BlackHole") else {
    FileHandle.standardError.write("ERROR: BlackHole device not found (reboot after install)\n".data(using: .utf8)!)
    exit(1)
}

// reuse an existing multi-output device with our name
if findDevice(named: deviceName) != nil {
    print("multi-output device '\(deviceName)' already exists")
    exit(0)
}

let defOut = defaultOutputDevice()
var subDevices: [[String: Any]] = []
if defOut != bh && defOut != kAudioObjectUnknown {
    subDevices.append([
        "audio-subdevice-uid": deviceUID(defOut),
        "drift-compensation": 0,
    ])
}
subDevices.append([
    "audio-subdevice-uid": deviceUID(bh),
    "drift-compensation": 0,
])

let uid = "physics-class-pipeline-multiout"
let aggregate: [String: Any] = [
    "aggregate-device-uid": uid,
    "name": deviceName,
    "main-subdevice": deviceUID(defOut != bh ? defOut : bh),
    "is-stack": 1,
    "is-named": 1,
    "is-hidden": 0,
    "subdevices": subDevices,
]

// merge into existing "Audio Device Preferences" (com.apple.audio.SystemSettings,
// currentHost domain) using Foundation property-list APIs
func hostPlistPath() -> String? {
    let dir = NSHomeDirectory() + "/Library/Preferences/ByHost"
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
    if let existing = files.first(where: { $0.hasPrefix("com.apple.audio.SystemSettings") && $0.hasSuffix(".plist") }) {
        return dir + "/" + existing
    }
    // never created before: borrow the hardware UUID suffix from any other ByHost plist
    if let donor = files.first(where: { $0.hasSuffix(".plist") }) {
        let comps = donor.components(separatedBy: ".")
        if comps.count >= 3 {
            let uuid = comps[comps.count - 2]
            return dir + "/com.apple.audio.SystemSettings." + uuid + ".plist"
        }
    }
    return nil
}

func readHostDomain() -> [String: Any] {
    guard let path = hostPlistPath(),
          let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        return [:]
    }
    return plist
}

func writeHostDomain(_ plist: [String: Any]) {
    guard let path = hostPlistPath() else {
        FileHandle.standardError.write("ERROR: cannot locate/create ByHost plist\n".data(using: .utf8)!)
        exit(1)
    }
    let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    try! data.write(to: URL(fileURLWithPath: path))
}

var plist = readHostDomain()
var prefs = plist["Audio Device Preferences"] as? [[String: Any]] ?? []
prefs.removeAll { ($0["aggregate-device-uid"] as? String) == uid }
prefs.append(aggregate)
plist["Audio Device Preferences"] = prefs
writeHostDomain(plist)

print("multi-output device '\(deviceName)' written to Audio Device Preferences")
print("NOTE: restart coreaudiod to activate: sudo killall coreaudiod")
