import Foundation

// MARK: - Capture geometry

/// Span of the capture timeline (`t_last − t_first`), or 0 when fewer than two points.
func captureDuration(_ points: [Point]) -> Double {
    guard let first = points.first, let last = points.last, points.count >= 2 else {
        return 0
    }
    let duration = last.time - first.time
    return duration.isFinite ? max(duration, 0) : 0
}

/// Uniform sample rate estimate `(N−1) / duration`, or `nil` when undefined.
func captureSampleRate(_ points: [Point]) -> Double? {
    guard points.count >= 2 else {
        return nil
    }
    let duration = captureDuration(points)
    guard duration > 0 else {
        return nil
    }
    let rate = Double(points.count - 1) / duration
    return rate.isFinite && rate > 0 ? rate : nil
}

/// Mean sample interval `duration / (N−1)`, or `nil` when undefined.
func captureSampleInterval(_ points: [Point]) -> Double? {
    guard let rate = captureSampleRate(points), rate > 0 else {
        return nil
    }
    return 1 / rate
}

// MARK: - Amplitude statistics

/// Peak absolute sample value (same helper as `PeakTo`).
func peakValue(_ points: [Point]) -> Double {
    peakAbsoluteValue(points)
}

/// Half of peak-to-peak (`PkPk / 2`).
func amplitudeValue(_ points: [Point]) -> Double {
    peakToPeakValue(points) / 2
}

/// Midpoint of min/max: `(max + min) / 2`. Empty → 0.
func midValue(_ points: [Point]) -> Double {
    guard let range = valueRange(points) else {
        return 0
    }
    return 0.5 * (range.minimum + range.maximum)
}

/// AC RMS: RMS of the zero-mean signal, `√max(0, RMS² − Avg²)`.
func acRmsValue(_ points: [Point]) -> Double {
    guard !points.isEmpty else {
        return 0
    }
    let mean = averageValue(points)
    let rms = rmsValue(points)
    let acSquared = rms * rms - mean * mean
    return acSquared > 0 ? sqrt(acSquared) : 0
}

/// Population standard deviation (identical to AC RMS for these samples).
func standardDeviationValue(_ points: [Point]) -> Double {
    acRmsValue(points)
}

/// Crest factor: peak absolute / RMS. `nil` when RMS is 0.
func crestFactorValue(_ points: [Point]) -> Double? {
    let rms = rmsValue(points)
    guard rms > 0 else {
        return nil
    }
    return peakAbsoluteValue(points) / rms
}

/// Median of sample values. Empty → 0.
func medianValue(_ points: [Point]) -> Double {
    guard !points.isEmpty else {
        return 0
    }
    let sorted = points.map(\.value).sorted()
    let count = sorted.count
    if count % 2 == 1 {
        return sorted[count / 2]
    }
    return 0.5 * (sorted[count / 2 - 1] + sorted[count / 2])
}

// MARK: - Top / Base (histogram modes)

/// Oscilloscope-style Top and Base from a value histogram (modes of upper/lower halves).
/// Flat captures return the constant level for both. Empty → `nil`.
func topBaseLevels(_ points: [Point], binCount: Int = 256) -> (base: Double, top: Double)? {
    guard let range = valueRange(points) else {
        return nil
    }
    if range.maximum <= range.minimum {
        return (range.minimum, range.maximum)
    }

    let bins = max(binCount, 4)
    var counts = [Int](repeating: 0, count: bins)
    let span = range.maximum - range.minimum
    for point in points {
        var bin = Int(((point.value - range.minimum) / span) * Double(bins))
        if bin >= bins {
            bin = bins - 1
        }
        if bin < 0 {
            bin = 0
        }
        counts[bin] += 1
    }

    let mid = bins / 2
    var baseBin = 0
    var topBin = bins - 1
    var baseCount = -1
    var topCount = -1
    for bin in 0 ..< mid {
        if counts[bin] > baseCount {
            baseCount = counts[bin]
            baseBin = bin
        }
    }
    for bin in mid ..< bins {
        if counts[bin] > topCount {
            topCount = counts[bin]
            topBin = bin
        }
    }

    let base = range.minimum + (Double(baseBin) + 0.5) / Double(bins) * span
    let top = range.minimum + (Double(topBin) + 0.5) / Double(bins) * span
    return (min(base, top), max(base, top))
}

/// Overshoot relative to Top/Base: `(max − Top) / (Top − Base)`. `nil` if span is 0.
func overshootRatio(_ points: [Point]) -> Double? {
    guard let levels = topBaseLevels(points),
          let range = valueRange(points) else {
        return nil
    }
    let amplitude = levels.top - levels.base
    guard amplitude > 0 else {
        return nil
    }
    return (range.maximum - levels.top) / amplitude
}

