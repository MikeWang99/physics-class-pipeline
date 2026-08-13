// create_multi_output.swift
// Creates (or reuses) a CoreAudio Multi-Output device containing the current
// default output device + BlackHole 2ch, so meeting audio plays normally AND
// gets mirrored into BlackHole for recording.
//
// Usage: swift create_multi_output.swift "Device Name"
//
// Note: AudioDeviceCreateAggregateDevice is a long-standing CoreAudio API.
// If this fails on a future macOS version, setup.sh falls back to manual
// instructions (Audio MIDI Setup -> Create Multi-Output Device).

import Foundation
import CoreAudio

let deviceName = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "PhysicsClass Multi-Output"

func check(_ status: OSStatus, _ what: String) {
    if status != noErr {
        FileHandle.standardError.write("ERROR \(what): OSStatus \(status)\n".data(using: .utf8)!)
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

func defaultOutputDevice() -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var id: AudioDeviceID = kAudioObjectUnknown
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id),
          "get default output")
    return id
}

func findDevice(named wanted: String) -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size),
          "device list size")
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: count)
    check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids),
          "device list")
    for id in ids where deviceName(id) == wanted {
        return id
    }
    return nil
}

// Reuse existing aggregate/multi-output device with the same name if present.
if let existing = findDevice(named: deviceName) {
    print("Reusing existing device '\(deviceName)' (id \(existing))")
    exit(0)
}

let blackHole = findDevice(named: "BlackHole 2ch")
guard let bh = blackHole else {
    FileHandle.standardError.write("ERROR: 'BlackHole 2ch' not found. Install it first.\n".data(using: .utf8)!)
    exit(1)
}

// Skip multi-output if default output is already BlackHole itself.
let defOut = defaultOutputDevice()
var subDevices: [AudioSubDevice] = []
if defOut != bh {
    subDevices.append(AudioSubDevice(sSubDeviceID: defOut, sDriftCompensation: 0))
}
subDevices.append(AudioSubDevice(sSubDeviceID: bh, sDriftCompensation: 0))

var description = AudioAggregateDeviceDescription(
    mName: (deviceName as CFString),
    mUID: ("physics-class-pipeline-\(Int(Date().timeIntervalSince1970))" as CFString),
    mMainSubDevice: defOut,
    mClockDevice: 0,
    mSubDeviceCount: subDevices.count,
    mSubDevices: &subDevices)

var newDevice: AudioDeviceID = kAudioObjectUnknown
let status = AudioDeviceCreateAggregateDevice(&description, &newDevice)
check(status, "create aggregate device")

// Mark it as a multi-output device (stacked outputs).
var isStacked: UInt32 = 1
var prop = AudioObjectPropertyAddress(
    mSelector: kAudioAggregateDevicePropertyIsStacked,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
let setStatus = AudioObjectSetPropertyData(newDevice, &prop, 0, nil, UInt32(MemoryLayout<UInt32>.size), &isStacked)
if setStatus != noErr {
    FileHandle.standardError.write("WARNING: could not set stacked flag: \(setStatus)\n".data(using: .utf8)!)
}

print("Created multi-output device '\(deviceName)' (id \(newDevice))")
