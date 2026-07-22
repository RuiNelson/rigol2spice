@testable import rigol2spice
import Foundation
import Testing

struct PlotWriterTests {
    @Test
    func `time tick interval uses decade steps`() {
        #expect(PlotWriter.timeTickInterval(duration: 2.5) == 0.1 || PlotWriter.timeTickInterval(duration: 2.5) == 1)
        #expect(PlotWriter.timeTickInterval(duration: 0.08) == 0.01)
        #expect(PlotWriter.timeTickInterval(duration: 0.0008) == 0.0001)
        #expect(PlotWriter.timeTickInterval(duration: 0) == 1)
    }

    @Test
    func `minor time ticks are one tenth of the major interval`() {
        #expect(PlotWriter.timeMinorTickInterval(majorInterval: 1e-3) == 1e-4)
        #expect(PlotWriter.timeMinorTickInterval(majorInterval: 1) == 0.1)
        #expect(PlotWriter.timeMinorTickInterval(majorInterval: 100e-6) == 10e-6)
        #expect(PlotWriter.isMultiple(1e-3, of: 1e-3))
        #expect(PlotWriter.isMultiple(2e-3, of: 1e-3))
        #expect(!PlotWriter.isMultiple(1.5e-3, of: 1e-3))
    }

    @Test
    func `spectrum axes use rounded divisions and bounded dynamic range`() {
        #expect(PlotWriter.spectrumTickInterval(span: 1000) == 200)
        #expect(PlotWriter.spectrumTickInterval(span: 2500) == 500)
        #expect(PlotWriter.spectrumTickInterval(span: 120) == 20)

        let bounds = PlotWriter.spectrumDBBounds([-240, -80, -20, 43])
        #expect(bounds.max == 60)
        #expect(bounds.min == -60)
        #expect(bounds.max - bounds.min == 120)
    }

