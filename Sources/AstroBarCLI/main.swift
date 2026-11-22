import AstroBarCore
import Foundation

// Diagnostic CLI: connect to the A50 base station and dump everything it exposes.
// Usage:
//   astrobar-cli dump             read-only dump of every value
//   astrobar-cli get-eq           print the active EQ preset
//   astrobar-cli set-eq <1-3>     set the active EQ preset
//   astrobar-cli selftest-write   toggle the EQ preset and restore it (writes!)
//   astrobar-cli x-status         A50 X / Gen 5: battery, volume and mix
//   astrobar-cli x-volume <0-21>  A50 X / Gen 5: set the headset volume
//   astrobar-cli x-probe          A50 X / Gen 5: read the settings not decoded yet

func usage() -> Never {
    let name = URL(fileURLWithPath: CommandLine.arguments.first ?? "astrobar-cli").lastPathComponent
    FileHandle.standardError.write(
        "usage: \(name) [dump | get-eq | set-eq <1-3> | selftest-write | probe-error | x-status | x-volume <0-21> | x-probe]\n".data(using: .utf8)!)
    exit(2)
}

func waitForConnection(_ device: A50Device, timeout: TimeInterval) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if device.isConnected { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return device.isConnected
}

func line(_ label: String, _ value: String) {
    print("  \(label.padding(toLength: 22, withPad: " ", startingAt: 0)) \(value)")
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "dump"

switch command {
case "dump", "get-eq", "set-eq", "selftest-write", "probe-error", "x-status", "x-volume", "x-probe":
    break
default:
    usage()
}

// set-eq needs a valid preset number; typos must not fall through to dump.
if command == "set-eq" {
    guard arguments.count == 2,
          let preset = Int(arguments[1]),
          A50Limits.eqPresets.contains(preset) else {
        usage()
    }
}

// The A50 X and A50 Gen 5 speak a different protocol on a different device.
if command == "x-status" || command == "x-volume" || command == "x-probe" {
    var requestedVolume: Int?
    if command == "x-volume" {
        guard arguments.count == 2, let level = Int(arguments[1]), A50X.volumeRange.contains(level) else {
            usage()
        }
        requestedVolume = level
    }

    let station = A50XDevice()
    await station.start()
    let deadline = Date().addingTimeInterval(5)
    while !station.isConnected, Date() < deadline {
        try? await Task.sleep(for: .milliseconds(100))
    }
    guard station.isConnected else {
        print("✗ A50 X / A50 Gen 5 base station not found"); exit(1)
    }

    // Read requests for the settings whose replies have not been decoded yet,
    // so their layout can be read off the hardware. Nothing is written.
    if command == "x-probe" {
        let settings: [(String, UInt8)] = [
            ("sidetone", 0x09), ("equalizer", 0x0D), ("dock light", 0x0F), ("noise gate", 0x14),
        ]
        print(A50X.modelName(productID: station.productID ?? 0))
        for (name, id) in settings {
            do {
                let payload = try await station.rawRead(command: id)
                let hex = payload.map { String(format: "%02x", $0) }.joined(separator: " ")
                line(name, "\(payload.count) bytes: \(hex)")
            } catch {
                line(name, "no value (\(error.localizedDescription))")
            }
        }
        exit(0)
    }

    do {
        if let requestedVolume {
            try await station.setVolume(requestedVolume)
            try? await Task.sleep(for: .milliseconds(300))
        }
        print(A50X.modelName(productID: station.productID ?? 0))
        let battery = try await station.battery()
        line("Battery", "\(battery.status.chargePercent)%" + (battery.isDocked ? " (on base)" : ""))
        let volume = try await station.volume()
        let mix = try await station.chatMix()
        line("Volume", "\(volume) of \(A50X.volumeRange.upperBound)")
        line("Game/voice mix", "\(mix) of \(A50X.chatMixRange.upperBound)")
        exit(0)
    } catch {
        print("✗ \(error.localizedDescription)"); exit(1)
    }
}

let device = A50Device()
await device.start()

// Sends deliberately invalid requests and hex-dumps the raw replies, so the
// shape of an error frame can be read off the hardware instead of guessed.
if command == "probe-error" {
    guard await waitForConnection(device, timeout: 5) else {
        print("✗ base station not found"); exit(1)
    }
    func hexDump(_ label: String, _ bytes: [UInt8]) {
        let shown = bytes.prefix(40)
        let hex = shown.map { String(format: "%02x", $0) }.joined(separator: " ")
        let ascii = String(decoding: shown.map { $0 >= 0x20 && $0 < 0x7F ? $0 : 0x2E }, as: UTF8.self)
        print("  \(label)")
        print("    hex   \(hex)")
        print("    ascii \(ascii)")
    }
    let probes: [(String, A50Command, [UInt8])] = [
        ("invalid preset (0x69 preset 9)", .getEQPresetGain, [9]),
        ("invalid band (0x70 preset 1 band 9)", .getEQPresetFreqAndBW, [1, 9]),
        ("unhandled command (0x74 set auto-shutoff)", .getAutoShutoffTimer, [99]),
        ("valid battery read, for comparison", .getBatteryStatus, []),
    ]
    for (label, cmd, payload) in probes {
        do {
            hexDump(label, try await device.rawExchange(command: cmd, payload: payload))
        } catch {
            print("  \(label)\n    threw \(error)")
        }
    }
    await device.stop()
    exit(0)
}

// Non-dump commands exit early.
if command == "selftest-write" {
    guard await waitForConnection(device, timeout: 3) else {
        print("✗ base station not found"); exit(1)
    }
    do {
        let current = try await device.activeEQPreset()
        print("Active EQ preset before: \(current)")
        let target = current == 1 ? 2 : 1
        try await device.setActiveEQPreset(target)
        // The firmware applies set-commands asynchronously; an immediate
        // read-back still returns the previous state.
        try await Task.sleep(for: .milliseconds(500))
        let after = try await device.activeEQPreset()
        print("Set to \(target), read back: \(after)  → \(after == target ? "WRITE OK ✓" : "MISMATCH ✗")")
        try await device.setActiveEQPreset(current)
        try await Task.sleep(for: .milliseconds(500))
        print("Restored to \(current): \(try await device.activeEQPreset())")
    } catch {
        print("write test failed: \(error.localizedDescription)"); exit(1)
    }
    await device.stop()
    exit(0)
}

if command == "get-eq" {
    guard await waitForConnection(device, timeout: 3) else { print("no device"); exit(1) }
    do {
        print(try await device.activeEQPreset())
    } catch {
        print("get-eq failed: \(error.localizedDescription)")
        await device.stop()
        exit(1)
    }
    await device.stop(); exit(0)
}
if command == "set-eq" {
    guard await waitForConnection(device, timeout: 3) else { print("no device"); exit(1) }
    do {
        try await device.setActiveEQPreset(Int(arguments[1])!)
        print("set \(arguments[1])")
    } catch {
        print("set-eq failed: \(error.localizedDescription)")
        await device.stop()
        exit(1)
    }
    await device.stop(); exit(0)
}

print("AstroBar diagnostics")
print(String(repeating: "─", count: 40))

guard await waitForConnection(device, timeout: 3) else {
    print("✗ A50 base station not found (0x\(String(A50.vendorID, radix: 16)):" +
          "0x\(String(A50.baseStationProductID, radix: 16))).")
    print("  If the headset is on a USB cable, switch to the base station.")
    exit(1)
}
print("✓ Connected to base station\n")

func dump(_ label: String, _ body: () async throws -> String) async {
    do { line(label, try await body()) }
    catch { line(label, "— (\(error.localizedDescription))") }
}

print("Battery & power")
await dump("Battery") {
    let b = try await device.batteryStatus()
    return "\(b.chargePercent)% " + (b.isCharging ? "(charging)" : "(on battery)")
}
await dump("Headset") {
    let s = try await device.headsetStatus()
    return (s.isLinked ? "linked" : "no link") + ", " + (s.isDocked ? "docked" : "undocked")
}

print("\nEqualizer")
await dump("Active preset") { "\(try await device.activeEQPreset())" }
for preset in A50Limits.eqPresets {
    await dump("Preset \(preset) name") { try await device.eqPresetName(preset) }
    await dump("Preset \(preset) gain (dB)") {
        let g = try await device.eqPresetGain(preset)
        return g.gain.map(String.init).joined(separator: ", ")
    }
}

print("\nMix sliders")
for slider in SliderType.allCases {
    await dump(slider.displayName) { "\(try await device.sliderValue(slider))%" }
}

print("\nAudio")
await dump("Balance (raw 0-255)") { "\(try await device.balance().raw)" }
await dump("Default balance") { "\(try await device.defaultBalance().raw)" }
await dump("Alert volume") { "\(try await device.alertVolume())%" }
await dump("Auto-shutoff timer") {
    let t = try await device.autoShutoffTimer()
    return t == 0 ? "off" : "raw \(t)"
}

print("\nMicrophone")
await dump("Mic EQ preset") { "\(try await device.micEQ())" }
await dump("Noise gate") { try await device.noiseGateMode().displayName }

print("\nDevice info")
await dump("USB id") { "\(try await device.deviceInfo())" }
await dump("Base firmware") { "\(try await device.baseFirmwareVersion())" }
await dump("Headset firmware") { "\(try await device.headsetFirmwareVersion())" }

print()
await device.stop()
