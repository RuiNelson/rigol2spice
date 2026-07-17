import Foundation

// MARK: - FIRFilterKind

enum FIRFilterKind: Equatable {
    case lowPass(cutoff: Double)
    case highPass(cutoff: Double)
    case bandPass(low: Double, high: Double)
    case bandStop(low: Double, high: Double)

    var operationName: String {
        switch self {
        case .lowPass: "LowPass"
        case .highPass: "HighPass"
        case .bandPass: "BandPass"
        case .bandStop: "BandStop"
        }
    }
}

// MARK: - FIRFilterDesign

struct FIRFilterDesign: Equatable {
    let kind: FIRFilterKind
    let sampleRate: Double
    let taps: [Double]

    var tapCount: Int {
        taps.count
    }

    var groupDelaySamples: Int {
        (taps.count - 1) / 2
    }

    var groupDelaySeconds: Double {
        Double(groupDelaySamples) / sampleRate
    }
}

// MARK: - FIRFilterError

enum FIRFilterError: LocalizedError, Equatable {
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

// MARK: - BlackmanHarris

/// Blackman–Harris 4-term coefficients (symmetric, non-periodic form).
private enum BlackmanHarris {
    static let a0 = 0.35875
    static let a1 = 0.48829
    static let a2 = 0.14128
    static let a3 = 0.01168

