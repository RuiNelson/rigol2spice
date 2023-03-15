import Foundation

func multiplyValueOfPoints(_ points: [Point], factor: Double) -> [Point] {
    points.map {
        var point = $0
        point.value = point.value * factor
        return point
    }
}

func offsetPoints(_ points: [Point], offset: Double) -> [Point] {
    points.map {
        var point = $0
        point.value = point.value + offset
        return point
    }
}

func calculateDC(_ points: [Point]) -> Double {
    let sum = points.reduce(0.0) { partialResult, pt in
        partialResult + pt.value
    }

    return sum / Double(points.count)
}

func clamp(_ points: [Point], lowerLimit: Double?, upperLimit: Double?) -> [Point] {
    return points.map({ oldPoint in
        var newPoint = oldPoint
        
        if let lowerLimit {
            if oldPoint.value < lowerLimit {
                newPoint.value = lowerLimit
            }
        }
        
        if let upperLimit {
            if oldPoint.value > upperLimit {
                newPoint.value = upperLimit
            }
        }
        
        return newPoint
    })
}
