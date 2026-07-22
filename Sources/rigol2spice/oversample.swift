import Foundation

// MARK: - OversampleError

enum OversampleError: LocalizedError, Equatable {
    case factorExceedsPointCount(factor: Int, pointCount: Int)
    case pointCountNotDivisible(
        factor: Int,
        pointCount: Int,
        removePoints: Int,
        addPoints: Int,
        sampleInterval: Double,
    )
    case nonFiniteSample(index: Int)

    var errorDescription: String? {
        switch self {
        case let .factorExceedsPointCount(factor, pointCount):
            return "Oversample factor \(factor) exceeds the capture's \(pointCount) samples"
        case let .pointCountNotDivisible(
            factor,
            pointCount,
            removePoints,
            addPoints,
            sampleInterval,
        ):
            let targetPointCount = removePoints <= addPoints
                ? pointCount - removePoints
                : pointCount + addPoints
            let duration = Double(pointCount - 1) * sampleInterval
            // Keep the suggested rate just above the exact boundary because ResampleF
            // determines its point count by flooring duration * frequency.
            let frequency = (Double(targetPointCount - 1) / duration) * (1 + 1e-12)
            return "Oversample \(factor) requires a sample count divisible by \(factor), but the capture has \(pointCount) samples. Remove \(removePoints) sample(s) (\(engineeringFormatter.string(Double(removePoints) * sampleInterval))s) or add \(addPoints) sample(s) (\(engineeringFormatter.string(Double(addPoints) * sampleInterval))s). Alternatively, apply `ResampleF \(engineeringFormatter.string(frequency))Hz` before `Oversample \(factor)` to resample to \(targetPointCount) samples."
        case let .nonFiniteSample(index):
            return "Oversample requires finite timestamps and values; sample \(index) is not finite"
        }
    }
}

/// Divide a capture into `factor` equal contiguous segments and average aligned values.
/// This is coherent ensemble averaging: it improves repeatable-signal amplitude resolution
/// while retaining the source sampling interval and one segment's duration.
func oversamplePoints(
    _ points: [Point],
    factor: Int,
    sampleInterval providedSampleInterval: Double? = nil,
) throws -> [Point] {
    guard factor > 1 else {
        throw TransformationParseError.invalidResamplingFactor(
            operation: "Oversample",
            value: String(factor),
        )
    }
    guard factor <= points.count else {
        throw OversampleError.factorExceedsPointCount(factor: factor, pointCount: points.count)
    }

    for (index, point) in points.enumerated() where !point.time.isFinite || !point.value.isFinite {
        throw OversampleError.nonFiniteSample(index: index)
    }

    let measuredInterval = (points[points.count - 1].time - points[0].time)
        / Double(points.count - 1)
    let gridInterval = if measuredInterval.isFinite, measuredInterval > 0 {
        measuredInterval
    }
    else {
        try resolveSampleInterval(
            providedSampleInterval,
            points: points,
            operation: "Oversample",
        )
    }
    let timestampMagnitude = max(1, abs(points[0].time), abs(points[points.count - 1].time))
    let intervalTolerance = max(
        abs(gridInterval) * 1e-6,
        timestampMagnitude * Double.ulpOfOne * 16,
        1e-15,
    )
    let sampleInterval = if let providedSampleInterval,
                            providedSampleInterval.isFinite,
                            providedSampleInterval > 0,
                            abs(providedSampleInterval - gridInterval) <= intervalTolerance {
        providedSampleInterval
    }
    else {
        gridInterval
    }

    let remainder = points.count % factor
    guard remainder == 0 else {
        throw OversampleError.pointCountNotDivisible(
            factor: factor,
            pointCount: points.count,
            removePoints: remainder,
            addPoints: factor - remainder,
            sampleInterval: sampleInterval,
        )
    }

    let segmentPointCount = points.count / factor
    var output: [Point] = []
    output.reserveCapacity(segmentPointCount)
    for pointIndex in 0 ..< segmentPointCount {
        var sum = 0.0
        var compensation = 0.0
        for segmentIndex in 0 ..< factor {
            let value = points[segmentIndex * segmentPointCount + pointIndex].value
            let corrected = value - compensation
            let updated = sum + corrected
            compensation = (updated - sum) - corrected
            sum = updated
        }
        output.append(Point(
            time: Double(pointIndex) * sampleInterval,
            value: sum / Double(factor),
        ))
    }
    return output
}
