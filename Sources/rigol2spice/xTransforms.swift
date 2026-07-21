import Foundation

private func firstPointIndex(atOrAfter targetTime: Double, in points: [Point]) -> Int {
    var lowerBound = 0
    var upperBound = points.count

    while lowerBound < upperBound {
        let middle = lowerBound + (upperBound - lowerBound) / 2
        if points[middle].time < targetTime {
            lowerBound = middle + 1
        }
        else {
            upperBound = middle
        }
    }

    return lowerBound
}

func removeRedundant(_ source: [Point]) -> [Point] {
    guard source.count >= 3 else {
        return source
    }

    var output: [Point] = []
    output.reserveCapacity(source.count)
    output.append(source[0])

    for index in 1 ..< source.count - 1 {
        let previousValue = source[index - 1].value
        let value = source[index].value
        let nextValue = source[index + 1].value

        if previousValue != value || value != nextValue {
            output.append(source[index])
        }
    }

    output.append(source[source.count - 1])
    return output
}

// MARK: - TriggerEdge

enum TriggerEdge: Equatable, CustomStringConvertible {
    case rising
    case falling
    /// First rising or falling crossing, whichever comes first.
    case either

    var description: String {
        switch self {
        case .rising: "rising"
        case .falling: "falling"
        case .either: "either"
        }
    }
}

/// Find the first rising, falling, or either-direction crossing of `threshold` and shift that
/// instant to t = 0. Optional `after` restricts the search to edges at or after that time.
func triggerPoints(
    _ points: [Point],
    edge: TriggerEdge,
    threshold: Double,
    after: Double? = nil,
) throws -> [Point] {
    guard points.count >= 2 else {
        throw Rigol2SpiceError.edgeNotFound(edge: edge, threshold: threshold)
    }

    let searchStart: Int = if let after {
        firstPointIndex(atOrAfter: after, in: points)
    }
    else {
        0
    }

    guard searchStart < points.count else {
        throw Rigol2SpiceError.edgeNotFound(edge: edge, threshold: threshold)
    }

    // Walk consecutive pairs; start from the first pair that ends at or after searchStart.
    let pairStart = max(1, searchStart)
    for index in pairStart ..< points.count {
        let previous = points[index - 1]
        let current = points[index]
        let crossedUp = previous.value < threshold && current.value >= threshold
        let crossedDown = previous.value > threshold && current.value <= threshold
        let crossed: Bool = switch edge {
        case .rising:
            crossedUp
        case .falling:
            crossedDown
        case .either:
            crossedUp || crossedDown
        }
        guard crossed else {
            continue
        }

        let delta = current.value - previous.value
        let edgeTime: Double
        if delta == 0 {
            edgeTime = current.time
        }
        else {
            let fraction = (threshold - previous.value) / delta
            edgeTime = previous.time + fraction * (current.time - previous.time)
        }

        if let after, edgeTime < after {
            continue
        }

        var shifted = timeShiftPoints(points, value: -edgeTime)
        // Crossing may fall between samples; ensure a point at t = 0 with the threshold value.
        if shifted.isEmpty || shifted[0].time > 0 {
            shifted.insert(Point(time: 0, value: threshold), at: 0)
        }
        else {
            shifted[0].time = 0
        }
        return shifted
    }

    throw Rigol2SpiceError.edgeNotFound(edge: edge, threshold: threshold)
}

/// Interpolated time when the segment from `previous` to `current` meets `threshold`.
func interpolatedCrossingTime(
    previous: Point,
    current: Point,
    threshold: Double,
) -> Double {
    let delta = current.value - previous.value
    if delta == 0 {
        return current.time
    }
    let fraction = (threshold - previous.value) / delta
    return previous.time + fraction * (current.time - previous.time)
}

/// Rising threshold crossings (linear interpolation between samples).
/// A crossing is recorded when a pair goes from strictly below `threshold` to at or above it.
func risingCrossingTimes(_ points: [Point], threshold: Double) -> [Double] {
    guard points.count >= 2 else {
        return []
    }

    var crossings: [Double] = []
    for index in 1 ..< points.count {
        let previous = points[index - 1]
        let current = points[index]
        guard previous.value < threshold, current.value >= threshold else {
            continue
        }
        crossings.append(interpolatedCrossingTime(
            previous: previous,
            current: current,
            threshold: threshold,
        ))
    }
    return crossings
}

