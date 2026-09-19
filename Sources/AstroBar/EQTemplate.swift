import AstroBarCore
import Foundation

/// A complete equalizer preset: a name, five band gains, and the five bands'
/// centre frequency and bandwidth.
///
/// This is what gets written into one of the three slots on the base station,
/// and what the JSON import/export format carries.
struct EQTemplate: Codable, Equatable, Identifiable, Sendable {
    struct Band: Codable, Equatable, Sendable {
        var centerFreq: Int
        /// Zero for the outer two bands; they are shelves and carry no width.
        var bandwidth: Int
    }

    var name: String
    /// One line on what the preset is for, shown under its name in the menu.
    /// Absent for imported presets, which carry no description.
    var summary: String?
    /// Gain per band in dB, five entries.
    var gain: [Int]
    /// Five entries, band 1 through band 5.
    var bands: [Band]

    var id: String { name }

    var isWellFormed: Bool {
        gain.count == A50Limits.eqBands.count && bands.count == A50Limits.eqBands.count
    }
}

// MARK: - Stock presets

extension EQTemplate {
    /// The five presets Astro Command Center shipped.
    ///
    /// Astro Command Center is discontinued and never ran on Apple silicon, so
    /// these are only reachable by writing them back by hand. The values come
    /// from a USB capture of Command Center pushing each preset into a slot,
    /// published by manuacl/astro-a50-gui.
    static let stock: [EQTemplate] = [
        EQTemplate(
            name: "A50 MOD KIT",
            summary: "Compensates for the Mod Kit ear cushions, not the stock ones",
            gain: [-5, -7, 5, -7, 5],
            bands: [
                Band(centerFreq: 200, bandwidth: 0),
                Band(centerFreq: 325, bandwidth: 6963),
                Band(centerFreq: 2753, bandwidth: 8192),
                Band(centerFreq: 6691, bandwidth: 2048),
                Band(centerFreq: 11002, bandwidth: 0),
            ]),
        EQTemplate(
            name: "ASTRO",
            summary: "Astro's house sound: scooped mids, lifted bass and treble",
            gain: [6, -5, 0, 7, 7],
            bands: [
                Band(centerFreq: 90, bandwidth: 0),
                Band(centerFreq: 406, bandwidth: 8192),
                Band(centerFreq: 783, bandwidth: 8192),
                Band(centerFreq: 4001, bandwidth: 8192),
                Band(centerFreq: 7001, bandwidth: 0),
            ]),
        EQTemplate(
            name: "MEDIA",
            summary: "Gentle lift for dialogue and detail — music, video, voice chat",
            gain: [0, -3, 0, 2, 4],
            bands: [
                Band(centerFreq: 95, bandwidth: 0),
                Band(centerFreq: 406, bandwidth: 8192),
                Band(centerFreq: 783, bandwidth: 8192),
                Band(centerFreq: 3901, bandwidth: 6963),
                Band(centerFreq: 6339, bandwidth: 0),
            ]),
        EQTemplate(
            name: "PRO",
            summary: "Bass and presence boost with the mids pulled back",
            gain: [5, -2, 1, 7, 1],
            bands: [
                Band(centerFreq: 95, bandwidth: 0),
                Band(centerFreq: 406, bandwidth: 8192),
                Band(centerFreq: 783, bandwidth: 8192),
                Band(centerFreq: 3901, bandwidth: 2048),
                Band(centerFreq: 6339, bandwidth: 0),
            ]),
        EQTemplate(
            name: "STUDIO",
            summary: "Flat through the low end, brightened on top",
            gain: [0, 0, 0, 5, 7],
            bands: [
                Band(centerFreq: 95, bandwidth: 0),
                Band(centerFreq: 419, bandwidth: 4096),
                Band(centerFreq: 783, bandwidth: 8192),
                Band(centerFreq: 3499, bandwidth: 4096),
                Band(centerFreq: 6100, bandwidth: 0),
            ]),
    ]
}

// MARK: - Community presets

