import Foundation

// MARK: - AnalogModulationError

enum AnalogModulationError: LocalizedError, Equatable {
    case carrierOutOfRange(operation: String, carrier: Double, nyquist: Double)
    case instantaneousFrequencyOutOfRange(operation: String, minimum: Double, maximum: Double, nyquist: Double)
    case cutoffOutOfRange(operation: String, cutoff: Double, maximum: Double)
    case insufficientSamples(operation: String)

    var errorDescription: String? {
        switch self {
        case let .carrierOutOfRange(operation, carrier, nyquist):
            "\(operation) carrier \(carrier) Hz must be greater than 0 and below Nyquist (\(nyquist) Hz)"
        case let .instantaneousFrequencyOutOfRange(operation, minimum, maximum, nyquist):
            "\(operation) instantaneous frequency must remain inside 0...Nyquist; received \(minimum)...\(maximum) Hz with Nyquist \(nyquist) Hz"
        case let .cutoffOutOfRange(operation, cutoff, maximum):
            "\(operation) baseband cutoff \(cutoff) Hz must be greater than 0 and below \(maximum) Hz"
        case let .insufficientSamples(operation):
            "\(operation) requires at least two samples"
        }
    }
}

// MARK: - Message normalization

/// Center and peak-normalize the message to −1...1. Constant inputs become zero.
private func normalizedMessage(_ points: [Point]) -> [Double] {
    guard !points.isEmpty else {
        return []
    }
    let mean = averageValue(points)
    let centered = points.map { $0.value - mean }
    let peak = centered.reduce(0.0) { max($0, abs($1)) }
    guard peak > 0, peak.isFinite else {
        return [Double](repeating: 0, count: points.count)
    }
    return centered.map { $0 / peak }
}

private func analogSampleInterval(
    _ provided: Double?,
    points: [Point],
    operation: String,
) throws -> Double {
    guard points.count >= 2 else {
        throw AnalogModulationError.insufficientSamples(operation: operation)
    }
    return try resolveSampleInterval(provided, points: points, operation: operation)
}

private func validateCarrier(
    _ carrier: Double,
    interval: Double,
    operation: String,
) throws -> Double {
    let nyquist = 1 / interval / 2
    guard carrier > 0, carrier < nyquist else {
        throw AnalogModulationError.carrierOutOfRange(
            operation: operation,
            carrier: carrier,
            nyquist: nyquist,
        )
    }
    return nyquist
}

// MARK: - Modulation

func modulateAMPoints(
    _ points: [Point],
    carrier: Double,
    depth: Double,
    amplitude: Double,
    sampleInterval: Double?,
) throws -> [Point] {
    let operation = "AM"
    let interval = try analogSampleInterval(sampleInterval, points: points, operation: operation)
    _ = try validateCarrier(carrier, interval: interval, operation: operation)
    let message = normalizedMessage(points)
    let start = points[0].time
    return points.enumerated().map { index, point in
        let phase = 2 * Double.pi * carrier * (point.time - start)
        let envelope = amplitude * (1 + depth * message[index])
        return Point(time: point.time, value: envelope * cos(phase))
    }
}

func modulateFMPoints(
    _ points: [Point],
    carrier: Double,
    sensitivity: Double,
    amplitude: Double,
    sampleInterval: Double?,
) throws -> [Point] {
    let operation = "FM"
    let interval = try analogSampleInterval(sampleInterval, points: points, operation: operation)
    let nyquist = try validateCarrier(carrier, interval: interval, operation: operation)
    let instantaneousFrequencies = points.map { carrier + sensitivity * $0.value }
    let minimumFrequency = instantaneousFrequencies.min() ?? carrier
    let maximumFrequency = instantaneousFrequencies.max() ?? carrier
    guard minimumFrequency.isFinite,
          maximumFrequency.isFinite,
          minimumFrequency > 0,
          maximumFrequency < nyquist else {
        throw AnalogModulationError.instantaneousFrequencyOutOfRange(
            operation: operation,
            minimum: minimumFrequency,
            maximum: maximumFrequency,
            nyquist: nyquist,
        )
    }

    var output = points
    var phase = 0.0
    output[0].value = amplitude
    for index in 1 ..< output.count {
        let dt = points[index].time - points[index - 1].time
        guard dt > 0, dt.isFinite else {
            output[index].value = amplitude * cos(phase)
            continue
        }
        let averageValue = 0.5 * (points[index - 1].value + points[index].value)
        let instantaneousFrequency = carrier + sensitivity * averageValue
        phase += 2 * Double.pi * instantaneousFrequency * dt
        output[index].value = amplitude * cos(phase)
    }
    return output
}