/// All level crossings of `threshold` (rising and falling), linearly interpolated.
/// Used by frequency analysis so incomplete half-waves at the ends can be discarded.
func levelCrossingTimes(_ points: [Point], threshold: Double) -> [Double] {
    directedLevelCrossings(points, threshold: threshold).map(\.time)
}

/// Average period and frequency from **complete** waves only.
///
/// Crossings are level passages (rise + fall). The first complete wave needs 3 crossings;
/// each further wave reuses the last crossing of the previous wave and needs 2 more:
/// periods = t₂−t₀, t₄−t₂, t₆−t₄, … Partial waves at the start/end are ignored.
func averagePeriodAndFrequency(
    from crossings: [Double],
) -> (period: Double, frequency: Double)? {
    guard crossings.count >= 3 else {
        return nil
    }

    var sum = 0.0
    var completeWaves = 0
    var waveStart = 0
    while waveStart + 2 < crossings.count {
        let period = crossings[waveStart + 2] - crossings[waveStart]
        guard period > 0, period.isFinite else {
            return nil
        }
        sum += period
        completeWaves += 1
        waveStart += 2
    }

    guard completeWaves > 0 else {
        return nil
    }

    let period = sum / Double(completeWaves)
    return (period, 1 / period)
}

/// Detect one fundamental period via rising threshold crossings and keep it.
/// Default threshold is the midpoint of min/max. Result is shifted so t starts at 0.
func extractPeriodPoints(_ points: [Point], threshold: Double?) throws -> [Point] {
    guard points.count >= 3 else {
        throw Rigol2SpiceError.periodNotDetected
    }

    let thresh: Double
    if let threshold {
        thresh = threshold
    }
    else {
        guard let range = valueRange(points), range.maximum > range.minimum else {
            throw Rigol2SpiceError.periodNotDetected
        }
        thresh = 0.5 * (range.minimum + range.maximum)
    }

    let crossings = risingCrossingTimes(points, threshold: thresh)
    guard crossings.count >= 2 else {
        throw Rigol2SpiceError.periodNotDetected
    }

    var intervals = [Double]()
    intervals.reserveCapacity(crossings.count - 1)
    for index in 1 ..< crossings.count {
        intervals.append(crossings[index] - crossings[index - 1])
    }
    intervals.sort()
    let period = intervals[intervals.count / 2]
    guard period > 0, period.isFinite else {
        throw Rigol2SpiceError.periodNotDetected
    }

    let start = crossings[0]
    let end = start + period
    let trimmed = trimPoints(points, start: start, end: end)
    guard trimmed.count >= 2 else {
        throw Rigol2SpiceError.periodNotDetected
    }

    var shifted = timeShiftPoints(trimmed, value: -start)
    if shifted.isEmpty || shifted[0].time > 0 {
        shifted.insert(Point(time: 0, value: thresh), at: 0)
    }
    else {
        shifted[0].time = 0
    }
    return shifted
}

// MARK: - ResamplingInterpolation

enum ResamplingInterpolation: String, Equatable {
    case linear
    case pchip
    case sinc
}

// MARK: - ResamplingDirection

enum ResamplingDirection: Equatable {
    case downsample
    case upsample

    var operationName: String {
        switch self {
        case .downsample: "Downsample"
        case .upsample: "Upsample"
        }
    }
}

// MARK: - ResamplingError

enum ResamplingError: LocalizedError, Equatable {
    case invalidFactor(operation: String, factor: Double)
    case pointCountTooLarge(operation: String, factor: Double)

    var errorDescription: String? {
        switch self {
        case let .invalidFactor(operation, factor):
            "\(operation) factor must be finite and greater than 1, but received \(factor)"
        case let .pointCountTooLarge(operation, factor):
            "\(operation) factor \(factor) would create too many samples"
        }
    }
}

