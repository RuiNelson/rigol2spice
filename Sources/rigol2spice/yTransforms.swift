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

/// Sample from the standard normal distribution N(0, 1) via Box–Muller.
func unitGaussianSample() -> Double {
    let u1 = Double.random(in: Double.leastNonzeroMagnitude ... 1)
    let u2 = Double.random(in: 0 ..< 1)
    return sqrt(-2 * log(u1)) * cos(2 * Double.pi * u2)
}

/// Add zero-mean Gaussian noise with standard deviation `amplitude` to every sample.
func addNoisePoints(_ points: [Point], amplitude: Double) -> [Point] {
    guard amplitude != 0, !points.isEmpty else {
        return points
    }

    var output = points
    output.withUnsafeMutableBufferPointer { buffer in
        for index in buffer.indices {
            buffer[index].value += amplitude * unitGaussianSample()
        }
    }
    return output
}

/// Default fraction of peak-to-peak used when `RemoveNoise` has no explicit threshold.
let removeNoiseAutoThresholdFraction = 0.05

/// Clean digital-ish captures: median-3, deadband hold, then plateau re-mean.
///
/// - Parameter threshold: Maximum step treated as plateau chatter. When `nil`, uses
///   5% of the capture's peak-to-peak after the median stage. `0` skips hold + re-mean.
///
/// 1. **Median 3** — remove single-sample spikes.
/// 2. **Deadband hold** — if `|sample − held| < T`, keep the held level; otherwise accept
///    the sample as the new level. Large edges jump cleanly; fine slews become steps of ~T.
/// 3. **Re-mean** — each constant held run is replaced by the mean of the post-median
///    samples in that run, so plateaus settle to the true rail instead of the first sample.
func removeNoisePoints(_ points: [Point], threshold: Double?) -> [Point] {
    guard points.count >= 2 else {
        return points
    }

    // Stage 1: kill single-sample spikes without a full low-pass smear.
    let source = medianPoints(points, window: 3)

    let holdThreshold: Double
    if let threshold {
        holdThreshold = threshold
    }
    else {
        holdThreshold = removeNoiseAutoThresholdFraction * peakToPeakValue(source)
    }

    guard holdThreshold > 0 else {
        return source
    }

    // Stage 2: deadband hold against the previous *held* level (not the raw neighbour).
    var held = source
    for index in 1 ..< source.count {
        if abs(source[index].value - held[index - 1].value) < holdThreshold {
            held[index].value = held[index - 1].value
        }
        else {
            held[index].value = source[index].value
        }
    }

    // Stage 3: each constant run → mean of the post-median samples in that run.
    var output = held
    var runStart = 0
    while runStart < output.count {
        let level = held[runStart].value
        var runEnd = runStart + 1
        while runEnd < held.count, held[runEnd].value == level {
            runEnd += 1
        }

        var sum = 0.0
        for index in runStart ..< runEnd {
            sum += source[index].value
        }
        let mean = sum / Double(runEnd - runStart)
        for index in runStart ..< runEnd {
            output[index].value = mean
        }
        runStart = runEnd
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

/// Quantize to `bits` levels spanning [lower, upper] (mid-tread / round-to-nearest).
func quantizePoints(_ points: [Point], bits: Int, lower: Double, upper: Double) -> [Point] {
    guard bits >= 1, upper > lower else {
        return points
    }

    let levels = (1 << bits) - 1 // 2^bits - 1 steps between endpoints
    let span = upper - lower
    var output = points
    output.withUnsafeMutableBufferPointer { buffer in
        for index in buffer.indices {
            let clamped = min(max(buffer[index].value, lower), upper)
            let code = ((clamped - lower) / span * Double(levels)).rounded()
            let limitedCode = min(max(code, 0), Double(levels))
            buffer[index].value = lower + limitedCode * span / Double(levels)
        }
    }
    return output
}

/// Linear amplitude fade at the start and/or end of the capture.
func fadePoints(
    _ points: [Point],
    fadeIn: Double,
    fadeOut: Double,
) -> [Point] {
    guard !points.isEmpty else {
        return points
    }

    let start = points[0].time
    let end = points[points.count - 1].time
    var output = points
    output.withUnsafeMutableBufferPointer { buffer in
        for index in buffer.indices {
            var gain = 1.0
            if fadeIn > 0 {
                let elapsed = buffer[index].time - start
                if elapsed < fadeIn {
                    gain = min(gain, max(0, elapsed / fadeIn))
                }
            }
            if fadeOut > 0 {
                let remaining = end - buffer[index].time
                if remaining < fadeOut {
                    gain = min(gain, max(0, remaining / fadeOut))
                }
            }
            buffer[index].value *= gain
        }
    }
    return output
}

/// Soft clip into [lower, upper] using a scaled tanh.
/// At the bounds the slope is gentle; the asymptotic limits are lower/upper.
func softClipPoints(_ points: [Point], lower: Double, upper: Double) -> [Point] {
    let center = 0.5 * (lower + upper)
    let half = 0.5 * (upper - lower)
    guard half > 0 else {
        return points
    }

    var output = points
    output.withUnsafeMutableBufferPointer { buffer in
        for index in buffer.indices {
            let normalized = (buffer[index].value - center) / half
            buffer[index].value = center + half * tanh(normalized)
        }
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
///
/// - Hard threshold (`fall == rise`): each sample is independently
///   `highOut` if ≥ threshold, else `lowOut`.
/// - Schmitt (`fall != rise`): go high when sample ≥ max(fall, rise),
///   go low when sample ≤ min(fall, rise); keep the previous level while
///   between the two thresholds. The first sample seeds the state.
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

    let lo = min(lowThreshold, highThreshold)
    let hi = max(lowThreshold, highThreshold)

    // Hard threshold: independent compare per sample (no hysteresis band).
    if lo == hi {
        var output = points
        output.withUnsafeMutableBufferPointer { buffer in
            for index in buffer.indices {
                buffer[index].value = buffer[index].value >= hi ? highOut : lowOut
            }
        }
        return output
    }

    // Schmitt trigger with hysteresis between lo and hi.
    var output = points
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
