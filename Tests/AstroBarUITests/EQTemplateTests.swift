import AstroBarCore
import Foundation
import Testing
@testable import AstroBar

@Suite("EQ presets")
struct EQTemplateTests {
    @Test("Every bundled preset fits what the hardware accepts")
    func bundledPresetsAreValid() {
        #expect(EQTemplate.stock.count == 5)
        #expect(EQTemplate.community.count == 10)

        for template in EQTemplate.stock + EQTemplate.community {
            #expect(template.isWellFormed, "\(template.name) has the wrong band count")

            for db in template.gain {
                #expect(db >= A50Limits.minGain && db <= A50Limits.maxGain,
                        "\(template.name) gain \(db) is out of range")
            }

            for (index, band) in template.bands.enumerated() {
                #expect(band.centerFreq >= A50Limits.minCenterFreq
                        && band.centerFreq <= A50Limits.maxCenterFreq,
                        "\(template.name) band \(index + 1) centre \(band.centerFreq) is out of range")

                if index == 0 || index == 4 {
                    // Outer bands are shelves and carry no width.
                    #expect(band.bandwidth == 0, "\(template.name) shelf \(index + 1) has a bandwidth")
                } else {
                    #expect(band.bandwidth >= A50Limits.minBandwidth
                            && band.bandwidth <= A50Limits.maxBandwidth,
                            "\(template.name) band \(index + 1) width \(band.bandwidth) is out of range")
                }
            }
        }
    }

    @Test("Every bundled preset explains what it is for")
    func bundledPresetsHaveSummaries() {
        for template in EQTemplate.stock + EQTemplate.community {
            let summary = template.summary ?? ""
            #expect(!summary.isEmpty, "\(template.name) has no summary")
            // Long enough to mean something, short enough for a menu subtitle.
            #expect(summary.count <= 80, "\(template.name) summary is too long for a menu row")
        }
    }

    @Test("Bundled preset names are unique so the menu has no duplicates")
    func bundledNamesAreUnique() {
        let all = EQTemplate.stock + EQTemplate.community
        #expect(Set(all.map(\.name)).count == all.count)
    }

    @Test("Community bandwidths match the published Command Center figures")
    func communityBandwidthsConvertCorrectly() throws {
        // The .astroeq files state bandwidth as the 0.1–3.0 figure Command
        // Center shows; the device stores that times `bandwidthScale`.
        let expected: [String: [Double]] = [
            "RECTIFY4": [0, 1.6, 0.4, 0.6, 0],
            "PURE": [0, 2.0, 2.2, 1.9, 0],
            "DYSTRILATION": [0, 2.2, 1.8, 2.0, 0],
            "INCENDIARY": [0, 2.6, 2.4, 2.8, 0],
            "KRYOGEN": [0, 2.0, 3.0, 1.6, 0],
            "ARCTURUS": [0, 2.2, 2.0, 2.2, 0],
            "OMNIVOX": [0, 2.2, 2.4, 2.2, 0],
            "TOURNAMENT I": [0, 2.0, 2.4, 2.6, 0],
            "TOURNAMENT II": [0, 2.0, 2.4, 2.6, 0],
            "TOURNAMENT III": [0, 2.1, 2.6, 2.5, 0],
        ]

        for template in EQTemplate.community {
            let published = try #require(expected[template.name])
            for (band, figure) in zip(template.bands, published) {
                let asFigure = Double(band.bandwidth) / Double(A50Limits.bandwidthScale)
                #expect(abs(asFigure - figure) < 0.001,
                        "\(template.name) band width \(asFigure) should be \(figure)")
            }
        }
    }

    @Test("Export and import round-trip")
    func roundTrip() throws {
        let data = try EQTemplateFile(presets: EQTemplate.stock).encoded()
        #expect(try EQTemplateFile.decode(data) == EQTemplate.stock)
    }

    @Test("Garbage is rejected rather than half-read")
    func rejectsGarbage() {
        #expect(throws: EQTemplateFile.LoadError.unreadable) {
            _ = try EQTemplateFile.decode(Data("not json".utf8))
        }
    }

    @Test("A newer format version is refused")
    func rejectsFutureVersion() throws {
        var file = EQTemplateFile(presets: EQTemplate.stock)
        file.version = EQTemplateFile.currentVersion + 1
        let data = try file.encoded()

        #expect(throws: EQTemplateFile.LoadError.unsupportedVersion(EQTemplateFile.currentVersion + 1)) {
            _ = try EQTemplateFile.decode(data)
        }
    }

    @Test("Presets with the wrong band count are dropped")
    func dropsMalformedPresets() throws {
        let broken = EQTemplate(name: "Broken", gain: [0, 0], bands: [])
        let data = try EQTemplateFile(presets: [broken] + EQTemplate.stock).encoded()

        let loaded = try EQTemplateFile.decode(data)
        #expect(loaded == EQTemplate.stock)
    }

    @Test("A file of nothing but malformed presets fails loudly")
    func rejectsAllMalformed() throws {
        let broken = EQTemplate(name: "Broken", gain: [], bands: [])
        let data = try EQTemplateFile(presets: [broken]).encoded()

        #expect(throws: EQTemplateFile.LoadError.noUsablePresets) {
            _ = try EQTemplateFile.decode(data)
        }
    }
}
