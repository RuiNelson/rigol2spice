@testable import rigol2spice
import Foundation
import Testing

struct RigolWFMFamilyTests {
    @Test
    func `detects supported Rigol families and deliberately excludes DHO`() throws {
        let cases: [(String, RigolWFMFamily)] = [
            ("DS1204B-A", .ds1000B),
            ("DS1202CA-A", .ds1000C),
            ("DS1102D-A", .ds1000DE),
            ("DS1052E", .ds1000DE),
            ("DS1054Z-A", .ds1000Z),
            ("DS2072A-5", .ds2000),
            ("DS4022-A", .ds4000),
        ]

        for (name, expected) in cases {
            let data = try referenceData(named: name)
            #expect(RigolWFMFamily.detect(in: data) == expected)
            #expect(CaptureFormat.detect(in: data) == .rigolWFM)
        }

        #expect(try RigolWFMFamily.detect(in: referenceData(named: "DHO824-ch1")) == nil)
    }

    @Test
    func `parses DS1000B reference waveform`() throws {
        let capture = try parse("DS1204B-A", channel: "CH1")

        #expect(capture.channels == ["CH1", "CH2", "CH3", "CH4"])
        #expect(capture.points.count == 8192)
        #expect(close(capture.sampleInterval, 8e-6))
        #expect(close(capture.points.first?.value, 3.04))
        #expect(capture.metadata?.model == "DS1204B")
        #expect(capture.metadata?.channels.first?.coupling == "DC")
    }

    @Test
    func `parses DS1000C reference waveform`() throws {
        let capture = try parse("DS1202CA-A", channel: "CH1")

        #expect(capture.channels == ["CH1", "CH2"])
        #expect(capture.points.count == 5120)
        #expect(close(capture.sampleInterval, 100e-6))
        #expect(close(capture.points.first?.value, 0.024))
        #expect(capture.metadata?.format == "Rigol DS1000C WFM")
    }

    @Test
    func `parses shared DS1000D and E layouts`() throws {
        let dCapture = try parse("DS1102D-A", channel: "CH1")
        let eCapture = try parse("DS1052E", channel: "CH1")

        #expect(dCapture.channels == ["CH1", "CH2"])
        #expect(dCapture.points.count == 1024)
        #expect(close(dCapture.sampleInterval, 10e-6))
        #expect(close(dCapture.points.first?.value, 0.16))
        #expect(eCapture.channels == ["CH1", "CH2"])
        #expect(eCapture.points.count == 8192)
        #expect(close(eCapture.sampleInterval, 2e-9))
        #expect(close(eCapture.points.first?.value, -0.04))
    }

    @Test
    func `parses DS2000 reference waveform and serial metadata`() throws {
        let capture = try parse("DS2072A-5", channel: "CH1")

        #expect(capture.channels == ["CH1", "CH2"])
        #expect(capture.points.count == 14000)
        #expect(close(capture.sampleInterval, 1e-9))
        #expect(close(capture.points.first?.value, 0.001, tolerance: 2e-9))
        #expect(capture.metadata?.serialNumber == "DS2D162450999")
        #expect(capture.metadata?.firmware == "00.03.05.03.03")
    }

    @Test
    func `parses DS4000 reference waveform`() throws {
        let capture = try parse("DS4022-A", channel: "CH1")

        #expect(capture.channels == ["CH1", "CH2", "CH3", "CH4"])
        #expect(capture.points.count == 7000)
        #expect(close(capture.sampleInterval, 2e-9))
        #expect(close(capture.points.first?.value, 137.5))
        #expect(capture.metadata?.serialNumber == "DS4A143500731")
        #expect(capture.metadata?.firmware == "00.02.03.00.03")
    }

    @Test
    func `additional Rigol families support channel expressions`() throws {
        let capture = try parse("DS1202CA-A", channel: "CH1-CH2")

        #expect(capture.selectedChannel == "CH1-CH2")
        #expect(capture.points.count == 5120)
        #expect(close(capture.points.first?.value, 0.024 - 0.66))
    }

    private func parse(_ name: String, channel: String) throws -> Capture {
        try RigolWFMParser().parse(referenceData(named: name), channel: channel)
    }

    private func referenceData(named name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root
            .appendingPathComponent("Reference/RigolWFM/tests/files/wfm", isDirectory: true)
            .appendingPathComponent("\(name).wfm")
        return try Data(contentsOf: url)
    }

    private func close(_ actual: Double?, _ expected: Double, tolerance: Double = 1e-9) -> Bool {
        guard let actual else {
            return false
        }
        return abs(actual - expected) <= max(tolerance, abs(expected) * 1e-6)
    }
}
