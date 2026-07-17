import Foundation

func multiplyValueOfPoints(_ points: [Point], factor: Double) -> [Point] {
    guard factor != 1 else {
        return points
    }

    var output = points
    output.withUnsafeMutableBufferPointer { buffer in
        for index in buffer.indices {
            buffer[index].value *= factor
        }
    }
    return output
}

func offsetPoints(_ points: [Point], offset: Double) -> [Point] {
    guard offset != 0 else {
        return points
    }

    var output = points
    output.withUnsafeMutableBufferPointer { buffer in
        for index in buffer.indices {
            buffer[index].value += offset
        }
    }
    return output
}

func clamp(_ points: [Point], lowerLimit: Double?, upperLimit: Double?) -> [Point] {
    guard lowerLimit != nil || upperLimit != nil else {
        return points
    }

    var output = points
    output.withUnsafeMutableBufferPointer { buffer in
        switch (lowerLimit, upperLimit) {
        case let (lowerLimit?, upperLimit?):
            for index in buffer.indices {
                let originalValue = buffer[index].value
                if originalValue < lowerLimit {
                    buffer[index].value = lowerLimit
                }
                if originalValue > upperLimit {
                    buffer[index].value = upperLimit
                }
            }
        case let (lowerLimit?, nil):
            for index in buffer.indices where buffer[index].value < lowerLimit {
                buffer[index].value = lowerLimit
            }
        case let (nil, upperLimit?):
            for index in buffer.indices where buffer[index].value > upperLimit {
                buffer[index].value = upperLimit
            }
        case (nil, nil):
            break
        }
    }
    return output
}

/// Zero values strictly below the threshold; keep values at or above it.
func gatePoints(_ points: [Point], threshold: Double) -> [Point] {
    var output = points
    output.withUnsafeMutableBufferPointer { buffer in
        for index in buffer.indices where buffer[index].value < threshold {
            buffer[index].value = 0
        }
    }
    return output
}

func absPoints(_ points: [Point]) -> [Point] {
    var output = points
    output.withUnsafeMutableBufferPointer { buffer in
        for index in buffer.indices {
            buffer[index].value = abs(buffer[index].value)
        }
    }
    return output
}

/// Half-wave rectify: keep non-negative values, zero the rest.
func rectifyPoints(_ points: [Point]) -> [Point] {
    var output = points
    output.withUnsafeMutableBufferPointer { buffer in
        for index in buffer.indices where buffer[index].value < 0 {
            buffer[index].value = 0
        }
    }
    return output
}

func peakAbsoluteValue(_ points: [Point]) -> Double {
    var peak = 0.0
    for point in points {
        let magnitude = abs(point.value)
        if magnitude > peak {
            peak = magnitude
        }
    }
    return peak
}

/// Scale so the peak absolute value equals `target`. Unchanged if the peak is zero.
func scalePeakTo(_ points: [Point], target: Double) -> [Point] {
    let peak = peakAbsoluteValue(points)
    guard peak > 0 else {
        return points
    }
    return multiplyValueOfPoints(points, factor: target / peak)
}

func peakToPeakValue(_ points: [Point]) -> Double {
    guard let first = points.first else {
        return 0
    }
    var minimum = first.value
    var maximum = first.value
    for point in points.dropFirst() {
        minimum = min(minimum, point.value)
        maximum = max(maximum, point.value)
    }
    return maximum - minimum
}

/// Scale so max − min equals `target`. Unchanged if the span is zero.
func scalePeakToPeak(_ points: [Point], target: Double) -> [Point] {
    let span = peakToPeakValue(points)
    guard span > 0 else {
        return points
    }
    return multiplyValueOfPoints(points, factor: target / span)
}

func rmsValue(_ points: [Point]) -> Double {
    guard !points.isEmpty else {
        return 0
    }
    var sumSquares = 0.0
    for point in points {
        sumSquares += point.value * point.value
    }
    return sqrt(sumSquares / Double(points.count))
}

/// Scale so the sample RMS equals `target`. Unchanged if RMS is zero.
func scalePointsToRMS(_ points: [Point], target: Double) -> [Point] {
    let rms = rmsValue(points)
    guard rms > 0 else {
        return points
    }
    return multiplyValueOfPoints(points, factor: target / rms)
}

/// Centered median filter over `window` samples (window ≥ 1). Edges use a shorter window.
func medianPoints(_ points: [Point], window: Int) -> [Point] {
    guard window > 1, points.count > 1 else {
        return points
    }

    let count = points.count
    let half = window / 2
    var output = points
    var scratch = [Double]()
    scratch.reserveCapacity(window)

    for index in 0 ..< count {
        let lower = max(0, index - half)
        let upper = min(count - 1, index - half + window - 1)
        scratch.removeAll(keepingCapacity: true)
        for sampleIndex in lower ... upper {
            scratch.append(points[sampleIndex].value)
        }
        scratch.sort()
        let sampleCount = scratch.count
        if sampleCount % 2 == 1 {
            output[index].value = scratch[sampleCount / 2]
        }
        else {
            output[index].value = 0.5 * (scratch[sampleCount / 2 - 1] + scratch[sampleCount / 2])
        }
    }
    return output
}

