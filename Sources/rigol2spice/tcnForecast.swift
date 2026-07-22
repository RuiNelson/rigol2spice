import Foundation

// MARK: - TCNForecastError

enum TCNForecastError: LocalizedError, Equatable {
    case notEnoughSamples(actual: Int, minimum: Int)
    case nonFiniteSample(index: Int)
    case nonUniformSampling(index: Int)
    case pointCountTooLarge(duration: Double)

    var errorDescription: String? {
        switch self {
        case let .notEnoughSamples(actual, minimum):
            "Forecast requires at least \(minimum) samples, but received \(actual)"
        case let .nonFiniteSample(index):
            "Forecast requires finite timestamps and values; sample \(index) is not finite"
        case let .nonUniformSampling(index):
            "Forecast requires uniformly spaced samples; sample \(index) is off the sampling grid. Add ResampleF before Forecast"
        case let .pointCountTooLarge(duration):
            "Forecast duration \(duration) would create too many samples"
        }
    }
}

private let tcnMinimumSampleCount = 8
private let tcnMaximumLocalContext = 32
private let tcnMaximumTrainingRows = 8192
let tcnMaximumForecastSamples = 10_000_000

// MARK: - TCNForecastMethod

enum TCNForecastMethod: Equatable {
    case temporalConvolution
    case seasonal(period: Int)
    case linearTrend
    case mean
    case holdLast

    var displayName: String {
        switch self {
        case .temporalConvolution: "causal temporal convolution"
        case let .seasonal(period): "repeating pattern (\(period)-sample period)"
        case .linearTrend: "linear trend"
        case .mean: "stable mean"
        case .holdLast: "hold last value"
        }
    }
}

// MARK: - TCNForecastResult

struct TCNForecastResult {
    let points: [Point]
    let method: TCNForecastMethod
    /// Validation quality from 0 (unpredictable) to 1 (near-perfect reconstruction).
    let confidence: Double
}

/// Append a forecast from a compact, single-channel causal temporal convolutional network.
///
/// The network is an autoregressive causal Conv1D layer. Its kernel and bias are fitted to
/// the tail of the capture with ridge regression, then evaluated recursively. Standardizing
/// the signal makes the fixed regularization useful across engineering scales.
func tcnForecastPoints(
    _ points: [Point],
    duration: Double,
    sampleCount requestedSampleCount: Int? = nil,
    sampleInterval providedSampleInterval: Double? = nil,
) throws -> [Point] {
    try tcnForecast(
        points,
        duration: duration,
        sampleCount: requestedSampleCount,
        sampleInterval: providedSampleInterval,
    ).points
}

func tcnForecast(
    _ points: [Point],
    duration: Double,
    sampleCount requestedSampleCount: Int? = nil,
    sampleInterval providedSampleInterval: Double? = nil,
) throws -> TCNForecastResult {
    guard points.count >= tcnMinimumSampleCount else {
        throw TCNForecastError.notEnoughSamples(actual: points.count, minimum: tcnMinimumSampleCount)
    }

    for (index, point) in points.enumerated() where !point.time.isFinite || !point.value.isFinite {
        throw TCNForecastError.nonFiniteSample(index: index)
    }

    let sampleInterval = try resolveSampleInterval(
        providedSampleInterval,
        points: points,
        operation: "Forecast",
    )
    try validateTCNSampling(points, sampleInterval: sampleInterval)

    let forecastRatio = duration / sampleInterval
    let nearestForecastCount = forecastRatio.rounded()
    let ratioTolerance = max(1, abs(forecastRatio)) * 1e-12
    let rawForecastCount = abs(forecastRatio - nearestForecastCount) <= ratioTolerance
        ? nearestForecastCount
        : ceil(forecastRatio)
    guard rawForecastCount.isFinite,
          rawForecastCount > 0,
          rawForecastCount <= Double(tcnMaximumForecastSamples),
          rawForecastCount <= Double(Int.max),
          points.count <= Int.max - Int(rawForecastCount) else {
        throw TCNForecastError.pointCountTooLarge(duration: duration)
    }
    let forecastCount = Int(rawForecastCount)
    if let requestedSampleCount {
        guard requestedSampleCount > 0,
              requestedSampleCount <= tcnMaximumForecastSamples,
              points.count <= Int.max - requestedSampleCount else {
            throw TCNForecastError.pointCountTooLarge(duration: duration)
        }
    }

    let values = points.map(\.value)
    let selection = selectTCNForecastMethod(values: values, requestedHorizon: forecastCount)
    let method = resolvedTCNMethod(selection.method, values: values)
    let forecast = forecastValues(values, count: forecastCount, method: method)
    let nativeForecast = appendTCNForecast(
        to: points,
        values: forecast,
        sampleInterval: sampleInterval,
    )
    let output = resampleTCNForecastIfNeeded(
        nativeForecast,
        originalCount: points.count,
        duration: duration,
        sampleCount: requestedSampleCount,
        sampleInterval: sampleInterval,
    )
    return TCNForecastResult(
        points: output,
        method: method,
        confidence: selection.confidence,
    )
}

