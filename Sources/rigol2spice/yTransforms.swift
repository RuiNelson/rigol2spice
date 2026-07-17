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