/// Resample to a factor of the original point count while preserving both time endpoints.
/// Downsampling intentionally performs no anti-alias filtering.
func resamplePoints(
    _ points: [Point],
    factor: Double,
    direction: ResamplingDirection,
    interpolation: ResamplingInterpolation,
) throws -> [Point] {
    let operation = direction.operationName
    guard factor.isFinite, factor > 1 else {
        throw ResamplingError.invalidFactor(operation: operation, factor: factor)
    }
    guard points.count >= 2 else {
        return points
    }

    let start = points[0].time
    let end = points[points.count - 1].time
    guard end > start else {
        return points
    }

    let rawTargetCount = switch direction {
    case .downsample: Double(points.count) / factor
    case .upsample: Double(points.count) * factor
    }
    guard rawTargetCount.isFinite, rawTargetCount <= 100_000_000 else {
        throw ResamplingError.pointCountTooLarge(operation: operation, factor: factor)
    }

    let roundedCount = Int(rawTargetCount.rounded(.toNearestOrAwayFromZero))
    let targetCount: Int = switch direction {
    case .downsample:
        points.count == 2 ? 2 : min(points.count - 1, max(2, roundedCount))
    case .upsample:
        max(points.count + 1, roundedCount)
    }

    let values: [Double] = switch interpolation {
    case .linear:
        linearResampledValues(points, targetCount: targetCount)
    case .pchip:
        pchipResampledValues(points, targetCount: targetCount)
    case .sinc:
        sincResampledValues(points, targetCount: targetCount)
    }
    let interval = (end - start) / Double(targetCount - 1)
    return values.enumerated().map { index, value in
        let time = index == targetCount - 1 ? end : start + Double(index) * interval
        return Point(time: time, value: value)
    }
}

private func linearResampledValues(_ points: [Point], targetCount: Int) -> [Double] {
    valuesOnUniformGrid(points, targetCount: targetCount) { _, before, after, time in
        guard after.time != before.time else {
            return before.value
        }
        let progress = (time - before.time) / (after.time - before.time)
        return before.value + (after.value - before.value) * progress
    }
}

private func valuesOnUniformGrid(
    _ points: [Point],
    targetCount: Int,
    interpolate: (_ sourceIndex: Int, _ before: Point, _ after: Point, _ time: Double) -> Double,
) -> [Double] {
    let start = points[0].time
    let end = points[points.count - 1].time
    let interval = (end - start) / Double(targetCount - 1)
    var sourceIndex = 0
    return (0 ..< targetCount).map { index in
        if index == targetCount - 1 {
            return points[points.count - 1].value
        }
        let time = start + Double(index) * interval
        while sourceIndex + 1 < points.count - 1, points[sourceIndex + 1].time < time {
            sourceIndex += 1
        }
        return interpolate(sourceIndex, points[sourceIndex], points[sourceIndex + 1], time)
    }
}

private func pchipResampledValues(_ points: [Point], targetCount: Int) -> [Double] {
    guard points.count > 2 else {
        return linearResampledValues(points, targetCount: targetCount)
    }

    let intervals = (0 ..< points.count - 1).map { points[$0 + 1].time - points[$0].time }
    guard intervals.allSatisfy({ $0.isFinite && $0 > 0 }) else {
        return linearResampledValues(points, targetCount: targetCount)
    }
    let secants = (0 ..< points.count - 1).map {
        (points[$0 + 1].value - points[$0].value) / intervals[$0]
    }
    var slopes = [Double](repeating: 0, count: points.count)

    for index in 1 ..< points.count - 1 {
        let previous = secants[index - 1]
        let next = secants[index]
        guard previous != 0, next != 0, previous.sign == next.sign else {
            slopes[index] = 0
            continue
        }
        let firstWeight = 2 * intervals[index] + intervals[index - 1]
        let secondWeight = intervals[index] + 2 * intervals[index - 1]
        slopes[index] = (firstWeight + secondWeight) / (firstWeight / previous + secondWeight / next)
    }

    func endpointSlope(first h1: Double, second h2: Double, firstDelta d1: Double, secondDelta d2: Double) -> Double {
        var slope = ((2 * h1 + h2) * d1 - h1 * d2) / (h1 + h2)
        if slope.sign != d1.sign {
            slope = 0
        }
        else if d1.sign != d2.sign, abs(slope) > abs(3 * d1) {
            slope = 3 * d1
        }
        return slope
    }

    slopes[0] = endpointSlope(
        first: intervals[0],
        second: intervals[1],
        firstDelta: secants[0],
        secondDelta: secants[1],
    )
    slopes[slopes.count - 1] = endpointSlope(
        first: intervals[intervals.count - 1],
        second: intervals[intervals.count - 2],
        firstDelta: secants[secants.count - 1],
        secondDelta: secants[secants.count - 2],
    )

    return valuesOnUniformGrid(points, targetCount: targetCount) { index, before, after, time in
        let width = after.time - before.time
        let position = (time - before.time) / width
        let position2 = position * position
        let position3 = position2 * position
        let h00 = 2 * position3 - 3 * position2 + 1
        let h10 = position3 - 2 * position2 + position
        let h01 = -2 * position3 + 3 * position2
        let h11 = position3 - position2
        return h00 * before.value
            + h10 * width * slopes[index]
            + h01 * after.value
            + h11 * width * slopes[index + 1]
    }
}

