import Foundation
import SwiftEngineeringNumberFormatter

// MARK: - PlotWriter

enum PlotWriter {
    static let largePlotPointThreshold = 10000

    private static let plotHeight: Double = 400
    private static let leftMargin: Double = 88
    private static let rightMargin: Double = 24
    private static let topMargin: Double = 44
    private static let bottomMargin: Double = 48

    /// Compact engineering labels for axis ticks (1 decimal place).
    private static let plotEngineeringFormatter = EngineeringNumberFormatter(
        maximumFractionDigits: 1,
        locale: usLocale,
        useGreekMu: false,
    )

    /// Writes a modern SVG plot. Returns the number of bytes written.
    /// Width of the data area is one pixel per sample point.
    @discardableResult
    static func write(
        _ points: [Point],
        to outputURL: URL,
        sourceFile: String,
        channel: String,
    ) throws -> Int {
        let svg = render(points, sourceFile: sourceFile, channel: channel)
        guard let data = svg.data(using: .utf8) else {
            throw PlotError.encodingFailed
        }
        try data.write(to: outputURL, options: .atomic)
        return data.count
    }

    static func render(
        _ points: [Point],
        sourceFile: String = "",
        channel: String = "",
    ) -> String {
        guard !points.isEmpty else {
            return emptySVG(sourceFile: sourceFile, channel: channel)
        }

        let count = points.count
        let plotWidth = Double(max(count, 1))
        let width = leftMargin + plotWidth + rightMargin
        let height = topMargin + plotHeight + bottomMargin

        let values = points.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let meanValue = values.reduce(0, +) / Double(count)

        var yMin = minValue
        var yMax = maxValue
        if yMin == yMax {
            yMin -= 1
            yMax += 1
        }
        let yPadding = (yMax - yMin) * 0.06
        yMin -= yPadding
        yMax += yPadding
        let yRange = yMax - yMin

        func xPixel(_ index: Int) -> Double {
            leftMargin + Double(index)
        }

        func yPixel(_ value: Double) -> Double {
            topMargin + (yMax - value) / yRange * plotHeight
        }

        var polyline = ""
        polyline.reserveCapacity(count * 12)
        for (index, point) in points.enumerated() {
            let x = xPixel(index)
            let y = yPixel(point.value)
            if index == 0 {
                polyline.append("\(formatCoord(x)),\(formatCoord(y))")
            }
            else {
                polyline.append(" \(formatCoord(x)),\(formatCoord(y))")
            }
        }

        let firstTime = points[0].time
        let lastTime = points[count - 1].time
        let duration = max(lastTime - firstTime, 0)
        let majorInterval = timeTickInterval(duration: duration)
        // Secondary time scales are 1/10 of the major interval (e.g. 1 ms → 0.1 ms).
        let minorInterval = majorInterval / 10

        var xSubscales = ""
        var xGrid = ""
        var xLabels = ""
        if duration > 0, majorInterval > 0 {
            // Minor ticks first (lines only, no labels).
            let startMinor = (firstTime / minorInterval).rounded(.up) * minorInterval
            var minorTick = startMinor
            var minorGuard = 0
            while minorTick <= lastTime + minorInterval * 1e-9, minorGuard < 100_000 {
                // Skip positions that coincide with a major tick (drawn below with a label).
                if !isMultiple(minorTick, of: majorInterval) {
                    let index = nearestIndex(forTime: minorTick, in: points)
                    let x = xPixel(index)
                    xSubscales.append(
                        """
                        <line class="grid-x-sub" x1="\(formatCoord(x))" y1="\(formatCoord(topMargin))" x2="\(formatCoord(x))" y2="\(formatCoord(topMargin + plotHeight))"/>
                        """,
                    )
                }
                minorTick += minorInterval
                minorGuard += 1
            }

            let startMajor = (firstTime / majorInterval).rounded(.up) * majorInterval
            var majorTick = startMajor
            var majorGuard = 0
            while majorTick <= lastTime + majorInterval * 1e-9, majorGuard < 10_000 {
                let index = nearestIndex(forTime: majorTick, in: points)
                let x = xPixel(index)
                xGrid.append(
                    """
                    <line class="grid-x" x1="\(formatCoord(x))" y1="\(formatCoord(topMargin))" x2="\(formatCoord(x))" y2="\(formatCoord(topMargin + plotHeight))"/>
                    """,
                )
                let label = escapeXML(plotEngineeringFormatter.string(majorTick) + "s")
                xLabels.append(
                    """
                    <text class="label-x" x="\(formatCoord(x))" y="\(formatCoord(topMargin + plotHeight + 20))">\(label)</text>
                    """,
                )
                majorTick += majorInterval
                majorGuard += 1
            }
        }
        else {
            let x = xPixel(0)
            let label = escapeXML(plotEngineeringFormatter.string(firstTime) + "s")
            xLabels.append(
                """
                <text class="label-x" x="\(formatCoord(x))" y="\(formatCoord(topMargin + plotHeight + 20))">\(label)</text>
                """,
            )
        }

        func yMark(value: Double, css: String, label: String) -> String {
            let y = yPixel(value)
            let valueLabel = escapeXML(plotEngineeringFormatter.string(value))
            return """
            <line class="\(css)" x1="\(formatCoord(leftMargin))" y1="\(formatCoord(y))" x2="\(formatCoord(leftMargin +
                    plotWidth))" y2="\(formatCoord(y))"/>
            <text class="label-y" x="\(formatCoord(leftMargin - 10))" y="\(formatCoord(y + 4))">\(valueLabel)</text>
            <text class="label-y-name" x="\(formatCoord(leftMargin - 10))" y="\(formatCoord(y -
                    10))">\(escapeXML(label))</text>
            """
        }

        // Draw mean between max/min so it sits visually in the stack; labels still clear.
        let yMarks =
            yMark(value: maxValue, css: "mark-max", label: "max")
                + yMark(value: meanValue, css: "mark-mean", label: "avg")
                + yMark(value: minValue, css: "mark-min", label: "min")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(formatCoord(
            width,
        ))" height="\(formatCoord(height))" viewBox="0 0 \(formatCoord(width)) \(formatCoord(height))">
          <defs>
            <style>
              .bg { fill: #0b1020; }
              .panel { fill: #121a2f; stroke: #243152; stroke-width: 1; }
              .grid-x { stroke: #1e2a44; stroke-width: 1; stroke-dasharray: 2 4; }
              .grid-x-sub { stroke: #18233a; stroke-width: 1; }
              .mark-max { stroke: #f87171; stroke-width: 1; stroke-dasharray: 4 3; opacity: 0.9; }
              .mark-min { stroke: #60a5fa; stroke-width: 1; stroke-dasharray: 4 3; opacity: 0.9; }
              .mark-mean { stroke: #a3e635; stroke-width: 1; stroke-dasharray: 2 3; opacity: 0.85; }
              .signal { fill: none; stroke: #38bdf8; stroke-width: 1.25; stroke-linejoin: round; stroke-linecap: round; }
              .label-x { fill: #94a3b8; font: 11px ui-sans-serif, system-ui, -apple-system, sans-serif; text-anchor: middle; }
              .label-y { fill: #cbd5e1; font: 11px ui-sans-serif, system-ui, -apple-system, sans-serif; text-anchor: end; }
              .label-y-name { fill: #64748b; font: 10px ui-sans-serif, system-ui, -apple-system, sans-serif; text-anchor: end; }
              .title { fill: #e2e8f0; font: 600 13px ui-sans-serif, system-ui, -apple-system, sans-serif; }
              .subtitle { fill: #94a3b8; font: 12px ui-sans-serif, system-ui, -apple-system, sans-serif; }
            </style>
          </defs>
          <rect class="bg" width="100%" height="100%"/>
          <rect class="panel" x="\(formatCoord(
              leftMargin,
          ))" y="\(formatCoord(topMargin))" width="\(formatCoord(plotWidth))" height="\(formatCoord(plotHeight))" rx="6"/>
          \(xSubscales)
          \(xGrid)
          \(yMarks)
          <polyline class="signal" points="\(polyline)"/>
          \(xLabels)
          \(titleElements(sourceFile: sourceFile, channel: channel, x: leftMargin))
        </svg>
        """
    }

    static func titleText(sourceFile: String, channel: String) -> String {
        let fileName = (sourceFile as NSString).lastPathComponent
        let parts = [fileName, channel]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty {
            return "rigol2spice"
        }
        return "rigol2spice — \(parts.joined(separator: " · "))"
    }

    private static func titleElements(sourceFile: String, channel: String, x: Double) -> String {
        let title = escapeXML(titleText(sourceFile: sourceFile, channel: channel))
        return """
        <text class="title" x="\(formatCoord(x))" y="\(formatCoord(18))">\(title)</text>
        """
    }

    /// Decade-style interval (1, 10, 100, … × 10^n) aiming for a readable number of X ticks.
    static func timeTickInterval(duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else {
            return 1
        }

        // Target roughly 6–12 ticks across the span.
        let rough = duration / 8
        let exponent = floor(log10(rough))
        var interval = pow(10, exponent)

        if duration / interval > 12 {
            interval *= 10
        }
        else if duration / interval < 4, interval / 10 > 0 {
            let finer = interval / 10
            if duration / finer <= 20 {
                interval = finer
            }
        }

        return interval
    }

    /// Minor time grid step: always 1/10 of the major interval (e.g. 1 ms → 0.1 ms).
    static func timeMinorTickInterval(majorInterval: Double) -> Double {
        majorInterval / 10
    }

    /// Whether `value` lies on a multiple of `step` (with relative floating-point tolerance).
    static func isMultiple(_ value: Double, of step: Double) -> Bool {
        guard step > 0, value.isFinite, step.isFinite else {
            return false
        }
        let ratio = value / step
        return abs(ratio - ratio.rounded()) <= 1e-9
    }

    static func nearestIndex(forTime time: Double, in points: [Point]) -> Int {
        guard points.count > 1 else {
            return 0
        }

        var lower = 0
        var upper = points.count - 1
        if time <= points[0].time {
            return 0
        }
        if time >= points[upper].time {
            return upper
        }

        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if points[middle].time < time {
                lower = middle + 1
            }
            else {
                upper = middle
            }
        }

        if lower > 0 {
            let before = lower - 1
            if abs(points[before].time - time) <= abs(points[lower].time - time) {
                return before
            }
        }
        return lower
    }

    private static func emptySVG(sourceFile: String, channel: String) -> String {
        let title = escapeXML(titleText(sourceFile: sourceFile, channel: channel))
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="320" height="120">
          <rect width="100%" height="100%" fill="#0b1020"/>
          <text x="16" y="28" fill="#e2e8f0" font="600 13px ui-sans-serif, system-ui, sans-serif">\(title)</text>
          <text x="16" y="72" fill="#94a3b8" font="14px ui-sans-serif, system-ui, sans-serif">No samples to plot</text>
        </svg>
        """
    }

    private static func formatCoord(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - PlotError

enum PlotError: LocalizedError, Equatable {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Failed to encode SVG plot as UTF-8"
        }
    }
}