extension EQTemplate {
    /// Presets from The ZEFERENCE collection by ZaliaS.
    ///
    /// Published as `.astroeq` files — the format Astro Command Center itself
    /// reads — at github.com/XxUnkn0wnxX/TheZEFERENCE. Those files store the
    /// bandwidth as the figure Command Center displays (0.1–3.0); the device
    /// wants it multiplied by `A50Limits.bandwidthScale`, which is what the
    /// numbers below already are.
    ///
    /// Only the presets that apply to an A50 Gen 4 are bundled. The collection's
    /// A40 and Gen 3 tunings and its per-game presets are deliberately left out:
    /// the first target different hardware, the second are too narrow to sit in
    /// a menu bar app.
    static let community: [EQTemplate] = [
        // Retunes the A50 Gen 4's own frequency signature towards a studio
        // reference response. The one preset in the collection written for this
        // exact headset.
        EQTemplate(
            name: "RECTIFY4",
            summary: "Flattens the A50 Gen 4's own colouration — the neutral option",
            gain: [3, 7, -5, -5, 7],
            bands: [
                Band(centerFreq: 1890, bandwidth: 0),
                Band(centerFreq: 5120, bandwidth: 6554),
                Band(centerFreq: 6088, bandwidth: 1638),
                Band(centerFreq: 8992, bandwidth: 2458),
                Band(centerFreq: 11830, bandwidth: 0),
            ]),
        EQTemplate(
            name: "PURE",
            summary: "All-rounder for music, film and games, generous in the bass",
            gain: [5, 7, 3, 6, 4],
            bands: [
                Band(centerFreq: 96, bandwidth: 0),
                Band(centerFreq: 864, bandwidth: 8192),
                Band(centerFreq: 3642, bandwidth: 9011),
                Band(centerFreq: 6800, bandwidth: 7782),
                Band(centerFreq: 8414, bandwidth: 0),
            ]),
        EQTemplate(
            name: "DYSTRILATION",
            summary: "Crisp mids and treble, detail first — for instrumental music",
            gain: [5, 7, 6, 3, 4],
            bands: [
                Band(centerFreq: 90, bandwidth: 0),
                Band(centerFreq: 2125, bandwidth: 9011),
                Band(centerFreq: 3850, bandwidth: 7373),
                Band(centerFreq: 9275, bandwidth: 8192),
                Band(centerFreq: 14250, bandwidth: 0),
            ]),
        EQTemplate(
            name: "INCENDIARY",
            summary: "Theatrical low and mid range — film and general entertainment",
            gain: [5, 4, 5, 6, 5],
            bands: [
                Band(centerFreq: 196, bandwidth: 0),
                Band(centerFreq: 1200, bandwidth: 10650),
                Band(centerFreq: 3864, bandwidth: 9830),
                Band(centerFreq: 7832, bandwidth: 11469),
                Band(centerFreq: 15000, bandwidth: 0),
            ]),
        EQTemplate(
            name: "KRYOGEN",
            summary: "The reverse of Incendiary: lows and treble, mids left neutral",
            gain: [7, 6, 5, 6, 3],
            bands: [
                Band(centerFreq: 110, bandwidth: 0),
                Band(centerFreq: 2000, bandwidth: 8192),
                Band(centerFreq: 4000, bandwidth: 12288),
                Band(centerFreq: 6000, bandwidth: 6554),
                Band(centerFreq: 12000, bandwidth: 0),
            ]),
        EQTemplate(
            name: "ARCTURUS",
            summary: "Broad, weighty tuning meant to suit any game",
            gain: [5, 6, 4, 6, 5],
            bands: [
                Band(centerFreq: 100, bandwidth: 0),
                Band(centerFreq: 1775, bandwidth: 9011),
                Band(centerFreq: 4664, bandwidth: 8192),
                Band(centerFreq: 8210, bandwidth: 9011),
                Band(centerFreq: 11125, bandwidth: 0),
            ]),
        // Low and mid focus for audible footstep direction, meant to work
        // across a wide range of games rather than one title.
        EQTemplate(
            name: "OMNIVOX",
            summary: "Footstep direction across a wide range of games",
            gain: [6, -1, 4, 7, 2],
            bands: [
                Band(centerFreq: 125, bandwidth: 0),
                Band(centerFreq: 486, bandwidth: 9011),
                Band(centerFreq: 2000, bandwidth: 9830),
                Band(centerFreq: 3800, bandwidth: 9011),
                Band(centerFreq: 6200, bandwidth: 0),
            ]),
        // Three competitive variants: shooters differ in which band carries the
        // positional cues, so the author's advice is to try all three.
        EQTemplate(
            name: "TOURNAMENT I",
            summary: "Competitive FPS, variant 1 — try all three, keep what works",
            gain: [4, 5, 6, 5, 6],
            bands: [
                Band(centerFreq: 170, bandwidth: 0),
                Band(centerFreq: 1000, bandwidth: 8192),
                Band(centerFreq: 3464, bandwidth: 9830),
                Band(centerFreq: 8000, bandwidth: 10650),
                Band(centerFreq: 15000, bandwidth: 0),
            ]),
        EQTemplate(
            name: "TOURNAMENT II",
            summary: "Competitive FPS, variant 2 — sharper around 3 kHz",
            gain: [5, 4, 7, 6, 5],
            bands: [
                Band(centerFreq: 164, bandwidth: 0),
                Band(centerFreq: 1000, bandwidth: 8192),
                Band(centerFreq: 3200, bandwidth: 9830),
                Band(centerFreq: 8000, bandwidth: 10650),
                Band(centerFreq: 12147, bandwidth: 0),
            ]),
        EQTemplate(
            name: "TOURNAMENT III",
            summary: "Competitive FPS, variant 3 — calmer lows, lifted top end",
            gain: [4, 3, 7, 4, 6],
            bands: [
                Band(centerFreq: 150, bandwidth: 0),
                Band(centerFreq: 1128, bandwidth: 8602),
                Band(centerFreq: 3180, bandwidth: 10650),
                Band(centerFreq: 8296, bandwidth: 10240),
                Band(centerFreq: 11150, bandwidth: 0),
            ]),
    ]
}

// MARK: - File format

/// The on-disk shape of an exported preset file.
///
/// Versioned so a later format change can be told apart from a corrupt file
/// rather than silently mis-read.
struct EQTemplateFile: Codable, Sendable {
    static let currentVersion = 1

    var version = EQTemplateFile.currentVersion
    var presets: [EQTemplate]

    enum LoadError: LocalizedError, Equatable {
        case unreadable
        case unsupportedVersion(Int)
        case noUsablePresets

        var errorDescription: String? {
            switch self {
            case .unreadable: "That file is not a readable AstroBar preset file."
            case .unsupportedVersion(let version): "This file uses preset format version \(version), which this version of AstroBar cannot read."
            case .noUsablePresets: "That file contains no presets with five bands."
            }
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Reads a preset file, rejecting anything malformed rather than writing
    /// half-valid values to the hardware.
    static func decode(_ data: Data) throws -> [EQTemplate] {
        guard let file = try? JSONDecoder().decode(EQTemplateFile.self, from: data) else {
            throw LoadError.unreadable
        }
        guard file.version <= currentVersion else {
            throw LoadError.unsupportedVersion(file.version)
        }
        let usable = file.presets.filter(\.isWellFormed)
        guard !usable.isEmpty else { throw LoadError.noUsablePresets }
        return usable
    }
}
