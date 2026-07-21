import Foundation

// MARK: - DigitalFilterKind

enum DigitalFilterKind: Equatable {
    case lowPass(cutoff: Double)
    case highPass(cutoff: Double)
    case bandPass(low: Double, high: Double)
    case bandStop(low: Double, high: Double)
    case notch(center: Double, width: Double)

    var operationName: String {
        switch self {
        case .lowPass: "LowPass"
        case .highPass: "HighPass"
        case .bandPass: "BandPass"
        case .bandStop: "BandStop"
        case .notch: "Notch"
        }
    }
}

// MARK: - Biquad

struct Biquad: Equatable {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double

    var maximumPoleRadius: Double {
        let discriminant = a1 * a1 - 4 * a2
        if discriminant < 0 {
            return sqrt(max(a2, 0))
        }
        let root = sqrt(discriminant)
        return max(abs((-a1 + root) / 2), abs((-a1 - root) / 2))
    }
}

// MARK: - DigitalFilterDesign

struct DigitalFilterDesign: Equatable {
    let kind: DigitalFilterKind
    let sampleRate: Double
    /// Cascaded sections in each parallel signal path. Most filters have one path;
    /// band rejection sums an independent low-pass and high-pass path.
    let branches: [[Biquad]]

    var sections: [Biquad] {
        branches.flatMap(\.self)
    }

    var settlingTime: Double {
        let radius = sections.map(\.maximumPoleRadius).max() ?? 0
        return 3 / (max(1 - radius, Double.leastNonzeroMagnitude) * sampleRate)
    }
}

// MARK: - DigitalFilterError

enum DigitalFilterError: LocalizedError, Equatable {
    case sampleIntervalRequired(operation: String)
    case invalidSampleInterval(operation: String, value: Double)
    case frequencyOutOfRange(operation: String, frequency: Double, nyquist: Double)
    case invalidFrequencyBand(operation: String, low: Double, high: Double)
    case insufficientSamples(operation: String, samples: Int, minimum: Int)

    var errorDescription: String? {
        switch self {
        case let .sampleIntervalRequired(operation):
            "\(operation) requires a regular sample interval"
        case let .invalidSampleInterval(operation, value):
            "\(operation) requires a positive sample interval, but received \(value)"
        case let .frequencyOutOfRange(operation, frequency, nyquist):
            "\(operation) frequency \(frequency) Hz must be greater than 0 and less than Nyquist (\(nyquist) Hz)"
        case let .invalidFrequencyBand(operation, low, high):
            "\(operation) requires 0 < f1 < f2 < Nyquist, but received \(low) Hz and \(high) Hz"
        case let .insufficientSamples(operation, samples, minimum):
            "\(operation) needs at least \(minimum) samples, but received \(samples)"
        }
    }
}

/// High offline-processing order. Forward/reverse application squares the magnitude response,
/// giving an effective 32nd-order roll-off while the SOS cascade remains numerically stable.
private let butterworthOrder = 16
private let zeroPhaseEdgeCorrection = pow(sqrt(2) - 1, 1 / Double(2 * butterworthOrder))
private let notchSectionCount = 8
private let zeroPhaseNotchWidthCorrection = sqrt(pow(2, 1 / Double(2 * notchSectionCount)) - 1)