/// Undershoot relative to Top/Base: `(Base − min) / (Top − Base)`. `nil` if span is 0.
func undershootRatio(_ points: [Point]) -> Double? {
    guard let levels = topBaseLevels(points),
          let range = valueRange(points) else {
        return nil
    }
    let amplitude = levels.top - levels.base
    guard amplitude > 0 else {
        return nil
    }
    return (levels.base - range.minimum) / amplitude
}

// MARK: - Integrals & power

/// Trapezoidal integral ∫v dt over the capture (final cumulative value).
func integralValue(_ points: [Point]) -> Double {
    guard points.count >= 2 else {
        return 0
    }
    return integratePoints(points).last?.value ?? 0
}

/// Trapezoidal “energy” proxy ∫v² dt (1 Ω).
func energyValue(_ points: [Point]) -> Double {
    guard points.count >= 2 else {
        return 0
    }
    var sum = 0.0
    for index in 1 ..< points.count {
        let dt = points[index].time - points[index - 1].time
        guard dt.isFinite, dt > 0 else {
            continue
        }
        let v0 = points[index - 1].value
        let v1 = points[index].value
        sum += 0.5 * (v0 * v0 + v1 * v1) * dt
    }
    return sum
}

/// Power in dBm from sample RMS into `resistance` ohms: `10·log₁₀(Vrms²/R / 1mW)`.
func dbmFromRMS(_ points: [Point], resistance: Double = powerReferenceResistance) -> Double? {
    guard resistance > 0, resistance.isFinite else {
        return nil
    }
    let rms = rmsValue(points)
    guard rms > 0 else {
        return nil
    }
    let powerWatts = (rms * rms) / resistance
    let dbm = 10 * log10(powerWatts / 1e-3)
    return dbm.isFinite ? dbm : nil
}

// MARK: - DirectedCrossing

struct DirectedCrossing: Equatable {
    let time: Double
    let rising: Bool
}

/// Level crossings of `threshold` with direction (linearly interpolated).
func directedLevelCrossings(_ points: [Point], threshold: Double) -> [DirectedCrossing] {
    guard points.count >= 2 else {
        return []
    }

    var crossings: [DirectedCrossing] = []
    for index in 1 ..< points.count {
        let previous = points[index - 1]
        let current = points[index]
        let crossedUp = previous.value < threshold && current.value >= threshold
        let crossedDown = previous.value > threshold && current.value <= threshold
        guard crossedUp || crossedDown else {
            continue
        }
        let time = interpolatedCrossingTime(
            previous: previous,
            current: current,
            threshold: threshold,
        )
        crossings.append(DirectedCrossing(time: time, rising: crossedUp))
    }
    return crossings
}

/// First crossing at `level` with the requested direction, optionally after `after`.
func firstDirectedCrossing(
    _ points: [Point],
    level: Double,
    rising: Bool,
    after: Double? = nil,
) -> Double? {
    for crossing in directedLevelCrossings(points, threshold: level) where crossing.rising == rising {
        if let after, crossing.time <= after {
            continue
        }
        return crossing.time
    }
    return nil
}

/// Rise or fall time between percentage levels of the min/max span (e.g. 10 → 90).
/// Percentages are of PkPk above min. Returns `nil` when the edge cannot be found.
func transitionTime(
    _ points: [Point],
    lowPercent: Double,
    highPercent: Double,
    rising: Bool,
) -> Double? {
    guard let range = valueRange(points) else {
        return nil
    }
    let span = range.maximum - range.minimum
    guard span > 0 else {
        return nil
    }

    let lowP = min(lowPercent, highPercent)
    let highP = max(lowPercent, highPercent)
    guard lowP >= 0, highP <= 100, highP > lowP else {
        return nil
    }

    let lowLevel = range.minimum + span * lowP / 100
    let highLevel = range.minimum + span * highP / 100

    if rising {
        guard let tLow = firstDirectedCrossing(points, level: lowLevel, rising: true),
              let tHigh = firstDirectedCrossing(points, level: highLevel, rising: true, after: tLow) else {
            return nil
        }
        let dt = tHigh - tLow
        return dt.isFinite && dt >= 0 ? dt : nil
    }

    guard let tHigh = firstDirectedCrossing(points, level: highLevel, rising: false),
          let tLow = firstDirectedCrossing(points, level: lowLevel, rising: false, after: tHigh) else {
        return nil
    }
    let dt = tLow - tHigh
    return dt.isFinite && dt >= 0 ? dt : nil
}

