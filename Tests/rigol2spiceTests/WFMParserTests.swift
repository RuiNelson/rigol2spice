@testable import rigol2spice
import Foundation
import Testing

struct WFMParserTests {
    @Test
    func `capture format detects WFM from magic and otherwise keeps CSV fallback`() throws {
        let wfm = try sampleData(named: "reverse", extension: "wfm")
        let csv = try sampleData(named: "reverse", extension: "csv")

        #expect(CaptureFormat.detect(in: wfm, csvFallback: .legacy) == .ds1000ZWFM)
        #expect(CaptureFormat.detect(in: csv, csvFallback: .legacy) == .legacy)
        #expect(CaptureFormat.detect(in: csv, csvFallback: .centaurus) == .centaurus)
    }

    @Test
    func `DS1000Z parser reads reverse WFM waveform and metadata`() throws {
        let capture = try DS1000ZWFMParser().parse(
            sampleData(named: "reverse", extension: "wfm"),
            channel: "ch1",
        )

        #expect(capture.channels == ["CH1"])
        #expect(capture.selectedChannel == "CH1")
        #expect(capture.points.count == 12512)
        #expect(capture.points.first?.time == 0)
        #expect(abs((capture.sampleInterval ?? 0) - 40e-9) < 1e-15)
        #expect(abs((capture.points.last?.time ?? 0) - 500.44e-6) < 1e-11)
        #expect(abs((capture.points.first?.value ?? 0) - 0.05) < 1e-12)

        let metadata = try #require(capture.metadata)
        #expect(metadata.format == "Rigol DS1000Z WFM")
        #expect(metadata.model == "DS1104Z")
        #expect(metadata.firmware == "00.04.05.SP2")
        #expect(metadata.fileVersion == 14)
        #expect(metadata.structureVersion == 0x1001)
        #expect(metadata.acquisitionMode == "Normal")
        #expect(metadata.timeMode == "Y-T")
        #expect(abs(metadata.horizontalScale - 20e-6) < 1e-15)
        #expect(abs(metadata.horizontalOffset - -112.6e-6) < 1e-15)
        #expect(metadata.memoryDepth == 12512)
        #expect(metadata.rawDataOffset == 0x0C91)
        #expect(metadata.channels.count == 1)
        #expect(metadata.channels.first?.name == "CH1")
        #expect(metadata.channels.first?.coupling == "AC")
        #expect(metadata.channels.first?.probeRatio == 10)
        #expect(metadata.channels.first?.voltsPerDivision == 1)
    }

    @Test
    func `DS1000Z parser can inspect channels without decoding samples`() throws {
        let capture = try DS1000ZWFMParser().parse(
            sampleData(named: "reverse", extension: "wfm"),
            channel: nil,
        )

        #expect(capture.channels == ["CH1"])
        #expect(capture.selectedChannel == nil)
        #expect(capture.points.isEmpty)
        #expect(capture.metadata?.model == "DS1104Z")
    }

    @Test
    func `DS1000Z parser supports channel expressions and reports missing channels`() throws {
        let data = try sampleData(named: "reverse", extension: "wfm")
        let capture = try DS1000ZWFMParser().parse(data, channel: "CH1*CH1")

        #expect(capture.selectedChannel == "CH1*CH1")
        #expect(capture.points.count == 12512)
        #expect(abs((capture.points.first?.value ?? 0) - 0.0025) < 1e-12)
        #expect(throws: ParseError.channelNotFound(channelLabel: "CH2")) {
            try DS1000ZWFMParser().parse(data, channel: "CH2")
        }
    }

    private func sampleData(named name: String, extension fileExtension: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: "SampleFiles",
            ),
        )
        return try Data(contentsOf: url)
    }
}