private func selectTCNForecastMethod(
    values: [Double],
    requestedHorizon: Int,
) -> (method: TCNForecastMethod, confidence: Double) {
    guard values.count >= 24 else {
        return (.temporalConvolution, 0)
    }
    let validationCount = min(max(8, values.count / 5), min(values.count / 3, requestedHorizon))
    guard validationCount >= 4 else {
        return (.temporalConvolution, 0)
    }

    let training = Array(values.dropLast(validationCount))
    let expected = Array(values.suffix(validationCount))
    var methods: [TCNForecastMethod] = [.holdLast, .mean, .linearTrend]
    if let period = detectedTCNPeriod(values: training) {
        methods.append(.seasonal(period: period))
    }
    methods.append(.temporalConvolution)

    var bestMethod = methods[0]
    var bestError = meanAbsoluteError(
        forecastValues(training, count: validationCount, method: bestMethod),
        expected,
    )
    for method in methods.dropFirst() {
        let error = meanAbsoluteError(
            forecastValues(training, count: validationCount, method: method),
            expected,
        )
        // Prefer the simpler earlier method unless the alternative is materially better.
        if error < bestError * 0.98 {
            bestMethod = method
            bestError = error
        }
    }

    let expectedMean = expected.reduce(0, +) / Double(expected.count)
    let expectedScale = sqrt(expected.reduce(0) { $0 + pow($1 - expectedMean, 2) } / Double(expected.count))
    var normalizedError = bestError / max(expectedScale, 1e-12)
    if normalizedError > 0.8, bestMethod != .holdLast, bestMethod != .mean {
        let holdError = meanAbsoluteError(
            forecastValues(training, count: validationCount, method: .holdLast),
            expected,
        )
        let meanError = meanAbsoluteError(
            forecastValues(training, count: validationCount, method: .mean),
            expected,
        )
        if meanError < holdError * 0.98 {
            bestMethod = .mean
            bestError = meanError
        }
        else {
            bestMethod = .holdLast
            bestError = holdError
        }
        normalizedError = bestError / max(expectedScale, 1e-12)
    }
    return (bestMethod, max(0, min(1, 1 - normalizedError)))
}

private func forecastValues(_ values: [Double], count: Int, method: TCNForecastMethod) -> [Double] {
    switch method {
    case .temporalConvolution:
        temporalConvolutionForecast(values, count: count)
    case let .seasonal(period):
        seasonalForecast(values, count: count, period: period)
    case .linearTrend:
        trendForecast(values, count: count)
    case .mean:
        Array(repeating: values.reduce(0, +) / Double(values.count), count: count)
    case .holdLast:
        Array(repeating: values.last ?? 0, count: count)
    }
}

private func temporalConvolutionForecast(_ values: [Double], count: Int) -> [Double] {
    let trend = fittedTCNTrend(values)
    let residuals = values.enumerated().map { index, value in value - trend.value(at: index) }
    let variance = residuals.reduce(0) { $0 + $1 * $1 } / Double(residuals.count)
    let scale = sqrt(variance)
    if !scale.isFinite || scale <= max(1, values.map(abs).max() ?? 0) * 1e-12 {
        return (0 ..< count).map { trend.value(at: values.count + $0) }
    }

    var normalized = residuals.map { $0 / scale }
    let lags = tcnCausalLags(values: normalized)
    let coefficients = fitCausalConvolution(values: normalized, lags: lags)
    let observedMinimum = normalized.min() ?? -1
    let observedMaximum = normalized.max() ?? 1
    let observedRange = max(observedMaximum - observedMinimum, 1)
    let lowerBound = observedMinimum - 2 * observedRange
    let upperBound = observedMaximum + 2 * observedRange
    var output: [Double] = []
    output.reserveCapacity(count)
    for offset in 0 ..< count {
        var prediction = coefficients[0]
        for (coefficientIndex, lag) in lags.enumerated() {
            prediction += coefficients[coefficientIndex + 1] * normalized[normalized.count - lag]
        }
        prediction = min(upperBound, max(lowerBound, prediction))
        normalized.append(prediction)
        output.append(trend.value(at: values.count + offset) + prediction * scale)
    }
    return output
}

