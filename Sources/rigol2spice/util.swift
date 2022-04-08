//
//  File.swift
//  
//
//  Created by Rui Magalhães Carneiro on 04/04/2022.
//

import Foundation

func removeUnecessary(_ source: [Point]) -> [Point] {
    var previousValue: Double = Double.nan
    
    let output = source.filter { point in
        if point.value == previousValue {
            return false
        }
        else {
            previousValue = point.value
            return true
        }
    }
    
    return output
}

func downsamplePoints(_ source: [Point], interval: Int) -> [Point] {
    var i = (interval - 1)
    
    let downsampled = source.filter {_ in
        i += 1
        return (i % interval) == 0
    }
    
    return downsampled
}

func parseEngineeringNotation(_ input: String) -> Double? {
    var str = input.lowercased()
    var multiplier: Double = 1.0
    var signal: Double!
    
    if str.hasPrefix("l") {
        str.removeFirst()
        signal = -1
    }
    else if str.hasPrefix("r") {
        str.removeFirst()
        signal = +1
    }
    else {
        signal = +1
    }
    
    if str.hasSuffix("s") {
        str.removeLast()
    }
    
    if str.hasSuffix("m") {
        str.removeLast()
        multiplier = 1E-3
    }
    else if str.hasSuffix("u") || str.hasSuffix("µ") {
        str.removeLast()
        multiplier = 1E-6
    }
    else if str.hasSuffix("n") {
        str.removeLast()
        multiplier = 1E-9
    }
    else if str.hasSuffix("p") {
        str.removeLast()
        multiplier = 1E-12
    }
    else if str.hasSuffix("f") {
        str.removeLast()
        multiplier = 1E-15
    }
    
    if let base = Double(str.uppercased()) {
        return signal * base * multiplier
    }
    else {
        return nil
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
    
    for i in 0...n {
        if i == 0 {
            newPoints.append(contentsOf: points)
        }
        else {
            var start = newPoints.last!.time + increment
            let shifted = timeShiftPoints(points, value: start)
            
            newPoints.append(contentsOf: shifted)
        }
    }
    
    return newPoints
}