private func sincResampledValues(_ points: [Point], targetCount: Int) -> [Double] {
    let start = points[0].time
    let end = points[points.count - 1].time
    let targetInterval = (end - start) / Double(targetCount - 1)
    let sourceInterval = (end - start) / Double(points.count - 1)
    let radius = 8

    func sinc(_ value: Double) -> Double {
        if abs(value) < 1e-12 {
            return 1
        }
        return sin(Double.pi * value) / (Double.pi * value)
    }

    return (0 ..< targetCount).map { targetIndex in
        if targetIndex == 0 {
            return points[0].value
        }
        if targetIndex == targetCount - 1 {
            return points[points.count - 1].value
        }
        let time = start + Double(targetIndex) * targetInterval
        let center = Int(((time - start) / sourceInterval).rounded())
        let lower = max(0, center - radius + 1)
        let upper = min(points.count - 1, center + radius)
        var weightedValue = 0.0
        var weightSum = 0.0
        for sourceIndex in lower ... upper {
            let distance = (time - points[sourceIndex].time) / sourceInterval
            guard abs(distance) < Double(radius) else {
                continue
            }
            let weight = sinc(distance) * sinc(distance / Double(radius))
            weightedValue += weight * points[sourceIndex].value
            weightSum += weight
        }
        return weightSum == 0 ? points[min(max(center, 0), points.count - 1)].value : weightedValue / weightSum
    }
}

/// Extend the capture by `duration` past the last sample, holding `value` (or the last value).
func padPoints(_ points: [Point], duration: Double, value: Double?) -> [Point] {
    guard !points.isEmpty, duration > 0 else {
        return points
    }
    let last = points[points.count - 1]
    var output = points
    output.append(Point(time: last.time + duration, value: value ?? last.value))
    return output
}

/// Extend the capture so the last sample is at `endTime` (no-op if already at or past endTime).
func extendPoints(to endTime: Double, points: [Point], value: Double?) -> [Point] {
    guard !points.isEmpty else {
        return points
    }
    let last = points[points.count - 1]
    guard endTime > last.time else {
        return points
    }
    var output = points
    output.append(Point(time: endTime, value: value ?? last.value))
    return output
}

/// Make the capture loopable: force the last value to match the first.
/// When `rampDuration` is positive, append a linear ramp of that length from the
/// current last value to the first value instead of overwriting the last sample.
func seamlessPoints(_ points: [Point], rampDuration: Double?) -> [Point] {
    guard points.count >= 2 else {
        return points
    }

    let firstValue = points[0].value
    let last = points[points.count - 1]

    if let rampDuration, rampDuration > 0 {
        var output = points
        output.append(Point(time: last.time + rampDuration, value: firstValue))
        return output
    }

    var output = points
    output[output.count - 1].value = firstValue
    return output
}

/// Scale the time axis by `factor` (> 0), preserving the first sample's timestamp.
func timeScalePoints(_ points: [Point], factor: Double) -> [Point] {
    guard factor != 1, !points.isEmpty else {
        return points
    }

    let origin = points[0].time
    return points.map { point in
        Point(time: origin + (point.time - origin) * factor, value: point.value)
    }
}

