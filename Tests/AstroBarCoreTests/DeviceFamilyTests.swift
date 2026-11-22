import Testing
@testable import AstroBarCore

@Suite("Device families")
struct DeviceFamilyTests {
    @Test("Gen 4 offers presets and an explicit save, but no HID volume")
    func gen4Capabilities() {
        let capabilities = DeviceFamily.gen4.capabilities
        #expect(capabilities.contains(.equalizerPresets))
        #expect(capabilities.contains(.saveToDevice))
        #expect(!capabilities.contains(.volumeKeys))
    }

    @Test("Logitech models apply values live and can take the volume keys")
    func logitechCapabilities() {
        for productID in A50X.productIDs {
            let capabilities = DeviceFamily.logitech(productID: productID).capabilities
            #expect(capabilities.contains(.volumeKeys))
            #expect(!capabilities.contains(.equalizerPresets))
            #expect(!capabilities.contains(.saveToDevice))
        }
    }

    @Test("Names come from the family")
    func names() {
        #expect(DeviceFamily.gen4.modelName == "ASTRO A50")
        #expect(DeviceFamily.gen4.settingsTitle == "Astro A50 (Gen 4)")
        #expect(DeviceFamily.logitech(productID: A50X.a50XProductID).modelName == "ASTRO A50 X")
        #expect(DeviceFamily.logitech(productID: A50X.gen5ProductID).settingsTitle == "ASTRO A50 (Gen 5)")
    }

    @Test("Model UID parsing reads the trailing hex ids")
    func modelUIDParsing() throws {
        let gen4 = try #require(AudioModelUID.parse("Astro A50 Game:9886:002C"))
        #expect(gen4.vendorID == 0x9886)
        #expect(gen4.productID == 0x002C)
        // A colon in the name must not confuse the split.
        let named = try #require(AudioModelUID.parse("A50: X Game:046D:0B0B"))
        #expect(named.vendorID == 0x046D)
        #expect(named.productID == 0x0B0B)
        #expect(AudioModelUID.parse("Built-in Output") == nil)
        #expect(AudioModelUID.parse("Name:zzzz:0B0B") == nil)
    }

    @Test("Only the Logitech A50 ids count as the X output")
    func logitechOutputMatch() {
        #expect(AudioModelUID.isLogitechA50("ASTRO A50 X Game:046D:0B0B"))
        #expect(AudioModelUID.isLogitechA50("ASTRO A50 Game:046D:0B1C"))
        #expect(!AudioModelUID.isLogitechA50("Astro A50 Game:9886:002C"))
        #expect(!AudioModelUID.isLogitechA50("Some Headset:046D:0A87"))
        #expect(!AudioModelUID.isLogitechA50("A50 lookalike"))
    }
}
