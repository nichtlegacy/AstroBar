import Testing
@testable import AstroBarCore

/// Frames in these tests were captured from an A50 X base station (046d:0b0b).
@Suite("A50 X wire framing")
struct A50XTests {
    private func padded(_ bytes: [UInt8]) -> [UInt8] {
        bytes + [UInt8](repeating: 0, count: 64 - bytes.count)
    }

    @Test("A read request is the six header bytes, padded to 64")
    func encodeRead() {
        let frame = A50XFrame.encode(command: A50XCommand.volume.rawValue, handle: A50XFrame.readHandle)
        #expect(frame == padded([0x02, 0x0c, 0x03, 0x00, 0x08, 0x0c]))
    }

    @Test("Setting the volume matches the frame G HUB sends")
    func encodeVolumeSet() {
        let frame = A50XFrame.encode(
            command: A50XCommand.volume.rawValue, handle: A50XFrame.volumeSetHandle, payload: [0xff, 8])
        #expect(frame == padded([0x02, 0x0c, 0x05, 0x00, 0x08, 0x1b, 0xff, 0x08]))
    }

    @Test("Battery reply decodes to percent and dock flag")
    func battery() throws {
        let message = try #require(A50XFrame.decode(padded([0x02, 0x0c, 0x06, 0x00, 0x06, 0x0c, 0x49, 0x4b])))
        #expect(message.command == A50XCommand.battery.rawValue)
        let value = try #require(A50XValue.battery(message.payload))
        #expect(value.percent == 73)
        #expect(value.isDocked == false)
    }

    @Test("Volume reply decodes to the wheel step")
    func volumeReply() throws {
        let message = try #require(A50XFrame.decode(padded([0x02, 0x0c, 0x06, 0x00, 0x08, 0x0c, 0x0a, 0x00, 0x07])))
        #expect(A50XValue.volume(message.payload) == 7)
    }

    @Test("A wheel push carries handle 0 and the new step")
    func volumePush() throws {
        let message = try #require(A50XFrame.decode(padded([0x02, 0x0c, 0x06, 0x00, 0x08, 0x00, 0x1f, 0x00, 0x15])))
        #expect(message.handle == 0)
        #expect(A50XValue.volume(message.payload) == 21)
    }

    @Test("Chat mix reply decodes to its position")
    func chatMix() throws {
        let message = try #require(A50XFrame.decode(padded([0x02, 0x0c, 0x04, 0x00, 0x0a, 0x0c, 0x06])))
        #expect(A50XValue.chatMix(message.payload) == 6)
    }

    @Test("Settings read from an A50 X decode to their values")
    func settings() {
        #expect(A50XValue.sidetone([0x01, 0x01, 0xff, 0x06]) == 6)
        #expect(A50XValue.dockLight([0x64]) == 100)
        #expect(A50XValue.noiseGate([0x00]) == A50XNoiseGate.off.rawValue)
    }

    @Test("Setting sidetone matches the frame G HUB sends")
    func encodeSidetoneSet() {
        let frame = A50XFrame.encode(
            command: A50XCommand.sidetone.rawValue, handle: A50XFrame.settingSetHandle, payload: [0x01, 0xff, 6])
        #expect(frame == padded([0x02, 0x0c, 0x06, 0x00, 0x09, 0x1c, 0x01, 0xff, 0x06]))
    }

    @Test("A bare acknowledgement has no payload")
    func acknowledgement() throws {
        let message = try #require(A50XFrame.decode(padded([0x02, 0x0c, 0x03, 0x00, 0x08, 0x1b])))
        #expect(message.payload.isEmpty)
    }

    @Test("Foreign and truncated frames are rejected")
    func rejects() {
        #expect(A50XFrame.decode(padded([0x02, 0x02, 0x01, 0x37])) == nil)
        #expect(A50XFrame.decode([0x02, 0x0c, 0x06, 0x00, 0x08, 0x0c]) == nil)
        #expect(A50XValue.volume([0x0a, 0x00, 0x16]) == nil)
    }
}
