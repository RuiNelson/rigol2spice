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