func designDigitalFilter(
    kind: DigitalFilterKind,
    sampleRate: Double,
    sampleCount: Int,
) throws -> DigitalFilterDesign {
    let operation = kind.operationName
    guard sampleRate.isFinite, sampleRate > 0 else {
        throw DigitalFilterError.invalidSampleInterval(operation: operation, value: sampleRate)
    }
    guard sampleCount >= 2 else {
        throw DigitalFilterError.insufficientSamples(operation: operation, samples: sampleCount, minimum: 2)
    }

    let nyquist = sampleRate / 2
    let branches: [[Biquad]]
    switch kind {
    case let .lowPass(cutoff):
        try validateCutoff(cutoff, nyquist: nyquist, operation: operation)
        branches = [butterworthSections(
            cutoff: correctedCutoff(cutoff, sampleRate: sampleRate, lowPass: true),
            sampleRate: sampleRate,
            lowPass: true,
        )]
    case let .highPass(cutoff):
        try validateCutoff(cutoff, nyquist: nyquist, operation: operation)
        branches = [butterworthSections(
            cutoff: correctedCutoff(cutoff, sampleRate: sampleRate, lowPass: false),
            sampleRate: sampleRate,
            lowPass: false,
        )]
    case let .bandPass(low, high):
        try validateBand(low: low, high: high, nyquist: nyquist, operation: operation)
        branches = [butterworthSections(
            cutoff: correctedCutoff(low, sampleRate: sampleRate, lowPass: false),
            sampleRate: sampleRate,
            lowPass: false,
        ) + butterworthSections(
            cutoff: correctedCutoff(high, sampleRate: sampleRate, lowPass: true),
            sampleRate: sampleRate,
            lowPass: true,
        )]
    case let .bandStop(low, high):
        try validateBand(low: low, high: high, nyquist: nyquist, operation: operation)
        branches = bandRejectBranches(low: low, high: high, sampleRate: sampleRate)
    case let .notch(center, width):
        let low = center - width / 2
        let high = center + width / 2
        try validateBand(low: low, high: high, nyquist: nyquist, operation: operation)
        let section = notchSection(center: center, width: width, sampleRate: sampleRate)
        branches = [Array(repeating: section, count: notchSectionCount)]
    }

    return DigitalFilterDesign(kind: kind, sampleRate: sampleRate, branches: branches)
}

func resolveSampleInterval(_ provided: Double?, points: [Point], operation: String) throws -> Double {
    if let provided {
        guard provided.isFinite, provided > 0 else {
            throw DigitalFilterError.invalidSampleInterval(operation: operation, value: provided)
        }
        return provided
    }

    guard let inferred = inferredSampleInterval(from: points) else {
        throw DigitalFilterError.sampleIntervalRequired(operation: operation)
    }
    return inferred
}

func inferredSampleInterval(from points: [Point]) -> Double? {
    guard points.count >= 2 else {
        return nil
    }
    let interval = points[1].time - points[0].time
    guard interval.isFinite, interval > 0 else {
        return nil
    }
    return interval
}

func applyZeroPhaseFilter(_ design: DigitalFilterDesign, to points: [Point]) -> [Point] {
    guard points.count >= 3, !design.branches.isEmpty else {
        return points
    }

    let values = points.map(\.value)
    let filteredBranches = design.branches.map { sections in
        applyZeroPhaseCascade(sections, to: values)
    }

    var output = points
    for index in output.indices {
        output[index].value = filteredBranches.reduce(0) { $0 + $1[index] }
    }
    return output
}

private func applyZeroPhaseCascade(_ sections: [Biquad], to values: [Double]) -> [Double] {
    let maximumPadding = values.count - 1
    let radius = sections.map(\.maximumPoleRadius).max() ?? 0
    let decay = 3 / max(1 - radius, Double.leastNonzeroMagnitude)
    let padding = if !decay.isFinite || decay >= Double(maximumPadding) {
        maximumPadding
    }
    else {
        min(maximumPadding, max(12, Int(decay.rounded(.up))))
    }
    var extended = oddReflectionPadding(values, count: padding)

    extended = applyCascade(sections, to: extended)
    extended.reverse()
    extended = applyCascade(sections.reversed(), to: extended)
    extended.reverse()
    return Array(extended[padding ..< padding + values.count])
}

private func validateCutoff(_ frequency: Double, nyquist: Double, operation: String) throws {
    guard frequency.isFinite, frequency > 0, frequency < nyquist else {
        throw DigitalFilterError.frequencyOutOfRange(
            operation: operation,
            frequency: frequency,
            nyquist: nyquist,
        )
    }
}

private func validateBand(low: Double, high: Double, nyquist: Double, operation: String) throws {
    guard low.isFinite, high.isFinite, low > 0, high < nyquist, low < high else {
        throw DigitalFilterError.invalidFrequencyBand(operation: operation, low: low, high: high)
    }
}

private func correctedCutoff(_ cutoff: Double, sampleRate: Double, lowPass: Bool) -> Double {
    let warped = tan(Double.pi * cutoff / sampleRate)
    let corrected = lowPass
        ? warped / zeroPhaseEdgeCorrection
        : warped * zeroPhaseEdgeCorrection
    return atan(corrected) * sampleRate / Double.pi
}

