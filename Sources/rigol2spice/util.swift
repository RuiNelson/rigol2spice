//  (C) Rui Carneiro

import Foundation

func removeRedundant(_ source: [Point]) -> [Point] {
    var samples = source
    var toDelete: Set<Double> = []

    for n in 1 ..< (samples.count - 1) {
        let before = samples[n - 1]
        let now = samples[n]
        let after = samples[n + 1]

        if before.value == after.value, now.value == before.value {
            toDelete.insert(now.time)
        }
    }

    samples = samples.filter { toDelete.contains($0.time) == false }

    return samples
}

func downsamplePoints(_ source: [Point], interval: Int) -> [Point] {
    var i = (interval - 1)

    let downsampled = source.filter { _ in
        i += 1
        return (i % interval) == 0
    }

    return downsampled
}

func parseEngineeringNotation(_ input: String) -> Double? {
    var numberStr = input

    if numberStr.hasSuffix("s") || numberStr.hasSuffix("S") {
        numberStr.removeLast()
    }

    let signal: Double = {
        let lowercased = input.lowercased()

        if lowercased.hasPrefix("l") || lowercased.hasPrefix("m") {
            numberStr.removeFirst()
            return -1
        } else if lowercased.hasPrefix("r") || lowercased.hasPrefix("p") {
            numberStr.removeFirst()
            return +1
        } else {
            return +1
        }
    }()

    guard let value = engineeringNF.double(numberStr) else {
        return nil
    }

    return signal * value
}

func multiplyValueOfPoints(_ points: [Point], factor: Double) -> [Point] {
    points.map {
        var point = $0
        point.value = point.value * factor
        return point
    }
}

func timeShiftPoints(_ points: [Point], value: Double) -> [Point] {
    let shifted: [Point] = points.map { point in
        var shiftedPoint = point
        shiftedPoint.time = shiftedPoint.time + value
        return shiftedPoint
    }

    let filtered = shifted.filter { $0.time >= 0 }

    return filtered
}

func cutAfter(_ points: [Point], after: Double) -> [Point] {
    return points.filter { $0.time < after }
}

func repeatPoints(_ points: [Point], n: Int) throws -> [Point] {
    guard points.count >= 2 else {
        throw Rigol2SpiceErrors.mustHaveAtLeastTwoPointsToRepeat
    }

    let increment = points[1].time - points[0].time
    var newPoints = [Point]()

    for i in 0 ... n {
        if i == 0 {
            newPoints.append(contentsOf: points)
        } else {
            let start = newPoints.last!.time + increment
            let shifted = timeShiftPoints(points, value: start)

            newPoints.append(contentsOf: shifted)
        }
    }

    return newPoints
}
