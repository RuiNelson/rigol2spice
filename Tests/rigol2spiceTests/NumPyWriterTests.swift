@testable import rigol2spice
import Foundation
import Testing

struct NumPyWriterTests {
    @Test
    func `npy writes a one dimensional little endian float64 array`() throws {
        let output = temporaryURL(extension: "npy")
        defer { try? FileManager.default.removeItem(at: output) }

        let byteCount = try NPYWriter().write([1, -2], to: output)
        let data = try Data(contentsOf: output)

        #expect(byteCount == 144)
        #expect(data[0] == 0x93)
        #expect(String(decoding: data[1 ..< 6], as: UTF8.self) == "NUMPY")
        #expect(data[6] == 1)
        #expect(data[7] == 0)
        let headerLength = Int(uint16(data, at: 8))
        let payloadOffset = 10 + headerLength
        #expect(headerLength == 118)
        #expect(payloadOffset.isMultiple(of: 64))
        let header = String(decoding: data[10 ..< payloadOffset], as: UTF8.self)
        #expect(header.contains("'descr': '<f8'"))
        #expect(header.contains("'fortran_order': False"))
        #expect(header.contains("'shape': (2,)"))
        #expect(header.last == "\n")
        #expect(uint64(data, at: payloadOffset) == Double(1).bitPattern)
        #expect(uint64(data, at: payloadOffset + 8) == Double(-2).bitPattern)
    }

    @Test
    func `npz stores named timestamp and value arrays`() throws {
        let output = temporaryURL(extension: "npz")
        defer { try? FileManager.default.removeItem(at: output) }
        let points = [Point(time: 0, value: 1), Point(time: 0.5, value: -2)]

        let byteCount = try NPZWriter().write(points, to: output)
        let data = try Data(contentsOf: output)

        #expect(byteCount == data.count)
        #expect(uint32(data, at: 0) == 0x0403_4B50)
        #expect(data.range(of: Data("timestamps.npy".utf8)) != nil)
        #expect(data.range(of: Data("values.npy".utf8)) != nil)
        #expect(uint32(data, at: data.count - 22) == 0x0605_4B50)
        #expect(uint16(data, at: data.count - 12) == 2)
    }

    @Test
    func `uncompressed zip writer creates a valid stored entry`() throws {
        let payload = Data([1, 2, 3])

        let data = try UncompressedZIPWriter().makeData(entries: [("a.npy", payload)])

        #expect(uint32(data, at: 0) == 0x0403_4B50)
        #expect(uint16(data, at: 8) == 0)
        #expect(uint32(data, at: 14) == 0x55BC_801D)
        #expect(uint32(data, at: 18) == 3)
        #expect(uint32(data, at: 22) == 3)
        #expect(String(decoding: data[30 ..< 35], as: UTF8.self) == "a.npy")
        #expect(data[35 ..< 38] == payload)
        #expect(uint32(data, at: data.count - 22) == 0x0605_4B50)
        #expect(uint16(data, at: data.count - 12) == 1)
    }

    private func temporaryURL(extension fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-\(UUID().uuidString).\(fileExtension)")
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

    private func uint64(_ data: Data, at offset: Int) -> UInt64 {
        (0 ..< 8).reduce(UInt64(0)) { result, byteIndex in
            result | UInt64(data[offset + byteIndex]) << UInt64(byteIndex * 8)
        }
    }
}