private func butterworthSections(cutoff: Double, sampleRate: Double, lowPass: Bool) -> [Biquad] {
    (0 ..< butterworthOrder / 2).map { index in
        let angle = Double(2 * index + 1) * Double.pi / Double(2 * butterworthOrder)
        let quality = 1 / (2 * cos(angle))
        return lowHighPassSection(
            cutoff: cutoff,
            sampleRate: sampleRate,
            quality: quality,
            lowPass: lowPass,
        )
    }
}

private func lowHighPassSection(
    cutoff: Double,
    sampleRate: Double,
    quality: Double,
    lowPass: Bool,
) -> Biquad {
    let omega = 2 * Double.pi * cutoff / sampleRate
    let cosine = cos(omega)
    let alpha = sin(omega) / (2 * quality)
    let a0 = 1 + alpha
    let b0 = (lowPass ? 1 - cosine : 1 + cosine) / 2
    let b1 = lowPass ? 1 - cosine : -(1 + cosine)
    let b2 = b0
    return Biquad(
        b0: b0 / a0,
        b1: b1 / a0,
        b2: b2 / a0,
        a1: -2 * cosine / a0,
        a2: (1 - alpha) / a0,
    )
}

private func bandRejectBranches(low: Double, high: Double, sampleRate: Double) -> [[Biquad]] {
    [
        butterworthSections(
            cutoff: correctedCutoff(low, sampleRate: sampleRate, lowPass: true),
            sampleRate: sampleRate,
            lowPass: true,
        ),
        butterworthSections(
            cutoff: correctedCutoff(high, sampleRate: sampleRate, lowPass: false),
            sampleRate: sampleRate,
            lowPass: false,
        ),
    ]
}

private func notchSection(center: Double, width: Double, sampleRate: Double) -> Biquad {
    let omega = 2 * Double.pi * center / sampleRate
    let cosine = cos(omega)
    let radius = exp(-Double.pi * width * zeroPhaseNotchWidthCorrection / sampleRate)
    var b0 = 1.0
    var b1 = -2 * cosine
    var b2 = 1.0
    let a1 = -2 * radius * cosine
    let a2 = radius * radius

    let numeratorAtDC = b0 + b1 + b2
    let denominatorAtDC = 1 + a1 + a2
    if abs(numeratorAtDC) > 1e-18 {
        let scale = denominatorAtDC / numeratorAtDC
        b0 *= scale
        b1 *= scale
        b2 *= scale
    }
    return Biquad(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
}

private func oddReflectionPadding(_ values: [Double], count: Int) -> [Double] {
    guard count > 0 else {
        return values
    }

    var result: [Double] = []
    result.reserveCapacity(values.count + 2 * count)
    let first = values[0]
    for index in stride(from: count, through: 1, by: -1) {
        result.append(2 * first - values[index])
    }
    result.append(contentsOf: values)
    let last = values[values.count - 1]
    for index in stride(from: values.count - 2, through: values.count - count - 1, by: -1) {
        result.append(2 * last - values[index])
    }
    return result
}

private func applyCascade(_ sections: some Sequence<Biquad>, to values: [Double]) -> [Double] {
    sections.reduce(values) { result, section in
        applyBiquad(section, to: result)
    }
}

private func applyBiquad(_ section: Biquad, to values: [Double]) -> [Double] {
    guard let first = values.first else {
        return values
    }

    let denominatorAtDC = 1 + section.a1 + section.a2
    let numeratorAtDC = section.b0 + section.b1 + section.b2
    let steadyOutput = abs(denominatorAtDC) > 1e-18
        ? first * numeratorAtDC / denominatorAtDC
        : 0
    var state1 = steadyOutput - section.b0 * first
    var state2 = section.b2 * first - section.a2 * steadyOutput
    var output = [Double](repeating: 0, count: values.count)

    for index in values.indices {
        let input = values[index]
        let value = section.b0 * input + state1
        state1 = section.b1 * input - section.a1 * value + state2
        state2 = section.b2 * input - section.a2 * value
        output[index] = value
    }
    return output
}
