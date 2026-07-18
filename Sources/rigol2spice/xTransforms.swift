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

func downsamplePoints(_ source: [Point], interval: Int) -> [Point] {
    guard interval > 1, source.count > 1 else {
        return source
    }

    var output: [Point] = []
    output.reserveCapacity((source.count - 1) / interval + 1)

    var index = 0
    while index < source.count {
        output.append(source[index])
        index += interval
    }

    return output
}

/// Find the first rising or falling crossing of `threshold` and shift that instant to t = 0.
/// Optional `after` restricts the search to edges at or after that time.
func triggerAtPoints(
    _ points: [Point],
    rising: Bool,
    threshold: Double,
    after: Double? = nil,
) throws -> [Point] {
    guard points.count >= 2 else {
        throw Rigol2SpiceError.edgeNotFound(rising: rising, threshold: threshold)
    }

    let searchStart: Int
    if let after {
        searchStart = firstPointIndex(atOrAfter: after, in: points)
    }
    else {
        searchStart = 0
    }

    guard searchStart < points.count else {
        throw Rigol2SpiceError.edgeNotFound(rising: rising, threshold: threshold)
    }

    // Walk consecutive pairs; start from the first pair that ends at or after searchStart.
    let pairStart = max(1, searchStart)
    for index in pairStart ..< points.count {
        let previous = points[index - 1]
        let current = points[index]
        let crossed: Bool
        if rising {
            crossed = previous.value < threshold && current.value >= threshold
        }
        else {
            crossed = previous.value > threshold && current.value <= threshold
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

    throw Rigol2SpiceError.edgeNotFound(rising: rising, threshold: threshold)
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
        var minimum = points[0].value
        var maximum = points[0].value
        for point in points {
            minimum = min(minimum, point.value)
            maximum = max(maximum, point.value)
        }
        guard maximum > minimum else {
            throw Rigol2SpiceError.periodNotDetected
        }
        thresh = 0.5 * (minimum + maximum)
    }

    var crossings: [Double] = []
    for index in 1 ..< points.count {
        let previous = points[index - 1]
        let current = points[index]
        guard previous.value < thresh, current.value >= thresh else {
            continue
        }
        let delta = current.value - previous.value
        if delta == 0 {
            crossings.append(current.time)
        }
        else {
            let fraction = (thresh - previous.value) / delta
            crossings.append(previous.time + fraction * (current.time - previous.time))
        }
    }

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

/// Linearly interpolate onto a uniform grid with the given sample interval.
func resamplePoints(_ points: [Point], interval: Double) throws -> [Point] {
    guard interval > 0, interval.isFinite else {
        throw TransformationParseError.invalidPositiveScalar(
            operation: "Resample",
            value: String(interval),
        )
    }
    guard points.count >= 2 else {
        return points
    }

    let start = points[0].time
    let end = points[points.count - 1].time
    guard end > start else {
        return points
    }

    let duration = end - start
    let stepCount = Int((duration / interval).rounded(.down))
    var output: [Point] = []
    output.reserveCapacity(stepCount + 2)

    var sourceIndex = 0
    var time = start
    var steps = 0
    while time < end - interval * 1e-12 {
        while sourceIndex + 1 < points.count, points[sourceIndex + 1].time < time {
            sourceIndex += 1
        }
        let before = points[sourceIndex]
        let afterIndex = min(sourceIndex + 1, points.count - 1)
        let after = points[afterIndex]
        let value: Double
        if after.time == before.time {
            value = before.value
        }
        else {
            let progress = (time - before.time) / (after.time - before.time)
            value = before.value + (after.value - before.value) * progress
        }
        output.append(Point(time: time, value: value))
        steps += 1
        time = start + Double(steps) * interval
        // Safety against huge allocations
        if steps > 100_000_000 {
            break
        }
    }
    // Always include the original end sample
    output.append(points[points.count - 1])
    return output
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
