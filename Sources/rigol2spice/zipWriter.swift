import Foundation

// MARK: - UncompressedZIPWriter

/// ZIPFoundation requires zlib, which it does not currently build with Swift's
/// Windows MSVC toolchain. NPZ only needs uncompressed ZIP entries, so Windows
/// uses this small store-only ZIP32 writer without an external executable.
struct UncompressedZIPWriter {
    private struct EntryMetadata {
        let name: [UInt8]
        let checksum: UInt32
        let size: UInt32
        let localHeaderOffset: UInt32
    }

    func makeData(entries: [(name: String, data: Data)]) throws -> Data {
        guard entries.count <= Int(UInt16.max) else {
            throw NumPyWriterError.archiveTooLarge
        }

        var archive = Data()
        var metadata: [EntryMetadata] = []
        metadata.reserveCapacity(entries.count)

        for entry in entries {
            let name = Array(entry.name.utf8)
            guard name.count <= Int(UInt16.max),
                  entry.data.count <= Int(UInt32.max),
                  archive.count <= Int(UInt32.max) else {
                throw NumPyWriterError.archiveTooLarge
            }

            let checksum = crc32(entry.data)
            let size = UInt32(entry.data.count)
            metadata.append(EntryMetadata(
                name: name,
                checksum: checksum,
                size: size,
                localHeaderOffset: UInt32(archive.count),
            ))

            archive.appendZIPLittleEndian(UInt32(0x0403_4B50))
            archive.appendZIPLittleEndian(UInt16(20))
            archive.appendZIPLittleEndian(UInt16(0))
            archive.appendZIPLittleEndian(UInt16(0))
            archive.appendZIPLittleEndian(UInt16(0))
            archive.appendZIPLittleEndian(UInt16(0))
            archive.appendZIPLittleEndian(checksum)
            archive.appendZIPLittleEndian(size)
            archive.appendZIPLittleEndian(size)
            archive.appendZIPLittleEndian(UInt16(name.count))
            archive.appendZIPLittleEndian(UInt16(0))
            archive.append(contentsOf: name)
            archive.append(entry.data)
        }

        guard archive.count <= Int(UInt32.max) else {
            throw NumPyWriterError.archiveTooLarge
        }
        let centralDirectoryOffset = UInt32(archive.count)

        for entry in metadata {
            archive.appendZIPLittleEndian(UInt32(0x0201_4B50))
            archive.appendZIPLittleEndian(UInt16(20))
            archive.appendZIPLittleEndian(UInt16(20))
            archive.appendZIPLittleEndian(UInt16(0))
            archive.appendZIPLittleEndian(UInt16(0))
            archive.appendZIPLittleEndian(UInt16(0))
            archive.appendZIPLittleEndian(UInt16(0))
            archive.appendZIPLittleEndian(entry.checksum)
            archive.appendZIPLittleEndian(entry.size)
            archive.appendZIPLittleEndian(entry.size)
            archive.appendZIPLittleEndian(UInt16(entry.name.count))
            archive.appendZIPLittleEndian(UInt16(0))
            archive.appendZIPLittleEndian(UInt16(0))
            archive.appendZIPLittleEndian(UInt16(0))
            archive.appendZIPLittleEndian(UInt16(0))
            archive.appendZIPLittleEndian(UInt32(0))
            archive.appendZIPLittleEndian(entry.localHeaderOffset)
            archive.append(contentsOf: entry.name)
        }

        let centralDirectorySize = archive.count - Int(centralDirectoryOffset)
        guard centralDirectorySize <= Int(UInt32.max) else {
            throw NumPyWriterError.archiveTooLarge
        }
        let entryCount = UInt16(metadata.count)
        archive.appendZIPLittleEndian(UInt32(0x0605_4B50))
        archive.appendZIPLittleEndian(UInt16(0))
        archive.appendZIPLittleEndian(UInt16(0))
        archive.appendZIPLittleEndian(entryCount)
        archive.appendZIPLittleEndian(entryCount)
        archive.appendZIPLittleEndian(UInt32(centralDirectorySize))
        archive.appendZIPLittleEndian(centralDirectoryOffset)
        archive.appendZIPLittleEndian(UInt16(0))
        return archive
    }

    private func crc32(_ data: Data) -> UInt32 {
        var checksum = UInt32.max
        for byte in data {
            let index = Int((checksum ^ UInt32(byte)) & 0xFF)
            checksum = (checksum >> 8) ^ Self.crc32Table[index]
        }
        return ~checksum
    }

    private static let crc32Table: [UInt32] = (0 ..< 256).map { value in
        (0 ..< 8).reduce(UInt32(value)) { checksum, _ in
            (checksum >> 1) ^ (checksum & 1 == 0 ? 0 : 0xEDB8_8320)
        }
    }
}

private extension Data {
    mutating func appendZIPLittleEndian(_ value: some FixedWidthInteger) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
