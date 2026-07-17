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

func repeatPoints(_ points: [Point], amount: Double) throws -> [Point] {
    guard points.count >= 2 else {
        throw Rigol2SpiceErrors.mustHaveAtLeastTwoPointsToRepeat
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
