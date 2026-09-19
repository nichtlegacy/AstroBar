import Testing
@testable import AstroBarCore

@Suite("A50 decoding")
struct DecodingTests {
    @Test("Battery byte splits charging bit and percent")
    func batteryDecode() {
        let onBattery = BatteryStatus(rawByte: 0x37) // 55%, bit7 clear
        #expect(onBattery.chargePercent == 55)
        #expect(onBattery.isCharging == false)

        let charging = BatteryStatus(rawByte: 0x80 | 80)
        #expect(charging.chargePercent == 80)
        #expect(charging.isCharging == true)
    }

    @Test("Headset status bits")
    func headsetDecode() {
        let linkedUndocked = HeadsetStatus(rawByte: 0x02)
        #expect(linkedUndocked.isLinked == true)
        #expect(linkedUndocked.isDocked == false)

        let dockedLinked = HeadsetStatus(rawByte: 0x03)
        #expect(dockedLinked.isDocked == true)
        #expect(dockedLinked.isLinked == true)

        // Headset powered off while away from the base: no link, not docked.
        let gone = HeadsetStatus(rawByte: 0x00)
        #expect(gone.isLinked == false)
        #expect(gone.isDocked == false)
    }

    @Test("Charge percent above 100 is clamped")
    func clampsImpossibleCharge() {
        // The percent field is seven bits, so a bad frame can carry 127.
        #expect(BatteryStatus(rawByte: 127).chargePercent == 100)
        #expect(BatteryStatus(rawByte: 0x80 | 127).chargePercent == 100)
    }

    @Test("Balance fraction")
    func balanceFraction() {
        #expect(Balance(raw: 0).chatFraction == 0.0)
        #expect(Balance(raw: 255).chatFraction == 1.0)
    }

    @Test("Invalid preset throws instead of trapping")
    func invalidPresetThrows() async {
        let device = A50Device()

        do {
            try await device.setActiveEQPreset(9)
            Issue.record("Expected invalidArgument for preset")
        } catch let error as A50Error {
            guard case .invalidArgument(let detail) = error else {
                Issue.record("Expected invalidArgument, got \(error.localizedDescription)")
                return
            }
            #expect(detail == "preset must be one of 1, 2, 3")
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("Invalid EQ gain shape throws instead of trapping")
    func invalidGainShapeThrows() async {
        let device = A50Device()

        do {
            try await device.setEQPresetGain(1, gain: [0, 0, 0, 0])
            Issue.record("Expected invalidArgument for gain shape")
        } catch let error as A50Error {
            guard case .invalidArgument(let detail) = error else {
                Issue.record("Expected invalidArgument, got \(error.localizedDescription)")
                return
            }
            #expect(detail == "gain must contain 5 bands")
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("Invalid EQ band throws instead of trapping")
    func invalidBandThrows() async {
        let device = A50Device()

        do {
            _ = try await device.eqPresetBand(1, band: 8)
            Issue.record("Expected invalidArgument for band")
        } catch let error as A50Error {
            guard case .invalidArgument(let detail) = error else {
                Issue.record("Expected invalidArgument, got \(error.localizedDescription)")
                return
            }
            #expect(detail == "band must be one of 1, 2, 3, 4, 5")
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }
}