    @Test
    func `nearest index finds the closest sample by time`() {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1e-3, value: 1),
            Point(time: 2e-3, value: 2),
            Point(time: 3e-3, value: 3),
        ]

        #expect(PlotWriter.nearestIndex(forTime: 0, in: points) == 0)
        #expect(PlotWriter.nearestIndex(forTime: 1.1e-3, in: points) == 1)
        #expect(PlotWriter.nearestIndex(forTime: 2.9e-3, in: points) == 3)
        #expect(PlotWriter.nearestIndex(forTime: 10, in: points) == 3)
    }

    @Test
    func `render produces svg with max mean min markers and one pixel per sample`() {
        let points = [
            Point(time: 0, value: -1),
            Point(time: 1e-3, value: 0),
            Point(time: 2e-3, value: 2),
            Point(time: 3e-3, value: 1),
        ]

        let svg = PlotWriter.render(points, sourceFile: "capture.csv", channel: "CH1+CH2")

        #expect(svg.contains("<svg"))
        #expect(svg.contains("class=\"signal\""))
        #expect(svg.contains(">max<"))
        #expect(svg.contains(">avg<"))
        #expect(svg.contains(">min<"))
        #expect(svg.contains("polyline"))
        #expect(svg.contains("class=\"grid-x-sub\""))
        #expect(svg.contains("class=\"grid-x\""))
        #expect(svg.contains("rigol2spice — capture.csv · CH1+CH2"))
        // Data area width = 4 px for 4 samples (plus margins 88 + 24).
        #expect(svg.contains("width=\"116.00\""))
    }

    @Test
    func `title includes source file basename and channel`() {
        #expect(
            PlotWriter.titleText(sourceFile: "/tmp/scope/capture.csv", channel: "CH2")
                == "rigol2spice — capture.csv · CH2",
        )
        #expect(PlotWriter.titleText(sourceFile: "", channel: "") == "rigol2spice")
    }

    @Test
    func `write creates an svg file`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-plot-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: url) }

        let points = [Point(time: 0, value: 1), Point(time: 1, value: -1)]
        let byteCount = try PlotWriter.write(
            points,
            to: url,
            sourceFile: "input.csv",
            channel: "CH1",
        )
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8)

        #expect(byteCount == data.count)
        #expect(text?.contains("<svg") == true)
        #expect(text?.contains("rigol2spice — input.csv · CH1") == true)
    }

    @Test
    func `render embeds analysis results when provided`() {
        let points = [
            Point(time: 0, value: -1),
            Point(time: 1, value: 1),
            Point(time: 2, value: -1),
            Point(time: 3, value: 1),
            Point(time: 4, value: -1),
            Point(time: 5, value: 1),
        ]
        let reports = AnalysisReport.reports(
            for: [.max, .min, .rms, .pkPk, .frequencyAt(0), .dc],
            on: points,
        )

        let svg = PlotWriter.render(
            points,
            sourceFile: "wave.csv",
            channel: "CH1",
            analysisReports: reports,
        )

        #expect(svg.contains("Analysis"))
        #expect(svg.contains("class=\"analysis-line\""))
        for report in reports {
            #expect(svg.contains(report.displayLine))
        }
        // Analysis is footer text only — no mid-plot analysis guides.
        #expect(!svg.contains("mark-analysis"))
        // Taller canvas to fit the analysis block under the axes.
        #expect(svg.contains("height=\"") && !svg.contains("height=\"492.00\""))
    }

    @Test
    func `render aligns decoded events below the time plot`() {
        let points = (0 ... 10).map { Point(time: Double($0), value: sin(Double($0))) }
        let svg = PlotWriter.render(
            points,
            sourceFile: "uart.csv",
            channel: "RX",
            decodeTitle: "UART · 9600 baud",
            decodeAnnotations: [
                PlotAnnotation(startTime: 2, endTime: 6, label: "0x41 & ACK", isError: false),
                PlotAnnotation(startTime: 7, endTime: 9, label: "0x42 · FRAMING", isError: true),
            ],
        )

        #expect(svg.contains("class=\"decode-panel\""))
        #expect(svg.contains("UART · 9600 baud"))
        #expect(svg.contains("class=\"decode-event\""))
        #expect(svg.contains("class=\"decode-event-error\""))
        #expect(svg.contains("0x41 &amp; ACK"))
        #expect(svg.contains("clip-path=\"url(#decode-clip-0)\""))

        let emptyDecode = PlotWriter.render(points, decodeTitle: "UART · 9600 baud")
        #expect(emptyDecode.contains("No decoded frames"))
    }

    @Test
    func `protocol results create useful plot labels`() {
        let uart = ProtocolDecodeResult.uart(UARTDecodeResult(
            baudRate: 9600,
            frames: [UARTFrame(
                startTime: 1, endTime: 2, value: 0x41, dataBits: 8,
                parityError: true, framingError: false,
            )],
        ))
        #expect(uart.plotAnnotations[0].label == "0x41 · ASCII \"A\" · PARITY")
        #expect(uart.plotAnnotations[0].isError)

        let i2cFrame = I2CFrame(
            transaction: 0, index: 0, startTime: 1, endTime: 2, value: 0xA1,
            acknowledged: true, isAddress: true, address: 0x50, read: true,
        )
        let i2c = ProtocolDecodeResult.i2c(I2CDecodeResult(transactions: [
            I2CTransaction(index: 0, startTime: 0, endTime: 3, repeatedStart: false, frames: [i2cFrame]),
        ]))
        #expect(i2c.plotAnnotations[0].label == "ADDR 0x50 R · ACK")

        let spi = ProtocolDecodeResult.spi(SPIDecodeResult(
            mode: 3, bitOrder: .msb,
            frames: [SPIFrame(index: 0, startTime: 1, endTime: 2, bitCount: 8, mosi: 0x12, miso: 0x34)],
        ))
        #expect(spi.plotAnnotations[0].label == "MOSI 0x12 ASCII \"\\x12\" · MISO 0x34 ASCII \"4\"")
    }

    @Test
    func `normalizePlotArguments inserts default path for bare plot flags`() {
        // Bare -p / --plot (nothing after, or next token is another flag) → plot.svg
        #expect(normalizePlotArguments(["input.csv", "-p"]) == ["input.csv", "--plot", "plot.svg"])
        #expect(normalizePlotArguments(["-p"]) == ["--plot", "plot.svg"])
        #expect(normalizePlotArguments(["--plot", "-k", "input.csv"]) == ["--plot", "plot.svg", "-k", "input.csv"])
        // Explicit path after -p
        #expect(normalizePlotArguments(["-p", "out.svg", "input.csv"]) == ["--plot", "out.svg", "input.csv"])
        #expect(normalizePlotArguments(["input.csv"]) == ["input.csv"])
    }
}
