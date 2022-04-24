// (C) Rui Carneiro

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

func removeDC(_ points: [Point]) -> (dcComponent: Double, points: [Point]) {
    let sum = points.reduce(0.0) { partialResult, pt in
        partialResult + pt.value
    }

    let dc = sum / Double(points.count)
    let newPoints = offsetPoints(points, offset: 0 - dc)

    return (dc, newPoints)
}