/// Complete-wave periods from level crossings (same pairing as frequency analysis).
func completeWavePeriods(from crossings: [Double]) -> [Double] {
    guard crossings.count >= 3 else {
        return []
    }
    var periods: [Double] = []
    var waveStart = 0
    while waveStart + 2 < crossings.count {
        let period = crossings[waveStart + 2] - crossings[waveStart]
        guard period > 0, period.isFinite else {
            return periods
        }
        periods.append(period)
        waveStart += 2
    }
    return periods
}

/// Average high (or low) pulse width at `threshold`.
/// High: rise→fall; low: fall→rise. Averages complete pulses only.
func averagePulseWidth(
    _ points: [Point],
    threshold: Double,
    high: Bool = true,
) -> Double? {
    let crossings = directedLevelCrossings(points, threshold: threshold)
    guard crossings.count >= 2 else {
        return nil
    }

    var widths: [Double] = []
    var index = 0
    while index + 1 < crossings.count {
        let first = crossings[index]
        let second = crossings[index + 1]
        let isHighPulse = first.rising && !second.rising
        let isLowPulse = !first.rising && second.rising
        if (high && isHighPulse) || (!high && isLowPulse) {
            let width = second.time - first.time
            if width > 0, width.isFinite {
                widths.append(width)
            }
            index += 2
        }
        else {
            // Skip leading half-pulse so pairing can lock.
            index += 1
        }
    }

    guard !widths.isEmpty else {
        return nil
    }
    return widths.reduce(0, +) / Double(widths.count)
}

/// Duty cycle as a fraction 0…1: mean high width / mean period at `threshold`.
func dutyCycleFraction(_ points: [Point], threshold: Double) -> Double? {
    let crossings = directedLevelCrossings(points, threshold: threshold)
    guard crossings.count >= 3 else {
        return nil
    }

    var duties: [Double] = []
    var index = 0
    // Align to a rising edge when possible for high-duty definition.
    while index < crossings.count, !crossings[index].rising {
        index += 1
    }

    while index + 2 < crossings.count {
        let rise = crossings[index]
        guard rise.rising else {
            index += 1
            continue
        }
        // Find fall then next rise.
        guard index + 1 < crossings.count else {
            break
        }
        let mid = crossings[index + 1]
        let next = crossings[index + 2]
        guard !mid.rising, next.rising else {
            index += 1
            continue
        }
        let period = next.time - rise.time
        let high = mid.time - rise.time
        if period > 0, high >= 0, period.isFinite, high.isFinite {
            duties.append(high / period)
        }
        index += 2 // next period starts at `next` (shared)
    }

    guard !duties.isEmpty else {
        return nil
    }
    return duties.reduce(0, +) / Double(duties.count)
}

/// Standard deviation of complete-wave periods (period jitter), or `nil` if &lt; 2 periods.
func periodStandardDeviation(from crossings: [Double]) -> Double? {
    let periods = completeWavePeriods(from: crossings)
    guard periods.count >= 2 else {
        return nil
    }
    let mean = periods.reduce(0, +) / Double(periods.count)
    var sumSquares = 0.0
    for period in periods {
        let delta = period - mean
        sumSquares += delta * delta
    }
    return sqrt(sumSquares / Double(periods.count))
}

// MARK: - THD from FFT spectrum

/// THD as a fraction (not percent): √(Σ Aₕ²) / A₁ for harmonics 2…`maxHarmonic`.
/// Uses linear magnitudes; searches ±1 bin around each harmonic.
func thdFraction(spectrum: FFTSpectrum, maxHarmonic: Int = 10) -> Double? {
    guard spectrum.frequencies.count == spectrum.magnitudes.count,
          spectrum.magnitudes.count > 2,
          spectrum.centerFrequency > 0,
          maxHarmonic >= 2 else {
        return nil
    }

    let binWidth = spectrum.frequencies.count >= 2
        ? spectrum.frequencies[1] - spectrum.frequencies[0]
        : spectrum.sampleRate / Double(spectrum.fftSize)
    guard binWidth > 0 else {
        return nil
    }

    func peakNear(_ frequency: Double) -> Double {
        let idealBin = frequency / binWidth
        let center = Int(idealBin.rounded())
        let lo = max(1, center - 1)
        let hi = min(spectrum.magnitudes.count - 1, center + 1)
        var best = 0.0
        for bin in lo ... hi {
            best = max(best, spectrum.magnitudes[bin])
        }
        return best
    }

    let fundamental = peakNear(spectrum.centerFrequency)
    guard fundamental > 0 else {
        return nil
    }

    var harmonicPower = 0.0
    for harmonic in 2 ... maxHarmonic {
        let freq = spectrum.centerFrequency * Double(harmonic)
        if freq >= spectrum.sampleRate / 2 {
            break
        }
        let mag = peakNear(freq)
        harmonicPower += mag * mag
    }

    guard harmonicPower > 0 else {
        return 0
    }
    return sqrt(harmonicPower) / fundamental
}
