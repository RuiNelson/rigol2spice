import Foundation
import Testing

struct CLITests {
    @Test
    func `analysis output is optional and sees transformed downsampled waveform`() throws {
        let result = try runCLI([
            samplePath(named: "Legacy"),
            "-c", "CH2",
            "-t", "Offset 1; Multiply 2",
            "-d", "3",
            "-a", "Points; Avg; Max",
        ])

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("From 1200 samples to 400 samples"))
        #expect(result.stdout.contains("Points: 400"))
        // Offset then multiply produces values around 2; reversed order would be around 1.
        #expect(result.stdout.contains("Avg: 2"))
        #expect(result.stdout.contains("Max: 2"))
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
