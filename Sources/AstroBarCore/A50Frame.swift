import Foundation

/// Encoding and decoding of raw 64-byte wire frames.
///
/// Frames are `[0x02, type, length, …payload]` for requests and
/// `[0x02, status, length, …data]` for responses. Pure functions — kept
/// separate from `A50Device` so framing rules are unit-testable.
enum A50Frame {
    /// Build a request report for a command.
    static func encode(command: A50Command, payload: [UInt8] = []) -> [UInt8] {
        var request: [UInt8] = [A50.magic, command.rawValue]
        if !payload.isEmpty {
            request.append(UInt8(payload.count))
            request.append(contentsOf: payload)
        }
        return request
    }

    /// Validate a response and return its data section.
    ///
    /// The declared length is advisory: firmware revisions both pad responses
    /// (reporting 61 bytes for a one-byte answer) and under-report them. So the
    /// caller states how many bytes it needs via `atLeast`, and the length is
    /// taken as the larger of the two, capped at what actually arrived.
    static func parse(_ response: [UInt8], atLeast minimum: Int = 0) throws -> [UInt8] {
        guard response.count >= 3, response[0] == A50.magic else {
            throw A50Error.malformedResponse
        }
        if response[1] == A50ResponseStatus.error.rawValue {
            throw decodeError(response)
        }
        guard response[1] == A50ResponseStatus.ok.rawValue
            || response[1] == A50ResponseStatus.noResponse.rawValue else {
            throw A50Error.malformedResponse
        }
        let available = response.count - 3
        let length = min(max(Int(response[2]), minimum), available)
        return Array(response[3 ..< 3 + length])
    }

    /// Decode an error reply.
    ///
    /// Observed on a Gen 4 base station: `02 01 24 0d 00 00 00 "HID_ERROR_…" 00`
    /// — a little-endian 32-bit code at the start of the payload, then a
    /// NUL-terminated ASCII name four bytes in.
    static func decodeError(_ response: [UInt8]) -> A50Error {
        let payload = Array(response.dropFirst(3))
        guard payload.count >= 4 else { return .deviceError(code: 0, name: nil) }

        let code = Int(payload[0]) | (Int(payload[1]) << 8) | (Int(payload[2]) << 16) | (Int(payload[3]) << 24)
        let nameBytes = payload.dropFirst(4).prefix { $0 >= 0x20 && $0 < 0x7F }
        let name = nameBytes.isEmpty ? nil : String(decoding: nameBytes, as: UTF8.self)
        return .deviceError(code: code, name: name)
    }
}
