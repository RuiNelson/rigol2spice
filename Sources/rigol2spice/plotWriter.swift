import Foundation
import SwiftEngineeringNumberFormatter

// MARK: - PlotWriter

enum PlotWriter {
    static let largePlotPointThreshold = 10000

    private static let plotHeight: Double = 400
    private static let spectrumHeight: Double = 600
    private static let spectrumGap: Double = 28
    private static let spectrumBottomPad: Double = 36
    private static let leftMargin: Double = 88
    private static let rightMargin: Double = 24
    private static let topMargin: Double = 44
    private static let bottomMargin: Double = 48
    private static let analysisLineHeight: Double = 15
    private static let analysisBlockPadding: Double = 10

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
        analysisReports: [AnalysisReport] = [],
    ) throws -> Int {
        let svg = render(
            points,
            sourceFile: sourceFile,
            channel: channel,
            analysisReports: analysisReports,
        )
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
        analysisReports: [AnalysisReport] = [],
    ) -> String {
        guard !points.isEmpty else {
            return emptySVG(sourceFile: sourceFile, channel: channel)
        }

        let count = points.count
        let plotWidth = Double(max(count, 1))
        let spectra = analysisReports.compactMap(\.fftSpectrum)
        // Title line + one line per report, below the X-axis labels.
        let analysisBlockHeight = analysisReports.isEmpty
            ? 0
            : analysisBlockPadding + analysisLineHeight
            + Double(analysisReports.count) * analysisLineHeight
        let spectraBlockHeight = spectra.isEmpty
            ? 0
            : Double(spectra.count) * (spectrumGap + spectrumHeight + spectrumBottomPad)
        let width = leftMargin + plotWidth + rightMargin
        let analysisOriginY = topMargin + plotHeight + bottomMargin + 4
        let spectraOriginY = analysisOriginY
            + (analysisReports.isEmpty ? 0 : analysisBlockHeight)
            + (spectra.isEmpty ? 0 : 8)
        let height = topMargin + plotHeight + bottomMargin
            + (analysisReports.isEmpty ? 0 : analysisBlockHeight)
            + spectraBlockHeight
            + (spectra.isEmpty || analysisReports.isEmpty ? 0 : 8)

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
                        <line class="grid-x-sub" x1="\(formatCoord(
                            x,
                        ))" y1="\(formatCoord(topMargin))" x2="\(formatCoord(x))" y2="\(formatCoord(topMargin +
                                plotHeight))"/>
                        """,
                    )
                }
                minorTick += minorInterval
                minorGuard += 1
            }

            let startMajor = (firstTime / majorInterval).rounded(.up) * majorInterval
            var majorTick = startMajor
            var majorGuard = 0
            while majorTick <= lastTime + majorInterval * 1e-9, majorGuard < 10000 {
                let index = nearestIndex(forTime: majorTick, in: points)
                let x = xPixel(index)
                xGrid.append(
                    """
                    <line class="grid-x" x1="\(formatCoord(
                        x,
                    ))" y1="\(formatCoord(topMargin))" x2="\(formatCoord(x))" y2="\(formatCoord(topMargin +
                            plotHeight))"/>
                    """,
                )
                let label = escapeXML(plotEngineeringFormatter.string(majorTick) + "s")
                xLabels.append(
                    """
                    <text class="label-x" x="\(formatCoord(x))" y="\(formatCoord(topMargin + plotHeight +
                            20))">\(label)</text>
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
                <text class="label-x" x="\(formatCoord(x))" y="\(formatCoord(topMargin + plotHeight +
                        20))">\(label)</text>
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

        let analysisText = analysisTextElements(
            reports: analysisReports,
            x: leftMargin,
            y: analysisOriginY,
        )
        let spectrumPanels = spectrumPanelElements(
            spectra: spectra,
            plotWidth: plotWidth,
            originY: spectraOriginY,
        )

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
              .grid-spectrum { stroke: #263555; stroke-width: 1; stroke-dasharray: 2 4; }
              .grid-spectrum-sub { stroke: #1a2740; stroke-width: 1; }
              .mark-max { stroke: #f87171; stroke-width: 1; stroke-dasharray: 4 3; opacity: 0.9; }
              .mark-min { stroke: #60a5fa; stroke-width: 1; stroke-dasharray: 4 3; opacity: 0.9; }
              .mark-mean { stroke: #a3e635; stroke-width: 1; stroke-dasharray: 2 3; opacity: 0.85; }
              .mark-peak { stroke: #fbbf24; stroke-width: 1; stroke-dasharray: 3 3; opacity: 0.85; }
              .signal { fill: none; stroke: #38bdf8; stroke-width: 1.25; stroke-linejoin: round; stroke-linecap: round; }
              .spectrum { fill: none; stroke: #c084fc; stroke-width: 1.25; stroke-linejoin: round; stroke-linecap: round; }
              .label-x { fill: #94a3b8; font: 11px ui-sans-serif, system-ui, -apple-system, sans-serif; text-anchor: middle; }
              .label-x-end { text-anchor: end; }
              .label-y { fill: #cbd5e1; font: 11px ui-sans-serif, system-ui, -apple-system, sans-serif; text-anchor: end; }
              .label-y-name { fill: #64748b; font: 10px ui-sans-serif, system-ui, -apple-system, sans-serif; text-anchor: end; }
              .title { fill: #e2e8f0; font: 600 13px ui-sans-serif, system-ui, -apple-system, sans-serif; }
              .subtitle { fill: #94a3b8; font: 12px ui-sans-serif, system-ui, -apple-system, sans-serif; }
              .analysis-title { fill: #cbd5e1; font: 600 11px ui-sans-serif, system-ui, -apple-system, sans-serif; }
              .analysis-line { fill: #e2e8f0; font: 11px ui-monospace, SFMono-Regular, Menlo, monospace; }
              .spectrum-title { fill: #cbd5e1; font: 600 11px ui-sans-serif, system-ui, -apple-system, sans-serif; }
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
          \(analysisText)
          \(spectrumPanels)
        </svg>
        """
    }

    private static func spectrumPanelElements(
        spectra: [FFTSpectrum],
        plotWidth: Double,
        originY: Double,
    ) -> String {
        guard !spectra.isEmpty else {
            return ""
        }

        var elements = ""
        for (index, spectrum) in spectra.enumerated() {
            let panelTop = originY + Double(index) * (spectrumGap + spectrumHeight + spectrumBottomPad)
            elements.append(renderSpectrumPanel(
                spectrum: spectrum,
                plotWidth: plotWidth,
                panelTop: panelTop,
            ))
        }
        return elements
    }

    private static func renderSpectrumPanel(
        spectrum: FFTSpectrum,
        plotWidth: Double,
        panelTop: Double,
    ) -> String {
        let titleY = panelTop + 12
        let chartTop = panelTop + spectrumGap
        let binCount = spectrum.frequencies.count
        guard binCount >= 2 else {
            return """
            <text class="spectrum-title" x="\(formatCoord(
                leftMargin,
            ))" y="\(formatCoord(titleY))">\(escapeXML("FFT \(spectrum.requestedPointCount) — unavailable"))</text>
            """
        }

        let fMax = spectrum.frequencies[binCount - 1]
        let dbBounds = spectrumDBBounds(spectrum.magnitudesDB)
        let dbMin = dbBounds.min
        let dbMax = dbBounds.max
        let dbRange = dbMax - dbMin

        func xAtFrequency(_ frequency: Double) -> Double {
            guard fMax > 0 else {
                return leftMargin
            }
            return leftMargin + (frequency / fMax) * plotWidth
        }

        func yAtDB(_ db: Double) -> Double {
            chartTop + (dbMax - db) / dbRange * spectrumHeight
        }

        var polyline = ""
        polyline.reserveCapacity(binCount * 14)
        for index in 0 ..< binCount {
            let x = xAtFrequency(spectrum.frequencies[index])
            let y = yAtDB(spectrum.magnitudesDB[index])
            if index == 0 {
                polyline.append("\(formatCoord(x)),\(formatCoord(y))")
            }
            else {
                polyline.append(" \(formatCoord(x)),\(formatCoord(y))")
            }
        }

        // Rounded 1-2-5 frequency divisions, with one subtle subdivision between
        // labels. This stays readable while giving more useful positions than equal
        // fractions of an arbitrary Nyquist frequency.
        var xGrid = ""
        let frequencyInterval = spectrumTickInterval(span: fMax)
        let frequencyMinorInterval = frequencyInterval / 2
        if frequencyMinorInterval > 0 {
            var frequency = frequencyMinorInterval
            while frequency < fMax {
                if !isMultiple(frequency, of: frequencyInterval) {
                    let x = xAtFrequency(frequency)
                    xGrid.append(
                        """
                        <line class="grid-spectrum-sub" x1="\(formatCoord(x))" y1="\(formatCoord(
                            chartTop,
                        ))" x2="\(formatCoord(x))" y2="\(formatCoord(chartTop + spectrumHeight))"/>
                        """,
                    )
                }
                frequency += frequencyMinorInterval
            }
        }

        var frequency = 0.0
        while frequency <= fMax + frequencyInterval * 1e-9 {
            let x = xAtFrequency(frequency)
            let label = escapeXML(plotEngineeringFormatter.string(frequency) + "Hz")
            let labelClass = abs(frequency - fMax) <= frequencyInterval * 1e-9
                ? "label-x label-x-end"
                : "label-x"
            xGrid.append(
                """
                <line class="grid-spectrum" x1="\(formatCoord(
                    x,
                ))" y1="\(formatCoord(chartTop))" x2="\(formatCoord(x))" y2="\(formatCoord(chartTop +
                        spectrumHeight))"/>
                <text class="\(labelClass)" x="\(formatCoord(x))" y="\(formatCoord(chartTop + spectrumHeight +
                        18))">\(label)</text>
                """,
            )
            frequency += frequencyInterval
        }

        // Rounded dB divisions across a useful dynamic range.
        var yGrid = ""
        let dbInterval = spectrumTickInterval(span: dbRange)
        var dbTick = (dbMin / dbInterval).rounded(.up) * dbInterval
        while dbTick <= dbMax + dbInterval * 1e-9 {
            let y = yAtDB(dbTick)
            let label = escapeXML(plotEngineeringFormatter.string(dbTick) + "dB")
            yGrid.append(
                """
                <line class="grid-spectrum" x1="\(formatCoord(leftMargin))" y1="\(formatCoord(
                    y,
                ))" x2="\(formatCoord(leftMargin + plotWidth))" y2="\(formatCoord(y))"/>
                <text class="label-y" x="\(formatCoord(leftMargin - 10))" y="\(formatCoord(y + 4))">\(label)</text>
                """,
            )
            dbTick += dbInterval
        }

        let peakX = xAtFrequency(spectrum.centerFrequency)
        let peakY = yAtDB(min(max(spectrum.centerMagnitudeDB, dbMin), dbMax))
        let resolution = spectrum.sampleRate / Double(spectrum.fftSize)
        let title: String = if spectrum.usedPointCount < spectrum.requestedPointCount {
            escapeXML(
                "FFT \(spectrum.usedPointCount) pts · \(spectrum.windowPosition.rawValue) window (requested \(spectrum.requestedPointCount)) · Δf \(plotEngineeringFormatter.string(resolution))Hz · peak \(plotEngineeringFormatter.string(spectrum.centerFrequency))Hz · \(plotEngineeringFormatter.string(spectrum.centerMagnitudeDB))dB",
            )
        }
        else {
            escapeXML(
                "FFT \(spectrum.usedPointCount) pts · \(spectrum.windowPosition.rawValue) window · Δf \(plotEngineeringFormatter.string(resolution))Hz · peak \(plotEngineeringFormatter.string(spectrum.centerFrequency))Hz · \(plotEngineeringFormatter.string(spectrum.centerMagnitudeDB))dB",
            )
        }

        return """
        <text class="spectrum-title" x="\(formatCoord(leftMargin))" y="\(formatCoord(titleY))">\(title)</text>
        <rect class="panel" x="\(formatCoord(
            leftMargin,
        ))" y="\(formatCoord(
            chartTop,
        ))" width="\(formatCoord(plotWidth))" height="\(formatCoord(spectrumHeight))" rx="6"/>
        \(xGrid)
        \(yGrid)
        <line class="mark-peak" x1="\(formatCoord(
            peakX,
        ))" y1="\(formatCoord(chartTop))" x2="\(formatCoord(peakX))" y2="\(formatCoord(chartTop +
                spectrumHeight))"/>
        <polyline class="spectrum" points="\(polyline)"/>
        <circle cx="\(formatCoord(peakX))" cy="\(formatCoord(peakY))" r="3" fill="#fbbf24"/>
        """
    }

    /// A conventional 1-2-5 interval targeting about six labelled divisions.
    static func spectrumTickInterval(span: Double, targetTickCount: Int = 6) -> Double {
        guard span.isFinite, span > 0, targetTickCount > 0 else {
            return 1
        }
        let rough = span / Double(targetTickCount)
        let magnitude = pow(10, floor(log10(rough)))
        let normalized = rough / magnitude
        let factor: Double = if normalized <= 1 {
            1
        }
        else if normalized <= 2 {
            2
        }
        else if normalized <= 5 {
            5
        }
        else {
            10
        }
        return factor * magnitude
    }

    /// Rounded dB limits with enough headroom for the peak and at most 120 dB of
    /// displayed range, avoiding a numerical FFT floor flattening the useful trace.
    static func spectrumDBBounds(
        _ values: [Double],
        maximumDynamicRange: Double = 120,
    ) -> (min: Double, max: Double) {
        let finiteValues = values.filter(\.isFinite)
        guard let rawMin = finiteValues.min(), let rawMax = finiteValues.max() else {
            return (-120, 0)
        }

        var visibleMin = max(rawMin, rawMax - maximumDynamicRange)
        var visibleMax = rawMax
        if visibleMax - visibleMin < 10 {
            visibleMin -= 5
            visibleMax += 5
        }
        let interval = spectrumTickInterval(span: visibleMax - visibleMin)
        let roundedMax = (visibleMax / interval).rounded(.up) * interval
        var roundedMin = (visibleMin / interval).rounded(.down) * interval
        if maximumDynamicRange > 0 {
            roundedMin = max(roundedMin, roundedMax - maximumDynamicRange)
        }
        if roundedMin >= roundedMax {
            roundedMin = roundedMax - max(interval, 10)
        }
        return (roundedMin, roundedMax)
    }

    private static func analysisTextElements(
        reports: [AnalysisReport],
        x: Double,
        y: Double,
    ) -> String {
        guard !reports.isEmpty else {
            return ""
        }

        var elements = """
        <text class="analysis-title" x="\(formatCoord(x))" y="\(formatCoord(y + analysisLineHeight -
                2))">Analysis</text>
        """
        for (index, report) in reports.enumerated() {
            let lineY = y + analysisLineHeight + Double(index + 1) * analysisLineHeight - 2
            elements.append(
                """
                <text class="analysis-line" x="\(formatCoord(x))" y="\(formatCoord(lineY))">\(escapeXML(report
                        .displayLine))</text>
                """,
            )
        }
        return elements
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
