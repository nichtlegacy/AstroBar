import Testing
@testable import AstroBarCore

@Suite("A50 wire framing")
struct FrameTests {
    @Test("Request omits the length byte for empty payloads")
    func encodeEmpty() {
        #expect(A50Frame.encode(command: .getBatteryStatus) == [0x02, 0x7C])
    }

    @Test("Request carries length + payload for non-empty bodies")
    func encodePayload() {
        #expect(A50Frame.encode(command: .setSliderValue, payload: [0x05, 40]) == [0x02, 0x62, 0x02, 0x05, 40])
    }

    @Test("Response data is sliced by the declared length")
    func parseSlicesByLength() throws {
        let response: [UInt8] = [0x02, 0x02, 0x01, 55]
        #expect(try A50Frame.parse(response) == [55])
    }

    @Test("Padded responses (length field < bytes received) parse fine")
    func parsePaddedResponse() throws {
        // Firmware sometimes pads a 1-byte answer to 61 bytes.
        var response: [UInt8] = [0x02, 0x02, 0x01, 55]
        response.append(contentsOf: Array(repeating: 0, count: 57))
        #expect(try A50Frame.parse(response) == [55])
    }

    @Test("Over-declared length clamps to the bytes that actually arrived")
    func parseClampsOverlongLength() throws {
        let response: [UInt8] = [0x02, 0x02, 0x10, 55, 0, 0]
        #expect(try A50Frame.parse(response) == [55, 0, 0])
    }

    @Test("Wrong magic throws malformedResponse")
    func parseRejectsWrongMagic() {
        #expect(throws: A50Error.malformedResponse) {
            _ = try A50Frame.parse([0x01, 0x02, 0x00])
        }
    }

    @Test("Error status throws deviceError")
    func parseRejectsErrorStatus() {
        #expect(throws: A50Error.deviceError(code: 0, name: nil)) {
            _ = try A50Frame.parse([0x02, 0x01, 0x00])
        }
    }

    @Test("Error replies carry a code and an ASCII name")
    func parseDecodesErrorName() {
        // Captured from a Gen 4 base station answering a request for EQ preset 9.
        let frame: [UInt8] = [0x02, 0x01, 0x24, 0x0D, 0x00, 0x00, 0x00]
            + Array("HID_ERROR_NO_EQ_WITH_THAT_VALUE".utf8) + [0x00, 0x00]
        #expect(throws: A50Error.deviceError(code: 13, name: "HID_ERROR_NO_EQ_WITH_THAT_VALUE")) {
            _ = try A50Frame.parse(frame)
        }
    }

    @Test("An under-reported length still yields the bytes the caller needs")
    func parseHonoursMinimumLength() throws {
        // Length says one byte; twelve arrived and the caller needs all of them.
        let frame: [UInt8] = [0x02, 0x02, 0x01] + Array(1 ... 12)
        #expect(try A50Frame.parse(frame, atLeast: 12) == Array(1 ... 12))
        // Without a stated minimum the declared length still wins.
        #expect(try A50Frame.parse(frame) == [1])
    }

    @Test("A minimum longer than the frame is capped, not padded")
    func parseCapsMinimumAtArrival() throws {
        let frame: [UInt8] = [0x02, 0x02, 0x01, 0x42]
        #expect(try A50Frame.parse(frame, atLeast: 12) == [0x42])
    }

    @Test("noResponse status is accepted and yields empty data")
    func parseAcceptsNoResponse() throws {
        #expect(try A50Frame.parse([0x02, 0x00, 0x00]) == [])
    }

    @Test("Truncated frames throw")
    func parseRejectsTruncated() {
        #expect(throws: A50Error.malformedResponse) {
            _ = try A50Frame.parse([0x02, 0x02])
        }
    }
}
