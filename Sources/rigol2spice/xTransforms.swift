import Foundation

func equal(_ a: Double, _ b: Double, _ c: Double) -> Bool {
    a == b && b == c
}

func removeRedundant(_ source: [Point]) -> [Point] {
    var output = source
    var toDelete: Set<Double> = []

    for n in 1 ..< (output.count - 1) {
        let before = output[n - 1]
        let now = output[n]
        let after = output[n + 1]

        if equal(before.value, now.value, after.value) {
            toDelete.insert(now.time)
        }
    }

    if !toDelete.isEmpty {
        output = output.filter { !toDelete.contains($0.time) }
    }

    return output
}

func downsamplePoints(_ source: [Point], interval: Int) -> [Point] {
    var i = (interval - 1)

    return source.filter { _ in
        i += 1
        return (i % interval) == 0
    }
}

func timeShiftPoints(_ points: [Point], value: Double) -> [Point] {
    let shifted: [Point] = points.map { point in
        var shiftedPoint = point
        shiftedPoint.time = shiftedPoint.time + value
        return shiftedPoint
    }

    return shifted.filter { $0.time >= 0 }
}

func cutPointsAfter(_ points: [Point], after: Double) -> [Point] {
    points.filter { $0.time < after }
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
    let increment = points[1].time - points[0].time
    let periodDuration = points.last!.time - firstPoint.time + increment
    var newPoints = points

    if completeRepeats > 0 {
        for copyIndex in 1 ... completeRepeats {
            let timeShift = Double(copyIndex) * periodDuration
            newPoints.append(contentsOf: points.map {
                Point(time: $0.time + timeShift, value: $0.value)
            })
        }
    }

    if fractionalRepeat > 0 {
        let partialDuration = periodDuration * fractionalRepeat
        let timeShift = Double(completeRepeats + 1) * periodDuration

        newPoints.append(contentsOf: points.lazy.filter {
            $0.time - firstPoint.time < partialDuration
        }.map {
            Point(time: $0.time + timeShift, value: $0.value)
        })

        let boundaryTime = firstPoint.time + partialDuration
        let before = points.last { $0.time <= boundaryTime } ?? firstPoint
        let after = points.first { $0.time >= boundaryTime }
            ?? Point(time: firstPoint.time + periodDuration, value: firstPoint.value)

        let boundaryValue: Double
        if before.time == after.time {
            boundaryValue = before.value
        }
        else {
            let progress = (boundaryTime - before.time) / (after.time - before.time)
            boundaryValue = before.value + (after.value - before.value) * progress
        }

        newPoints.append(Point(time: boundaryTime + timeShift, value: boundaryValue))
    }

    return newPoints
}