func timeShiftPoints(_ points: [Point], value: Double) -> [Point] {
    guard !points.isEmpty else {
        return points
    }

    if value == 0, points[0].time >= 0 {
        return points
    }

    let firstIndex = firstPointIndex(atOrAfter: -value, in: points)
    guard firstIndex < points.count else {
        return []
    }

    var shifted: [Point] = []
    shifted.reserveCapacity(points.count - firstIndex)

    for index in firstIndex ..< points.count {
        let point = points[index]
        shifted.append(Point(time: point.time + value, value: point.value))
    }

    return shifted
}

func cutPointsAfter(_ points: [Point], after: Double) -> [Point] {
    let endIndex = firstPointIndex(atOrAfter: after, in: points)
    guard endIndex < points.count else {
        return points
    }

    return Array(points[..<endIndex])
}

/// Discard samples strictly before `before`; keep times unchanged.
func cutPointsBefore(_ points: [Point], before: Double) -> [Point] {
    let startIndex = firstPointIndex(atOrAfter: before, in: points)
    guard startIndex > 0 else {
        return points
    }
    guard startIndex < points.count else {
        return []
    }
    return Array(points[startIndex...])
}

/// Keep samples with `start <= time < end`; times unchanged.
func trimPoints(_ points: [Point], start: Double, end: Double) -> [Point] {
    cutPointsAfter(cutPointsBefore(points, before: start), after: end)
}

func repeatPoints(_ points: [Point], amount: Double) throws -> [Point] {
    guard points.count >= 2 else {
        throw Rigol2SpiceError.mustHaveAtLeastTwoPointsToRepeat
    }

    guard amount > 0,
          amount.isFinite,
          amount < Double(Int.max),
          let completeRepeats = Int(exactly: amount.rounded(.down)) else {
        throw TransformationParseError.invalidPositiveScalar(operation: "Repeat", value: String(amount))
    }

    let fractionalRepeat = amount - Double(completeRepeats)
    let firstPoint = points[0]
    let increment = points[1].time - firstPoint.time
    let periodDuration = points[points.count - 1].time - firstPoint.time + increment
    let partialDuration = periodDuration * fractionalRepeat
    let partialEndIndex = fractionalRepeat > 0
        ? firstPointIndex(atOrAfter: firstPoint.time + partialDuration, in: points)
        : 0

    var output: [Point] = []
    let (completePointCount, overflowed) = points.count.multipliedReportingOverflow(by: completeRepeats + 1)
    if !overflowed {
        let partialPointCount = fractionalRepeat > 0 ? partialEndIndex + 1 : 0
        let (capacity, capacityOverflowed) = completePointCount.addingReportingOverflow(partialPointCount)
        if !capacityOverflowed {
            output.reserveCapacity(capacity)
        }
    }

    output.append(contentsOf: points)

    if completeRepeats > 0 {
        for copyIndex in 1 ... completeRepeats {
            let timeShift = Double(copyIndex) * periodDuration
            for point in points {
                output.append(Point(time: point.time + timeShift, value: point.value))
            }
        }
    }

    if fractionalRepeat > 0 {
        let timeShift = Double(completeRepeats + 1) * periodDuration

        for index in 0 ..< partialEndIndex {
            let point = points[index]
            output.append(Point(time: point.time + timeShift, value: point.value))
        }

        let boundaryTime = firstPoint.time + partialDuration
        let before = partialEndIndex > 0 ? points[partialEndIndex - 1] : firstPoint
        let after = partialEndIndex < points.count
            ? points[partialEndIndex]
            : Point(time: firstPoint.time + periodDuration, value: firstPoint.value)

        let boundaryValue: Double
        if boundaryTime == after.time {
            boundaryValue = after.value
        }
        else {
            let progress = (boundaryTime - before.time) / (after.time - before.time)
            boundaryValue = before.value + (after.value - before.value) * progress
        }

        output.append(Point(time: boundaryTime + timeShift, value: boundaryValue))
    }

    return output
}
