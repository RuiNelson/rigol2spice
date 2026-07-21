import Foundation

#if canImport(ZIPFoundation)
    import ZIPFoundation
#endif

// MARK: - NumPyWriterError

enum NumPyWriterError: LocalizedError, Equatable {
    case arrayTooLarge
    case archiveTooLarge

    var errorDescription: String? {
        switch self {
        case .arrayTooLarge:
            "NumPy array is too large for the NPY 1.0 format"
        case .archiveTooLarge:
            "NumPy arrays are too large for the NPZ archive"
        }
    }
}

// MARK: - NPYWriter

struct NPYWriter {
    func write(_ values: [Double], to outputURL: URL) throws -> Int {
        let data = try makeData(values)
        try data.write(to: outputURL, options: .atomic)
        return data.count
    }

    func makeData(_ values: [Double]) throws -> Data {
        let headerText = "{'descr': '<f8', 'fortran_order': False, 'shape': (\(values.count),), }"
        let baseHeaderLength = headerText.utf8.count + 1
        let paddingLength = (64 - ((10 + baseHeaderLength) % 64)) % 64
        let headerLength = baseHeaderLength + paddingLength
        guard headerLength <= Int(UInt16.max) else {
            throw NumPyWriterError.arrayTooLarge
        }

        let (payloadSize, overflow) = values.count.multipliedReportingOverflow(by: MemoryLayout<UInt64>.size)
        guard !overflow else {
            throw NumPyWriterError.arrayTooLarge
        }

        var data = Data()
        data.reserveCapacity(10 + headerLength + payloadSize)
        data.append(0x93)
        data.append(contentsOf: "NUMPY".utf8)
        data.append(1)
        data.append(0)
        data.appendLittleEndian(UInt16(headerLength))
        data.append(contentsOf: headerText.utf8)
        data.append(contentsOf: repeatElement(UInt8(ascii: " "), count: paddingLength))
        data.append(UInt8(ascii: "\n"))
        for value in values {
            data.appendLittleEndian(value.bitPattern)
        }
        return data
    }
}

// MARK: - NPZWriter

struct NPZWriter {
    func write(_ points: [Point], to outputURL: URL) throws -> Int {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("rigol2spice-npz-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let npyWriter = NPYWriter()
        let timestampsURL = temporaryDirectory.appendingPathComponent("timestamps.npy")
        let valuesURL = temporaryDirectory.appendingPathComponent("values.npy")
        _ = try npyWriter.write(points.map(\.time), to: timestampsURL)
        _ = try npyWriter.write(points.map(\.value), to: valuesURL)

        let data: Data
        #if canImport(ZIPFoundation)
            let archiveURL = temporaryDirectory.appendingPathComponent("output.npz")
            let archive = try Archive(url: archiveURL, accessMode: .create)
            try archive.addEntry(with: "timestamps.npy", fileURL: timestampsURL, compressionMethod: .none)
            try archive.addEntry(with: "values.npy", fileURL: valuesURL, compressionMethod: .none)
            data = try Data(contentsOf: archiveURL)
        #else
            data = try UncompressedZIPWriter().makeData(entries: [
                ("timestamps.npy", Data(contentsOf: timestampsURL)),
                ("values.npy", Data(contentsOf: valuesURL)),
            ])
        #endif
        try data.write(to: outputURL, options: .atomic)
        return data.count
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: some FixedWidthInteger) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
