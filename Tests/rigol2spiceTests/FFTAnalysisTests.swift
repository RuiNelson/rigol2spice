@testable import rigol2spice
import Foundation
import Testing

struct FFTAnalysisTests {
    @Test
    func `parses fft point count and window position`() throws {
        #expect(try Analysis.parseList("FFT") == [.fft(pointCount: nil, position: .start)])
        #expect(try Analysis.parseList("FFT 1024") == [.fft(pointCount: 1024, position: .start)])
        #expect(try Analysis.parseList("fft 1k") == [.fft(pointCount: 1000, position: .start)])
        #expect(try Analysis.parseList("FFT middle") == [.fft(pointCount: nil, position: .middle)])
        #expect(try Analysis.parseList("FFT 1024, middle") == [.fft(pointCount: 1024, position: .middle)])
        #expect(try Analysis.parseList("FFT 1024, end") == [.fft(pointCount: 1024, position: .end)])
        #expect(try Analysis.parseList("FFT 1024, centre") == [.fft(pointCount: 1024, position: .middle)])
        #expect(throws: (any Error).self) {
            try Analysis.parseList("FFT 0")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("FFT -8")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("FFT 1.5")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("FFT 1, 2")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("FFT 1024, nowhere")
        }
    }

    @Test
    func `bare fft uses every sample`() throws {
        let points = (0 ..< 50).map { index in
            Point(time: Double(index) * 1e-3, value: sin(Double(index)))
        }
        let spectrum = try #require(
            {
                let outcome = Analysis.fft(pointCount: nil, position: .start).evaluate(on: points)
                guard case let .fft(spectrum) = outcome else {
                    return nil as FFTSpectrum?
                }
                return spectrum
            }(),
        )
        #expect(spectrum.usedPointCount == 50)
        #expect(spectrum.requestedPointCount == 50)
        #expect(!AnalysisReport.reports(for: [.fft(pointCount: nil, position: .start)], on: points)[0]
            .displayLine.contains("requested"))
        #expect(spectrum.windowPosition == .start)
    }

    @Test
    func `selects start middle and end windows and falls back to available samples`() throws {
        let points = (0 ..< 20).map { index in
            Point(time: Double(index) * 1e-3, value: Double(index))
        }

        let defaultStart = try #require(computeFFTSpectrum(points: points, requestedPointCount: 8))
        let explicitStart = try #require(computeFFTSpectrum(
            points: Array(points[0 ..< 8]),
            requestedPointCount: 8,
        ))
        let middle = try #require(computeFFTSpectrum(
            points: points,
            requestedPointCount: 8,
            position: .middle,
        ))
        let explicitMiddle = try #require(computeFFTSpectrum(
            points: Array(points[6 ..< 14]),
            requestedPointCount: 8,
        ))
        let end = try #require(computeFFTSpectrum(
            points: points,
            requestedPointCount: 8,
            position: .end,
        ))
        let explicitEnd = try #require(computeFFTSpectrum(
            points: Array(points[12 ..< 20]),
            requestedPointCount: 8,
        ))

        #expect(defaultStart.magnitudes == explicitStart.magnitudes)
        #expect(middle.magnitudes == explicitMiddle.magnitudes)
        #expect(end.magnitudes == explicitEnd.magnitudes)
        #expect(defaultStart.windowPosition == .start)
        #expect(middle.windowPosition == .middle)
        #expect(end.windowPosition == .end)
        #expect(defaultStart.fftSize == 8)

        let capped = try #require(computeFFTSpectrum(points: points, requestedPointCount: 1000))
        #expect(capped.requestedPointCount == 1000)
        #expect(capped.usedPointCount == 20)
        #expect(capped.fftSize == 32) // next power of two of the *used* count, not 1000

        // Same spectrum whether you ask for 1000 or exactly 20 when only 20 exist.
        let exact = try #require(computeFFTSpectrum(points: points, requestedPointCount: 20))
        #expect(capped.usedPointCount == exact.usedPointCount)
        #expect(capped.fftSize == exact.fftSize)
        #expect(abs(capped.centerFrequency - exact.centerFrequency) < 1e-12)

        let report = AnalysisReport.reports(
            for: [.fft(pointCount: 5000, position: .end)],
            on: points,
        )[0]
        #expect(report.displayLine.hasPrefix("FFT 20 end:"))
        #expect(report.displayLine.contains("requested 5000"))
    }

    @Test
    func `dominant peak finds the tone frequency of a sine wave`() throws {
        let frequency = 50.0
        let sampleRate = 2000.0
        let count = 1024
        let points = (0 ..< count).map { index in
            let time = Double(index) / sampleRate
            return Point(time: time, value: sin(2 * Double.pi * frequency * time))
        }

        let spectrum = try #require(computeFFTSpectrum(points: points, requestedPointCount: count))
        let resolution = spectrum.sampleRate / Double(spectrum.fftSize)
        #expect(abs(spectrum.centerFrequency - frequency) <= resolution * 1.5)

        let report = AnalysisReport.reports(
            for: [.fft(pointCount: count, position: .start)],
            on: points,
        )[0]
        #expect(report.displayLine.hasPrefix("FFT \(count) start:"))
        #expect(report.displayLine.contains("Hz"))
        #expect(report.displayLine.contains("dB"))
        #expect(spectrum.centerMagnitude > 0)
        #expect(spectrum.centerMagnitudeDB.isFinite)
    }

    @Test
    func `dc offset does not steal the peak after zero padding`() throws {
        // Same shape as the Legacy CH1 issue: large DC + ~1 kHz tone, non-power-of-two length.
        let frequency = 1000.0
        let sampleRate = 500_000.0
        let count = 1200
        let points = (0 ..< count).map { index in
            let time = Double(index) / sampleRate
            // ~0…3 V square-ish / sine with ~1.5 V DC, like the scope capture.
            return Point(time: time, value: 1.5 + 1.5 * sin(2 * Double.pi * frequency * time))
        }

        let allPoints = try #require(computeFFTSpectrum(points: points, requestedPointCount: count))
        let resolution = allPoints.sampleRate / Double(allPoints.fftSize)
        #expect(allPoints.fftSize == 2048) // zero-padded
        #expect(abs(allPoints.centerFrequency - frequency) <= resolution * 1.5)

        // Requesting more than available must match using all samples.
        let oversize = try #require(computeFFTSpectrum(points: points, requestedPointCount: 5000))
        #expect(oversize.usedPointCount == count)
        #expect(abs(oversize.centerFrequency - frequency) <= resolution * 1.5)
    }

    @Test
    func `plot render includes spectrum polyline for fft analysis`() {
        let frequency = 100.0
        let sampleRate = 2000.0
        let count = 256
        let points = (0 ..< count).map { index in
            let time = Double(index) / sampleRate
            return Point(time: time, value: sin(2 * Double.pi * frequency * time))
        }
        let reports = AnalysisReport.reports(
            for: [.fft(pointCount: count, position: .start), .rms],
            on: points,
        )

        let svg = PlotWriter.render(
            points,
            sourceFile: "tone.csv",
            channel: "CH1",
            analysisReports: reports,
        )

        #expect(svg.contains("class=\"spectrum\""))
        #expect(svg.contains("class=\"spectrum-title\""))
        #expect(svg.contains("class=\"grid-spectrum\""))
        #expect(svg.contains("class=\"grid-spectrum-sub\""))
        #expect(svg.contains("class=\"label-x label-x-end\""))
        #expect(svg.contains("Δf"))
        #expect(svg.contains("dB</text>"))
        #expect(svg.contains("Hz · "))
        #expect(svg.contains("FFT \(count) pts"))
        #expect(svg.contains(reports[0].displayLine))
        #expect(svg.contains(reports[1].displayLine))
    }

    @Test
    func `FFT dependent analyses require and reuse the preceding FFT`() throws {
        for source in ["THD", "Fundamental", "Harmonic 3"] {
            #expect(throws: try AnalysisParseError
                .fftRequired(operation: #require(source.split(separator: " ").first.map(String.init)))) {
                try Analysis.parseList(source)
            }
        }
        #expect(try Analysis.parseList("FFT 1k, start; THD; Fundamental; Harmonic 3") == [
            .fft(pointCount: 1000, position: .start),
            .thd,
            .fundamental,
            .harmonic(number: 3),
        ])
        #expect(throws: AnalysisParseError.invalidArgumentCount(
            operation: "Fundamental",
            expected: 0,
            actual: 1,
        )) {
            try Analysis.parseList("FFT; Fundamental 1k")
        }
        #expect(throws: AnalysisParseError.invalidArgumentCount(
            operation: "Harmonic",
            expected: 1,
            actual: 2,
        )) {
            try Analysis.parseList("FFT; Harmonic 3, 1k")
        }

        let sampleRate = 8192.0
        let windowCount = 1024
        let points = (0 ..< windowCount * 2).map { index -> Point in
            let time = Double(index) / sampleRate
            let frequency = index < windowCount ? 256.0 : 1024.0
            return Point(time: time, value: sin(2 * Double.pi * frequency * time))
        }
        let reports = AnalysisReport.reports(for: [
            .fft(pointCount: windowCount, position: .start),
            .rms,
            .fundamental,
            .fft(pointCount: windowCount, position: .end),
            .avg,
            .fundamental,
        ], on: points)

        guard case let .frequencyAndAmplitude(startFrequency, _) = reports[2].outcome,
              case let .frequencyAndAmplitude(endFrequency, _) = reports[5].outcome else {
            Issue.record("Expected both Fundamental analyses to consume a preceding FFT")
            return
        }
        #expect(abs(startFrequency - 256) < 1)
        #expect(abs(endFrequency - 1024) < 1)
        #expect(Analysis.thd.evaluate(on: points) == .unavailable)
    }

    @Test
    func `next power of two and hann helpers`() {
        #expect(nextPowerOfTwo(1) == 1)
        #expect(nextPowerOfTwo(2) == 2)
        #expect(nextPowerOfTwo(3) == 4)
        #expect(nextPowerOfTwo(1024) == 1024)
        #expect(nextPowerOfTwo(1025) == 2048)

        var values = [1.0, 1.0, 1.0, 1.0, 1.0]
        applyHannWindow(&values)
        #expect(abs(values[0]) < 1e-12)
        #expect(abs(values[values.count - 1]) < 1e-12)
        #expect(values[2] > 0.9)
    }
}