private func seasonalForecast(_ values: [Double], count: Int, period: Int) -> [Double] {
    guard period > 0, period <= values.count else {
        return Array(repeating: values.last ?? 0, count: count)
    }
    var history = values
    var output: [Double] = []
    output.reserveCapacity(count)
    for _ in 0 ..< count {
        let value = history[history.count - period]
        history.append(value)
        output.append(value)
    }
    return output
}

private func trendForecast(_ values: [Double], count: Int) -> [Double] {
    let trend = fittedTCNTrend(values)
    return (0 ..< count).map { trend.value(at: values.count + $0) }
}

private func meanAbsoluteError(_ predicted: [Double], _ expected: [Double]) -> Double {
    zip(predicted, expected).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(expected.count)
}

private func resolvedTCNMethod(_ method: TCNForecastMethod, values: [Double]) -> TCNForecastMethod {
    if case .seasonal = method, let period = detectedTCNPeriod(values: values) {
        return .seasonal(period: period)
    }
    return method
}

// MARK: - TCNTrend

private struct TCNTrend {
    let intercept: Double
    let slope: Double

    func value(at index: Int) -> Double {
        intercept + slope * Double(index)
    }
}

/// Keep a linear trend only when it is materially larger than the temporal residual.
/// This avoids interpreting a partial cycle of an otherwise stationary waveform as drift.
private func fittedTCNTrend(_ values: [Double]) -> TCNTrend {
    if values.min() == values.max() {
        return TCNTrend(intercept: values[0], slope: 0)
    }
    let count = Double(values.count)
    let center = (count - 1) / 2
    let mean = values.reduce(0, +) / count
    var covariance = 0.0
    var indexVariance = 0.0
    for (index, value) in values.enumerated() {
        let centeredIndex = Double(index) - center
        covariance += centeredIndex * (value - mean)
        indexVariance += centeredIndex * centeredIndex
    }
    let slope = indexVariance > 0 ? covariance / indexVariance : 0
    let intercept = mean - slope * center

    let residualVariance = values.enumerated().reduce(0.0) { partial, element in
        let residual = element.element - (intercept + slope * Double(element.offset))
        return partial + residual * residual
    } / count
    let trendSpan = abs(slope) * (count - 1)
    guard trendSpan > 2 * sqrt(residualVariance) else {
        return TCNTrend(intercept: mean, slope: 0)
    }
    return TCNTrend(intercept: intercept, slope: slope)
}

private func validateTCNSampling(_ points: [Point], sampleInterval: Double) throws {
    let origin = points[0].time
    let tolerance = max(abs(sampleInterval) * 1e-6, 1e-15)
    for index in 1 ..< points.count {
        let expected = origin + Double(index) * sampleInterval
        if abs(points[index].time - expected) > tolerance * max(1, Double(index)) {
            throw TCNForecastError.nonUniformSampling(index: index)
        }
    }
}

/// Build a sparse dilated causal kernel: dense recent taps plus an automatically detected
/// seasonal tap. The long tap gives the TCN enough receptive field for oscilloscope captures
/// whose period is much longer than their local edge shape.
private func tcnCausalLags(values: [Double]) -> [Int] {
    let localContext = min(tcnMaximumLocalContext, max(4, (values.count - 1) / 8))
    var lags = Array(1 ... localContext)
    guard let bestLag = detectedTCNPeriod(values: values), bestLag > localContext else {
        return lags
    }
    for lag in max(localContext + 1, bestLag - 2) ... min(values.count - 1, bestLag + 2) {
        lags.append(lag)
    }
    return lags
}

private func detectedTCNPeriod(values: [Double]) -> Int? {
    let minimumLag = min(tcnMaximumLocalContext, max(4, (values.count - 1) / 8)) + 1
    let maximumLag = min(values.count * 2 / 3, values.count - 8)
    guard maximumLag >= minimumLag else {
        return nil
    }
    let variance = values.reduce(0) { $0 + $1 * $1 } / Double(values.count)
    guard variance > 0 else {
        return nil
    }
    var bestLag: Int?
    var bestError = Double.infinity
    for lag in minimumLag ... maximumLag {
        var squaredError = 0.0
        for index in lag ..< values.count {
            let difference = values[index] - values[index - lag]
            squaredError += difference * difference
        }
        let error = squaredError / Double(values.count - lag)
        if error < bestError {
            bestError = error
            bestLag = lag
        }
    }

    // Independent samples have expected difference energy of about 2 × variance.
    // Require a much stronger match before treating a lag as a repeating period.
    return if let bestLag, bestError < variance * 0.5 { bestLag } else { nil }
}