/// Centered moving average over `window` samples (window ≥ 1). Edges use a shorter window.
func movingAveragePoints(_ points: [Point], window: Int) -> [Point] {
    guard window > 1, points.count > 1 else {
        return points
    }

    let count = points.count
    let half = window / 2
    var output = points
    output.withUnsafeMutableBufferPointer { buffer in
        var prefix = [Double](repeating: 0, count: count + 1)
        for index in 0 ..< count {
            prefix[index + 1] = prefix[index] + buffer[index].value
        }

        for index in 0 ..< count {
            let lower = max(0, index - half)
            let upper = min(count - 1, index - half + window - 1)
            let sampleCount = upper - lower + 1
            buffer[index].value = (prefix[upper + 1] - prefix[lower]) / Double(sampleCount)
        }
    }
    return output
}

/// Numerical derivative dv/dt (central difference interior; one-sided at the ends).
func differentiatePoints(_ points: [Point]) -> [Point] {
    guard points.count >= 2 else {
        return points.map { Point(time: $0.time, value: 0) }
    }

    var output = points
    let last = points.count - 1

    let firstDt = points[1].time - points[0].time
    output[0].value = firstDt != 0
        ? (points[1].value - points[0].value) / firstDt
        : 0

    if points.count > 2 {
        for index in 1 ..< last {
            let dt = points[index + 1].time - points[index - 1].time
            output[index].value = dt != 0
                ? (points[index + 1].value - points[index - 1].value) / dt
                : 0
        }
    }

    let lastDt = points[last].time - points[last - 1].time
    output[last].value = lastDt != 0
        ? (points[last].value - points[last - 1].value) / lastDt
        : 0

    return output
}

/// Cumulative trapezoidal integral starting at 0.
func integratePoints(_ points: [Point]) -> [Point] {
    guard !points.isEmpty else {
        return points
    }

    var output = points
    output[0].value = 0

    guard points.count > 1 else {
        return output
    }

    var cumulative = 0.0
    for index in 1 ..< points.count {
        let dt = points[index].time - points[index - 1].time
        cumulative += 0.5 * (points[index].value + points[index - 1].value) * dt
        output[index].value = cumulative
    }
    return output
}

/// Limit |dv/dt| to `maxSlew` (V/s). Walks forward from the first sample.
func slewLimitPoints(_ points: [Point], maxSlew: Double) -> [Point] {
    guard points.count >= 2, maxSlew > 0 else {
        return points
    }

    var output = points
    for index in 1 ..< output.count {
        let dt = output[index].time - output[index - 1].time
        guard dt > 0 else {
            output[index].value = output[index - 1].value
            continue
        }
        let maxDelta = maxSlew * dt
        let previous = output[index - 1].value
        let target = output[index].value
        let delta = target - previous
        if delta > maxDelta {
            output[index].value = previous + maxDelta
        }
        else if delta < -maxDelta {
            output[index].value = previous - maxDelta
        }
    }
    return output
}

/// Convert an analog waveform to two-level digital output.
/// - Without hysteresis (`highThreshold == lowThreshold`): each sample is
///   `highOut` if ≥ threshold, else `lowOut`.
/// - With hysteresis: rising needs `highThreshold`, falling needs `lowThreshold`.
func digitizePoints(
    _ points: [Point],
    lowThreshold: Double,
    highThreshold: Double,
    lowOut: Double,
    highOut: Double,
) -> [Point] {
    guard !points.isEmpty else {
        return points
    }

    var output = points
    let lo = min(lowThreshold, highThreshold)
    let hi = max(lowThreshold, highThreshold)

    output.withUnsafeMutableBufferPointer { buffer in
        var isHigh = buffer[0].value >= hi
        buffer[0].value = isHigh ? highOut : lowOut

        for index in 1 ..< buffer.count {
            let sample = buffer[index].value
            if isHigh {
                if sample <= lo {
                    isHigh = false
                }
            }
            else if sample >= hi {
                isHigh = true
            }
            buffer[index].value = isHigh ? highOut : lowOut
        }
    }
    return output
}

/// Zero values with absolute magnitude strictly below `threshold`.
func deadZonePoints(_ points: [Point], threshold: Double) -> [Point] {
    let magnitude = abs(threshold)
    var output = points
    output.withUnsafeMutableBufferPointer { buffer in
        for index in buffer.indices where abs(buffer[index].value) < magnitude {
            buffer[index].value = 0
        }
    }
    return output
}

/// Default impedance when converting absolute power levels (dBmW / dBW) to volts.
let powerReferenceResistance = 50.0

/// Voltage corresponding to an absolute power level into the given resistance.
/// - Parameter powerWatts: Power in watts (must be ≥ 0).
func voltageForPower(_ powerWatts: Double, resistance: Double = powerReferenceResistance) -> Double {
    sqrt(max(powerWatts, 0) * resistance)
}

/// dBmW (dB relative to 1 mW) → volts into `resistance`.
func voltageFromDBmW(_ dbmW: Double, resistance: Double = powerReferenceResistance) -> Double {
    voltageForPower(1e-3 * pow(10, dbmW / 10), resistance: resistance)
}

/// dBW (dB relative to 1 W) → volts into `resistance`.
func voltageFromDBW(_ dbW: Double, resistance: Double = powerReferenceResistance) -> Double {
    voltageForPower(pow(10, dbW / 10), resistance: resistance)
}
