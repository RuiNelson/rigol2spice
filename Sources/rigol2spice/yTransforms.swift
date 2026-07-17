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

/// Scale so the peak absolute value is 1. Unchanged if the peak is zero.
func normalizePoints(_ points: [Point]) -> [Point] {
    let peak = peakAbsoluteValue(points)
    guard peak > 0 else {
        return points
    }
    return multiplyValueOfPoints(points, factor: 1 / peak)
}

/// Scale so the peak absolute value equals `target`. Unchanged if the peak is zero.
func scalePeakTo(_ points: [Point], target: Double) -> [Point] {
    let peak = peakAbsoluteValue(points)
    guard peak > 0 else {
        return points
    }
    return multiplyValueOfPoints(points, factor: target / peak)
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