private func fitCausalConvolution(values: [Double], lags: [Int]) -> [Double] {
    let parameterCount = lags.count + 1 // bias plus one weight per causal kernel tap
    var gram = Array(repeating: Array(repeating: 0.0, count: parameterCount), count: parameterCount)
    var target = Array(repeating: 0.0, count: parameterCount)
    let firstRow = max(lags.max() ?? 1, values.count - tcnMaximumTrainingRows)

    for sampleIndex in firstRow ..< values.count {
        var features = Array(repeating: 1.0, count: parameterCount)
        for (featureIndex, lag) in lags.enumerated() {
            features[featureIndex + 1] = values[sampleIndex - lag]
        }
        for row in 0 ..< parameterCount {
            target[row] += features[row] * values[sampleIndex]
            for column in row ..< parameterCount {
                gram[row][column] += features[row] * features[column]
            }
        }
    }

    for row in 0 ..< parameterCount {
        for column in 0 ..< row {
            gram[row][column] = gram[column][row]
        }
    }

    let trainingRowCount = max(1, values.count - firstRow)
    let regularization = Double(trainingRowCount) * 1e-6
    for index in 1 ..< parameterCount { // Do not regularize the bias.
        gram[index][index] += regularization
    }

    return solveLinearSystem(gram, target) ?? fallbackTCNCoefficients(lags: lags)
}

private func solveLinearSystem(_ matrix: [[Double]], _ vector: [Double]) -> [Double]? {
    var a = matrix
    var b = vector
    let count = b.count

    for pivot in 0 ..< count {
        var bestRow = pivot
        for row in (pivot + 1) ..< count where abs(a[row][pivot]) > abs(a[bestRow][pivot]) {
            bestRow = row
        }
        guard abs(a[bestRow][pivot]) > 1e-14 else {
            return nil
        }
        if bestRow != pivot {
            a.swapAt(bestRow, pivot)
            b.swapAt(bestRow, pivot)
        }

        let divisor = a[pivot][pivot]
        for column in pivot ..< count {
            a[pivot][column] /= divisor
        }
        b[pivot] /= divisor

        for row in 0 ..< count where row != pivot {
            let factor = a[row][pivot]
            guard factor != 0 else {
                continue
            }
            for column in pivot ..< count {
                a[row][column] -= factor * a[pivot][column]
            }
            b[row] -= factor * b[pivot]
        }
    }

    return b.allSatisfy(\.isFinite) ? b : nil
}

private func fallbackTCNCoefficients(lags: [Int]) -> [Double] {
    var coefficients = Array(repeating: 0.0, count: lags.count + 1)
    if let lastValueIndex = lags.firstIndex(of: 1) {
        coefficients[lastValueIndex + 1] = 1 // Hold the last value if fitting becomes singular.
    }
    return coefficients
}

private func appendTCNForecast(
    to points: [Point],
    values: [Double],
    sampleInterval: Double,
) -> [Point] {
    var output = points
    output.reserveCapacity(points.count + values.count)
    let lastTime = points[points.count - 1].time
    for (offset, value) in values.enumerated() {
        output.append(Point(
            time: lastTime + Double(offset + 1) * sampleInterval,
            value: value,
        ))
    }
    return output
}

private func resampleTCNForecastIfNeeded(
    _ nativeForecast: [Point],
    originalCount: Int,
    duration: Double,
    sampleCount: Int?,
    sampleInterval: Double,
) -> [Point] {
    guard let sampleCount else {
        return nativeForecast
    }

    let original = nativeForecast.prefix(originalCount)
    let lastOriginal = nativeForecast[originalCount - 1]
    let timelineValues = [lastOriginal.value] + nativeForecast.dropFirst(originalCount).map(\.value)
    var output = Array(original)
    output.reserveCapacity(originalCount + sampleCount)

    for outputIndex in 1 ... sampleCount {
        let elapsed = duration * Double(outputIndex) / Double(sampleCount)
        let sourcePosition = elapsed / sampleInterval
        let lowerIndex = min(Int(sourcePosition.rounded(.down)), timelineValues.count - 1)
        let upperIndex = min(lowerIndex + 1, timelineValues.count - 1)
        let fraction = sourcePosition - Double(lowerIndex)
        let value = timelineValues[lowerIndex]
            + fraction * (timelineValues[upperIndex] - timelineValues[lowerIndex])
        output.append(Point(time: lastOriginal.time + elapsed, value: value))
    }
    return output
}
