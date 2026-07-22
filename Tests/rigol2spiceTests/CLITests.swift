import Foundation
import Testing

struct CLITests {
    @Test
    func `analysis sees transformed waveform before output downsample`() throws {
        let result = try runCLI([
            samplePath(named: "Legacy"),
            "-c", "CH2",
            "-t", "Offset 1; Multiply 2",
            "-d", "3",
            "-a", "Points; Avg; Max",
        ])

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(!result.stdout.contains("Downsampling signal output"))
        #expect(result.stdout.contains("Points: 1.2k"))
        // Offset then multiply produces values around 2; reversed order would be around 1.
        #expect(result.stdout.contains("Avg: 2"))
        #expect(result.stdout.contains("Max: 2"))
    }

    @Test
    func `downsample applies only to the written signal after analysis`() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-downsample-\(UUID().uuidString).m")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runCLI([
            samplePath(named: "Legacy"), output.path,
            "-c", "CH2",
            "-d", "3",
            "-a", "Points",
            "--format", "matlab",
        ])

        #expect(result.status == 0)
        #expect(result.stdout.contains("Points: 1.2k"))
        #expect(result.stdout.contains("Downsampling signal output by 3×"))
        let lines = try String(contentsOf: output, encoding: .ascii)
            .split(whereSeparator: \Character.isNewline)
        #expect(lines.count == 402)
    }

    @Test
    func `cli accepts multiline transformation and analysis lists`() throws {
        let result = try runCLI([
            samplePath(named: "Legacy"),
            "-c", "CH2",
            "-t", "Offset 1\r\nMultiply 2",
            "-a", "Points\nAvg",
        ])

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("Points: 1.2k"))
        #expect(result.stdout.contains("Avg: 2"))
    }

    @Test
    func `short command file options prepend file commands to inline commands`() throws {
        let transformationsFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-transformations-\(UUID().uuidString).txt")
        let analysisFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-analysis-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: transformationsFile)
            try? FileManager.default.removeItem(at: analysisFile)
        }
        try "Offset 1\r\n".write(to: transformationsFile, atomically: true, encoding: .utf8)
        try "FFT 1024\n".write(to: analysisFile, atomically: true, encoding: .utf8)

        let result = try runCLI([
            samplePath(named: "Legacy"),
            "-c", "CH2",
            "-tf", transformationsFile.path,
            "-t", "Multiply 2",
            "-af", analysisFile.path,
            "-a", "THD; Avg",
        ])

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("THD:"))
        // File first: (input + 1) × 2 averages approximately 2; reverse order would average 1.
        #expect(result.stdout.contains("Avg: 2"))
    }

    @Test
    func `long command file options work without inline lists`() throws {
        let transformationsFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-transformations-\(UUID().uuidString).txt")
        let analysisFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-analysis-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: transformationsFile)
            try? FileManager.default.removeItem(at: analysisFile)
        }
        try "Offset 1".write(to: transformationsFile, atomically: true, encoding: .utf8)
        try "Avg".write(to: analysisFile, atomically: true, encoding: .utf8)

        let result = try runCLI([
            samplePath(named: "Legacy"),
            "-c", "CH2",
            "--transformations-file", transformationsFile.path,
            "--analysis-file", analysisFile.path,
        ])

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("Avg: 1"))
    }

    @Test
    func `unreadable command file returns a useful error`() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-missing-\(UUID().uuidString).txt")
        let result = try runCLI([
            samplePath(named: "Legacy"),
            "-tf", missing.path,
            "-a", "Points",
        ])

        #expect(result.status != 0)
        #expect((result.stdout + result.stderr).contains("Could not read transformations file"))
        #expect((result.stdout + result.stderr).contains(missing.path))
    }

    @Test
    func `console analysis combines engineering notation with units`() throws {
        let result = try runCLI([
            samplePath(named: "Legacy"),
            "-c", "CH2",
            "-a", "End; Max; Min",
        ])

        #expect(result.status == 0)
        #expect(result.stdout.contains("End: 2.4ms"))
        #expect(result.stdout.contains("Max: 8.4mV"))
        #expect(result.stdout.contains("Min: -2.4mV"))
    }

    @Test
    func `FFT dependent analysis without preceding FFT returns an error`() throws {
        let result = try runCLI([
            samplePath(named: "Legacy"),
            "-a", "THD",
        ])

        #expect(result.status != 0)
        #expect((result.stdout + result.stderr).contains("requires an FFT analysis earlier"))
    }

    @Test
    func `cli writes transformed PWL data end to end`() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-cli-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runCLI([
            samplePath(named: "Legacy"),
            output.path,
            "-c", "CH2",
            "-k",
            "-t", "Offset 1; Multiply 2",
        ])

        #expect(result.status == 0)
        let text = try String(contentsOf: output, encoding: .ascii)
        let lines = text.split(whereSeparator: \Character.isNewline)
        #expect(lines.count == 1200)
        #expect(lines.first == "0\t2.0152")
    }

    @Test
    func `MATLAB output always keeps every processed point`() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-cli-\(UUID().uuidString).m")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runCLI([
            samplePath(named: "Legacy"),
            output.path,
            "--format", "matlab",
            "-c", "CH2",
        ])

        #expect(result.status == 0)
        #expect(!result.stdout.contains("Removing redundant sample points"))
        let text = try String(contentsOf: output, encoding: .ascii)
        let lines = text.split(whereSeparator: \Character.isNewline)
        #expect(lines.count == 1202)
        #expect(lines.first == "points = [")
        #expect(lines.dropFirst().first == "0.0076;")
        #expect(lines.last == "];")
    }

    @Test
    func `wav16 output keeps every point and writes source sample rate`() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-cli-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runCLI([
            samplePath(named: "Legacy"),
            output.path,
            "--format", "wav16",
            "--channel", "CH2",
        ])

        #expect(result.status == 0)
        #expect(!result.stdout.contains("Removing redundant sample points"))
        let data = try Data(contentsOf: output)
        #expect(data.count == 44 + 1200 * 2)
        #expect(String(decoding: data[0 ..< 4], as: UTF8.self) == "RIFF")
        let sampleRate = UInt32(data[24])
            | UInt32(data[25]) << 8
            | UInt32(data[26]) << 16
            | UInt32(data[27]) << 24
        #expect(sampleRate == 500_000)
    }

    @Test
    func `resampling updates the rate used by later filters`() throws {
        let result = try runCLI([
            samplePath(named: "Legacy"),
            "-c", "CH2",
            "-t", "ResampleF 10k; LowPass 6k",
            "-a", "Points",
        ])

        #expect(result.status != 0)
        #expect((result.stdout + result.stderr).contains("Nyquist (5000.0 Hz)"))
    }

    @Test
    func `wav output writes the resampled rate`() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-resampled-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runCLI([
            samplePath(named: "Legacy"),
            output.path,
            "--format", "wav16",
            "--channel", "CH2",
            "--transformations", "ResampleF 10k",
        ])

        #expect(result.status == 0)
        let data = try Data(contentsOf: output)
        let sampleRate = UInt32(data[24])
            | UInt32(data[25]) << 8
            | UInt32(data[26]) << 16
            | UInt32(data[27]) << 24
        #expect(sampleRate == 10000)
    }

    @Test
    func `wav output rejects unnormalized samples with transformation suggestion`() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-cli-invalid-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runCLI([
            samplePath(named: "Legacy"),
            output.path,
            "--format", "wav32",
            "--transformations", "Multiply 1000",
        ])

        #expect(result.status != 0)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect((result.stdout + result.stderr).contains("PeakTo 1"))
    }

    @Test
    func `npy output keeps every vertical value`() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-cli-\(UUID().uuidString).npy")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runCLI([
            samplePath(named: "Legacy"),
            output.path,
            "--format", "npy",
            "--channel", "CH2",
        ])

        #expect(result.status == 0)
        #expect(!result.stdout.contains("Removing redundant sample points"))
        let data = try Data(contentsOf: output)
        let headerLength = Int(data[8]) | Int(data[9]) << 8
        #expect(data.count == 10 + headerLength + 1200 * 8)
        #expect((10 + headerLength).isMultiple(of: 64))
        #expect(data[0] == 0x93)
        #expect(String(decoding: data[1 ..< 6], as: UTF8.self) == "NUMPY")
    }

    @Test
    func `cli auto detects Centaurus CSV without an option`() throws {
        let result = try runCLI([
            samplePath(named: "Centaurus"),
            "-l",
        ])

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("Detected format: Centaurus CSV"))
        #expect(result.stdout.contains("- CH4V"))
    }

    @Test
    func `invalid transformation returns failure without producing output`() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-invalid-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runCLI([
            samplePath(named: "Legacy"),
            output.path,
            "-t", "NotARealTransformation 1",
        ])

        #expect(result.status != 0)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect((result.stdout + result.stderr).contains("NotARealTransformation"))
    }

    @Test
    func `cli auto detects WFM and prints instrument metadata`() throws {
        let result = try runCLI([
            samplePath(named: "reverse", extension: "wfm"),
            "-l",
        ])

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("Detected format: Rigol WFM"))
        #expect(result.stdout.contains("Model               : DS1104Z"))
        #expect(result.stdout.contains("Firmware            : 00.04.05.SP2"))
        #expect(result.stdout.contains("Horizontal scale    : 20us/div"))
        #expect(result.stdout.contains("Raw data file offset: 0xC91"))
        #expect(result.stdout.contains("- CH1"))
    }

    @Test
    func `cli converts WFM samples to PWL end to end`() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-wfm-cli-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runCLI([
            samplePath(named: "reverse", extension: "wfm"),
            output.path,
            "-k",
        ])

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        let text = try String(contentsOf: output, encoding: .ascii)
        let lines = text.split(whereSeparator: \Character.isNewline)
        #expect(lines.count == 12512)
        #expect(lines.first == "0\t0.05")
    }

    @Test
    func `cli decodes UART to a separate CSV output`() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-uart-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runCLI([
            samplePath(named: "Legacy"),
            "--decode", "UART rx=CH2, baud=500k, threshold=0",
            "--decode-format", "csv",
            "--decode-output", output.path,
        ])

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("Selected channel / expression: CH2"))
        #expect(result.stdout.contains("Decoding UART on CH2"))
        let csv = try String(contentsOf: output, encoding: .utf8)
        #expect(csv.hasPrefix("protocol,baud,start_time_s,end_time_s,byte_hex"))
    }

    @Test
    func `cli requires a file for binary decode output`() throws {
        let result = try runCLI([
            samplePath(named: "Legacy"),
            "--decode", "UART rx=CH2, baud=500k, threshold=0",
            "--decode-format", "bin",
        ])

        #expect(result.status != 0)
        #expect((result.stdout + result.stderr).contains("requires --decode-output"))
    }

    @Test
    func `cli loads multiple channels and decodes I2C`() throws {
        let input = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-i2c-\(UUID().uuidString).csv")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-i2c-\(UUID().uuidString)-decoded.csv")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }

        var states: [(sda: Bool, scl: Bool)] = []
        func append(_ sda: Bool, _ scl: Bool) {
            states.append(contentsOf: repeatElement((sda: sda, scl: scl), count: 3))
        }
        append(true, true)
        append(false, true)
        for byte in [UInt8(0xA0), UInt8(0x42)] {
            for bit in (0 ..< 8).map({ byte & (1 << (7 - $0)) != 0 }) + [false] {
                append(bit, false)
                append(bit, true)
            }
        }
        append(false, false)
        append(false, true)
        append(true, true)
        let rows = ["Time(s),SDA,SCL"] + states.enumerated().map {
            "\(Double($0.offset) * 1e-6),\($0.element.sda ? 3 : 0),\($0.element.scl ? 3 : 0)"
        }
        try rows.joined(separator: "\n").write(to: input, atomically: true, encoding: .utf8)

        let result = try runCLI([
            input.path,
            "--transformations", "Multiply 2",
            "--downsample", "3",
            "--decode", "I2C sda=SDA, scl=SCL, threshold=4",
            "--decode-format", "csv",
            "--decode-output", output.path,
        ])

        #expect(result.status == 0)
        #expect(result.stdout.contains("Decoding I2C on SDA=SDA, SCL=SCL"))
        #expect(!result.stdout.contains("Downsampling signal output"))
        let csv = try String(contentsOf: output, encoding: .utf8)
        #expect(csv.contains("I2C,0,"))
        #expect(csv.contains(",0xA0,160,address,0x50,write,true"))
        #expect(csv.contains(",0x42,66,data,,,true"))
    }

    private func runCLI(_ arguments: [String]) throws -> CLIResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return CLIResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        )
    }

    private var executableURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/rigol2spice")
    }

    private func samplePath(named name: String) throws -> String {
        try samplePath(named: name, extension: "csv")
    }

    private func samplePath(named name: String, extension fileExtension: String) throws -> String {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "SampleFiles",
        ) else {
            throw CLITestError.missingSample(name)
        }
        return url.path
    }

    private struct CLIResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private enum CLITestError: Error {
        case missingSample(String)
    }
}