func modulatePMPoints(
    _ points: [Point],
    carrier: Double,
    sensitivity: Double,
    amplitude: Double,
    sampleInterval: Double?,
) throws -> [Point] {
    let operation = "PM"
    let interval = try analogSampleInterval(sampleInterval, points: points, operation: operation)
    _ = try validateCarrier(carrier, interval: interval, operation: operation)
    let start = points[0].time
    return points.enumerated().map { index, point in
        let carrierPhase = 2 * Double.pi * carrier * (point.time - start)
        let phase = carrierPhase + sensitivity * points[index].value
        return Point(time: point.time, value: amplitude * cos(phase))
    }
}

// MARK: - Coherent quadrature demodulation

private func quadratureBaseband(
    _ points: [Point],
    carrier: Double,
    cutoff: Double,
    sampleInterval: Double?,
    operation: String,
) throws -> (inPhase: [Point], quadrature: [Point]) {
    let interval = try analogSampleInterval(sampleInterval, points: points, operation: operation)
    let nyquist = try validateCarrier(carrier, interval: interval, operation: operation)
    let maximumCutoff = min(carrier, nyquist - carrier)
    guard cutoff > 0, cutoff < maximumCutoff else {
        throw AnalogModulationError.cutoffOutOfRange(
            operation: operation,
            cutoff: cutoff,
            maximum: maximumCutoff,
        )
    }

    let start = points[0].time
    var inPhase = points
    var quadrature = points
    for index in points.indices {
        let phase = 2 * Double.pi * carrier * (points[index].time - start)
        inPhase[index].value = 2 * points[index].value * cos(phase)
        quadrature[index].value = -2 * points[index].value * sin(phase)
    }

    let design = try designFIRFilter(
        kind: .lowPass(cutoff: cutoff),
        sampleRate: 1 / interval,
        sampleCount: points.count,
    )
    return (
        applyFIRFilter(taps: design.taps, to: inPhase),
        applyFIRFilter(taps: design.taps, to: quadrature),
    )
}

private func unwrappedPhase(inPhase: [Point], quadrature: [Point]) -> [Double] {
    guard inPhase.count == quadrature.count, !inPhase.isEmpty else {
        return []
    }
    var result = [Double](repeating: 0, count: inPhase.count)
    var previousWrapped = atan2(quadrature[0].value, inPhase[0].value)
    result[0] = previousWrapped
    for index in 1 ..< result.count {
        let wrapped = atan2(quadrature[index].value, inPhase[index].value)
        var delta = wrapped - previousWrapped
        while delta > Double.pi {
            delta -= 2 * Double.pi
        }
        while delta < -Double.pi {
            delta += 2 * Double.pi
        }
        result[index] = result[index - 1] + delta
        previousWrapped = wrapped
    }
    return result
}

func demodulateAMPoints(
    _ points: [Point],
    carrier: Double,
    depth: Double,
    cutoff: Double,
    sampleInterval: Double?,
) throws -> [Point] {
    let baseband = try quadratureBaseband(
        points,
        carrier: carrier,
        cutoff: cutoff,
        sampleInterval: sampleInterval,
        operation: "DemodAM",
    )
    let envelope = zip(baseband.inPhase, baseband.quadrature).map { hypot($0.value, $1.value) }
    let carrierAmplitude = envelope.reduce(0, +) / Double(envelope.count)
    guard carrierAmplitude > 0, carrierAmplitude.isFinite else {
        return points.map { Point(time: $0.time, value: 0) }
    }
    return points.enumerated().map { index, point in
        Point(time: point.time, value: (envelope[index] / carrierAmplitude - 1) / depth)
    }
}

func demodulateFMPoints(
    _ points: [Point],
    carrier: Double,
    sensitivity: Double,
    cutoff: Double,
    sampleInterval: Double?,
) throws -> [Point] {
    let baseband = try quadratureBaseband(
        points,
        carrier: carrier,
        cutoff: cutoff,
        sampleInterval: sampleInterval,
        operation: "DemodFM",
    )
    let phase = unwrappedPhase(inPhase: baseband.inPhase, quadrature: baseband.quadrature)
    var recovered = [Double](repeating: 0, count: points.count)
    for index in 1 ..< points.count {
        let dt = points[index].time - points[index - 1].time
        guard dt > 0, dt.isFinite else {
            recovered[index] = recovered[index - 1]
            continue
        }
        recovered[index] = (phase[index] - phase[index - 1]) / (2 * Double.pi * dt * sensitivity)
    }
    if recovered.count > 1 {
        recovered[0] = recovered[1]
    }
    return points.enumerated().map { Point(time: $0.element.time, value: recovered[$0.offset]) }
}

func demodulatePMPoints(
    _ points: [Point],
    carrier: Double,
    sensitivity: Double,
    cutoff: Double,
    sampleInterval: Double?,
) throws -> [Point] {
    let baseband = try quadratureBaseband(
        points,
        carrier: carrier,
        cutoff: cutoff,
        sampleInterval: sampleInterval,
        operation: "DemodPM",
    )
    let phase = unwrappedPhase(
        inPhase: baseband.inPhase,
        quadrature: baseband.quadrature,
    )
    return points.enumerated().map { Point(time: $0.element.time, value: phase[$0.offset] / sensitivity) }
}