    /// Approximate main-lobe / transition width in cycles/sample: ≈ 6 / N.
    static let transitionWidthFactor = 6.0
}

private let minimumTapCount = 63
private let absoluteMaximumTapCount = 4095

func designFIRFilter(
    kind: FIRFilterKind,
    sampleRate: Double,
    sampleCount: Int,
) throws -> FIRFilterDesign {
    let operation = kind.operationName
    guard sampleRate.isFinite, sampleRate > 0 else {
        throw FIRFilterError.invalidSampleInterval(operation: operation, value: sampleRate)
    }
    guard sampleCount >= 2 else {
        throw FIRFilterError.insufficientSamples(operation: operation, samples: sampleCount, minimum: 2)
    }

    let nyquist = sampleRate / 2
    let edges: IdealFilterEdges

    switch kind {
    case let .lowPass(cutoff):
        try validateCutoff(cutoff, nyquist: nyquist, operation: operation)
        edges = .lowPass(cutoff / sampleRate)
    case let .highPass(cutoff):
        try validateCutoff(cutoff, nyquist: nyquist, operation: operation)
        edges = .highPass(cutoff / sampleRate)
    case let .bandPass(low, high):
        try validateBand(low: low, high: high, nyquist: nyquist, operation: operation)
        edges = .bandPass(low: low / sampleRate, high: high / sampleRate)
    case let .bandStop(low, high):
        try validateBand(low: low, high: high, nyquist: nyquist, operation: operation)
        edges = .bandStop(low: low / sampleRate, high: high / sampleRate)
    }

    let taps = makeWindowedSincTaps(
        edges: edges,
        sampleRate: sampleRate,
        sampleCount: sampleCount,
    )
    return FIRFilterDesign(kind: kind, sampleRate: sampleRate, taps: taps)
}

func resolveSampleInterval(_ provided: Double?, points: [Point], operation: String) throws -> Double {
    if let provided {
        guard provided.isFinite, provided > 0 else {
            throw FIRFilterError.invalidSampleInterval(operation: operation, value: provided)
        }
        return provided
    }

    guard points.count >= 2 else {
        throw FIRFilterError.sampleIntervalRequired(operation: operation)
    }

    let inferred = points[1].time - points[0].time
    guard inferred.isFinite, inferred > 0 else {
        throw FIRFilterError.sampleIntervalRequired(operation: operation)
    }
    return inferred
}

func applyFIRFilter(taps: [Double], to points: [Point]) -> [Point] {
    let count = points.count
    guard count > 0, taps.count >= 1 else {
        return points
    }

    let delay = (taps.count - 1) / 2
    var values = [Double](repeating: 0, count: count)
    for index in 0 ..< count {
        values[index] = points[index].value
    }

    var output = points
    output.withUnsafeMutableBufferPointer { buffer in
        taps.withUnsafeBufferPointer { tapBuffer in
            values.withUnsafeBufferPointer { valueBuffer in
                for outputIndex in 0 ..< count {
                    var sum = 0.0
                    for tapIndex in 0 ..< tapBuffer.count {
                        let inputIndex = outputIndex + delay - tapIndex
                        let sampleIndex = reflectedIndex(inputIndex, count: count)
                        sum += tapBuffer[tapIndex] * valueBuffer[sampleIndex]
                    }
                    buffer[outputIndex].value = sum
                }
            }
        }
    }
    return output
}

// MARK: - IdealFilterEdges

private enum IdealFilterEdges {
    case lowPass(Double)
    case highPass(Double)
    case bandPass(low: Double, high: Double)
    case bandStop(low: Double, high: Double)
}

private func validateCutoff(_ frequency: Double, nyquist: Double, operation: String) throws {
    guard frequency.isFinite, frequency > 0, frequency < nyquist else {
        throw FIRFilterError.frequencyOutOfRange(
            operation: operation,
            frequency: frequency,
            nyquist: nyquist,
        )
    }
}

private func validateBand(low: Double, high: Double, nyquist: Double, operation: String) throws {
    guard low.isFinite, high.isFinite, low > 0, high < nyquist, low < high else {
        throw FIRFilterError.invalidFrequencyBand(operation: operation, low: low, high: high)
    }
}

private func makeWindowedSincTaps(
    edges: IdealFilterEdges,
    sampleRate: Double,
    sampleCount: Int,
) -> [Double] {
    let tapCount = chooseTapCount(edges: edges, sampleRate: sampleRate, sampleCount: sampleCount)
    var taps = idealSincKernel(edges: edges, tapCount: tapCount)
    applyBlackmanHarrisWindow(&taps)
    normalizePassbandGain(&taps, edges: edges)
    return taps
}

private func chooseTapCount(edges: IdealFilterEdges, sampleRate: Double, sampleCount: Int) -> Int {
    let nyquist = sampleRate / 2
    let transitionHz: Double

    switch edges {
    case let .lowPass(normalized):
        let cutoff = normalized * sampleRate
        let margin = min(cutoff, nyquist - cutoff)
        transitionHz = max(0.1 * margin, sampleRate * 1e-4)
    case let .highPass(normalized):
        let cutoff = normalized * sampleRate
        let margin = min(cutoff, nyquist - cutoff)
        transitionHz = max(0.1 * margin, sampleRate * 1e-4)
    case let .bandPass(lowNorm, highNorm),
         let .bandStop(lowNorm, highNorm):
        let low = lowNorm * sampleRate
        let high = highNorm * sampleRate
        let margin = min(low, high - low, nyquist - high)
        transitionHz = max(0.1 * margin, sampleRate * 1e-4)
    }

    let raw = BlackmanHarris.transitionWidthFactor * sampleRate / transitionHz
    let maximumForCapture = max(minimumTapCount, (sampleCount / 4) | 1)
    let upper = min(absoluteMaximumTapCount, maximumForCapture)
    var tapCount = Int(raw.rounded(.up))
    if tapCount % 2 == 0 {
        tapCount += 1
    }
    tapCount = min(max(tapCount, minimumTapCount), upper)
    if tapCount % 2 == 0 {
        tapCount -= 1
    }
    return max(tapCount, 3)
}

private func idealSincKernel(edges: IdealFilterEdges, tapCount: Int) -> [Double] {
    let mid = (tapCount - 1) / 2
    var taps = [Double](repeating: 0, count: tapCount)

    func lowPassKernel(normalizedCutoff: Double) -> [Double] {
        var kernel = [Double](repeating: 0, count: tapCount)
        for n in 0 ..< tapCount {
            let k = Double(n - mid)
            if k == 0 {
                kernel[n] = 2 * normalizedCutoff
            }
            else {
                kernel[n] = sin(2 * Double.pi * normalizedCutoff * k) / (Double.pi * k)
            }
        }
        return kernel
    }

    switch edges {
    case let .lowPass(fc):
        taps = lowPassKernel(normalizedCutoff: fc)

    case let .highPass(fc):
        taps = lowPassKernel(normalizedCutoff: fc)
        for n in 0 ..< tapCount {
            taps[n] = -taps[n]
        }
        taps[mid] += 1

    case let .bandPass(low, high):
        let highKernel = lowPassKernel(normalizedCutoff: high)
        let lowKernel = lowPassKernel(normalizedCutoff: low)
        for n in 0 ..< tapCount {
            taps[n] = highKernel[n] - lowKernel[n]
        }

    case let .bandStop(low, high):
        let highKernel = lowPassKernel(normalizedCutoff: high)
        let lowKernel = lowPassKernel(normalizedCutoff: low)
        for n in 0 ..< tapCount {
            taps[n] = lowKernel[n] - highKernel[n]
        }
        taps[mid] += 1
    }

    return taps
}

private func applyBlackmanHarrisWindow(_ taps: inout [Double]) {
    let count = taps.count
    guard count > 1 else {
        return
    }

    let denominator = Double(count - 1)
    for n in 0 ..< count {
        let phase = 2 * Double.pi * Double(n) / denominator
        let window =
            BlackmanHarris.a0
                - BlackmanHarris.a1 * cos(phase)
                + BlackmanHarris.a2 * cos(2 * phase)
                - BlackmanHarris.a3 * cos(3 * phase)
        taps[n] *= window
    }
}

private func normalizePassbandGain(_ taps: inout [Double], edges: IdealFilterEdges) {
    let referenceFrequency: Double
    switch edges {
    case let .lowPass(fc):
        referenceFrequency = 0
        _ = fc
    case let .highPass(fc):
        // Near Nyquist, safely below 0.5.
        referenceFrequency = min(0.49, fc + (0.5 - fc) * 0.5)
    case let .bandPass(low, high):
        referenceFrequency = (low + high) / 2
    case .bandStop:
        referenceFrequency = 0
    }

    let gain = frequencyResponseMagnitude(taps: taps, normalizedFrequency: referenceFrequency)
    guard gain > 1e-18 else {
        return
    }

    let scale = 1 / gain
    for index in taps.indices {
        taps[index] *= scale
    }
}

private func frequencyResponseMagnitude(taps: [Double], normalizedFrequency: Double) -> Double {
    var real = 0.0
    var imaginary = 0.0
    let omega = 2 * Double.pi * normalizedFrequency
    for (index, tap) in taps.enumerated() {
        let angle = omega * Double(index)
        real += tap * cos(angle)
        imaginary -= tap * sin(angle)
    }
    return (real * real + imaginary * imaginary).squareRoot()
}

/// Numpy-style `reflect` indexing (edge sample is not duplicated).
private func reflectedIndex(_ index: Int, count: Int) -> Int {
    if count <= 1 {
        return 0
    }
    if index >= 0, index < count {
        return index
    }

    let period = 2 * (count - 1)
    var wrapped = index % period
    if wrapped < 0 {
        wrapped += period
    }
    if wrapped >= count {
        return period - wrapped
    }
    return wrapped
}
