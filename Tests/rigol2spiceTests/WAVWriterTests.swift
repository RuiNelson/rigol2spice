@testable import rigol2spice
import Foundation
import Testing

struct WAVWriterTests {
    @Test
    func `wav32 writes mono IEEE float with fact chunk`() throws {
        let output = temporaryWAVURL()
        defer { try? FileManager.default.removeItem(at: output) }
        let points = samplePoints(values: [-1, 0, 1])

        let byteCount = try WAVWriter(encoding: .float32).write(points, to: output)
        let data = try Data(contentsOf: output)

        #expect(byteCount == 70)
        #expect(data.count == byteCount)
        #expect(ascii(data, at: 0, count: 4) == "RIFF")
        #expect(ascii(data, at: 8, count: 4) == "WAVE")
        #expect(uint16(data, at: 20) == 3)
        #expect(uint16(data, at: 22) == 1)
        #expect(uint32(data, at: 24) == 1000)
        #expect(uint32(data, at: 28) == 4000)
        #expect(uint16(data, at: 32) == 4)
        #expect(uint16(data, at: 34) == 32)
        #expect(ascii(data, at: 38, count: 4) == "fact")
        #expect(uint32(data, at: 46) == 3)
        #expect(ascii(data, at: 50, count: 4) == "data")
        #expect(uint32(data, at: 54) == 12)
        #expect(uint32(data, at: 58) == Float32(-1).bitPattern)
        #expect(uint32(data, at: 62) == Float32(0).bitPattern)
        #expect(uint32(data, at: 66) == Float32(1).bitPattern)
    }

    @Test
    func `wav16 writes mono signed PCM samples`() throws {
        let output = temporaryWAVURL()
        defer { try? FileManager.default.removeItem(at: output) }
        let points = samplePoints(values: [-1, 0, 1])

        let byteCount = try WAVWriter(encoding: .pcm16).write(points, to: output)
        let data = try Data(contentsOf: output)

        #expect(byteCount == 50)
        #expect(uint16(data, at: 20) == 1)
        #expect(uint32(data, at: 24) == 1000)
        #expect(uint32(data, at: 28) == 2000)
        #expect(uint16(data, at: 32) == 2)
        #expect(uint16(data, at: 34) == 16)
        #expect(ascii(data, at: 36, count: 4) == "data")
        #expect(uint32(data, at: 40) == 6)
        #expect(uint16(data, at: 44) == UInt16(bitPattern: -32768))
        #expect(uint16(data, at: 46) == 0)
        #expect(uint16(data, at: 48) == UInt16(bitPattern: 32767))
    }

    @Test
    func `timestamp floating point noise is accepted`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 0.001 + 1e-12, value: 0),
            Point(time: 0.002, value: 0),
        ]

        #expect(try WAVWriter.sampleRate(for: points) == 1000)
    }

    @Test
    func `nonuniform timestamps suggest ResampleF`() {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 0.0009, value: 0),
            Point(time: 0.002, value: 0),
        ]

        #expect(throws: WAVWriterError.nonUniformTimestamps(index: 1, suggestedRate: 1000)) {
            try WAVWriter.sampleRate(for: points)
        }
    }

    @Test
    func `nonintegral sample rate suggests ResampleF`() {
        let points = [Point(time: 0, value: 0), Point(time: 0.0011, value: 0)]

        #expect(throws: WAVWriterError.nonIntegralSampleRate(
            estimated: 1 / 0.0011,
            suggested: 909,
        )) {
            try WAVWriter.sampleRate(for: points)
        }
    }

    @Test
    func `samples outside normalized range suggest PeakTo`() throws {
        let output = temporaryWAVURL()
        defer { try? FileManager.default.removeItem(at: output) }
        let points = samplePoints(values: [0, 1.01])

        #expect(throws: WAVWriterError.sampleOutOfRange(index: 1, value: 1.01)) {
            try WAVWriter(encoding: .float32).write(points, to: output)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    private func samplePoints(values: [Double]) -> [Point] {
        values.enumerated().map { Point(time: Double($0.offset) / 1000, value: $0.element) }
    }

    private func temporaryWAVURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-\(UUID().uuidString).wav")
    }

    private func ascii(_ data: Data, at offset: Int, count: Int) -> String {
        String(decoding: data[offset ..< offset + count], as: UTF8.self)
    }

    private func uint16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func uint32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
