import Foundation

// MARK: - FFTWindowPosition

enum FFTWindowPosition: String, Equatable {
    case start
    case middle
    case end
}

// MARK: - FFTSpectrum

/// Positive-frequency magnitude spectrum from a real FFT (including DC and Nyquist).
struct FFTSpectrum: Equatable {
    /// Requested analysis length (user argument).
    let requestedPointCount: Int
    /// Samples actually taken from the capture (≤ requested).
    let usedPointCount: Int
    /// Position of the selected sample window inside the capture.
    let windowPosition: FFTWindowPosition
    /// FFT length after zero-padding to the next power of two.
    let fftSize: Int
    let sampleRate: Double
    /// Frequency of the dominant AC peak (bin 0 / DC is ignored when possible).
    let centerFrequency: Double
    /// Linear magnitude of the dominant AC peak (same scale as `magnitudes`).
    let centerMagnitude: Double
    /// Magnitude of the dominant peak in dB: `20 · log₁₀(|X|)`.
    let centerMagnitudeDB: Double
    /// Bin centre frequencies from 0 to Nyquist (Hz).
    let frequencies: [Double]
    /// Linear magnitudes `|X[k]|`.
    let magnitudes: [Double]
    /// Magnitude in dB: `20 · log₁₀(|X[k|)` with a small floor.
    let magnitudesDB: [Double]
}

// MARK: - FFT analysis

/// Hann-windowed real FFT of up to `requestedPointCount` samples.
///
/// - If the capture is shorter than requested, every available sample is used.
/// - If longer, the requested window is selected at the start, middle, or end.
/// - Values are zero-padded to the next power of two for a radix-2 FFT.
func computeFFTSpectrum(
    points: [Point],
    requestedPointCount: Int,
    position: FFTWindowPosition = .start,
) -> FFTSpectrum? {
    guard requestedPointCount >= 1, points.count >= 2 else {
        return nil
    }

    let usedCount = min(requestedPointCount, points.count)
    guard usedCount >= 2 else {
        return nil
    }

    let start: Int = switch position {
    case .start:
        0
    case .middle:
        (points.count - usedCount) / 2
    case .end:
        points.count - usedCount
    }
    let window = points[start ..< (start + usedCount)]
    let firstTime = window[window.startIndex].time
    let lastTime = window[window.index(before: window.endIndex)].time
    let span = lastTime - firstTime
    guard span > 0, span.isFinite else {
        return nil
    }

    // Uniform-rate assumption over the selected window.
    let sampleRate = Double(usedCount - 1) / span
    guard sampleRate > 0, sampleRate.isFinite else {
        return nil
    }

    var real = window.map(\.value)
    // Remove mean so a large DC offset does not leak into low bins (especially after
    // zero-padding) and drown the real AC tone when picking the peak.
    removeMean(&real)
    applyHannWindow(&real)

    let fftSize = nextPowerOfTwo(usedCount)
    if real.count < fftSize {
        real.append(contentsOf: repeatElement(0.0, count: fftSize - real.count))
    }
    var imag = [Double](repeating: 0, count: fftSize)
    radix2FFT(&real, &imag)

    let binCount = fftSize / 2 + 1
    var frequencies = [Double]()
    var magnitudes = [Double]()
    frequencies.reserveCapacity(binCount)
    magnitudes.reserveCapacity(binCount)

    for bin in 0 ..< binCount {
        frequencies.append(Double(bin) * sampleRate / Double(fftSize))
        magnitudes.append(hypot(real[bin], imag[bin]))
    }

    let peakBin = dominantPeakBin(magnitudes: magnitudes)
    let peakMagnitude = magnitudes[peakBin]
    let magnitudeFloor = max(peakMagnitude * 1e-12, 1e-30)
    let magnitudesDB = magnitudes.map { magnitude in
        20 * log10(max(magnitude, magnitudeFloor))
    }
    let centerFrequency = refinedPeakFrequency(
        magnitudes: magnitudes,
        frequencies: frequencies,
        peakBin: peakBin,
    )
    let centerMagnitudeDB = 20 * log10(max(peakMagnitude, magnitudeFloor))

    return FFTSpectrum(
        requestedPointCount: requestedPointCount,
        usedPointCount: usedCount,
        windowPosition: position,
        fftSize: fftSize,
        sampleRate: sampleRate,
        centerFrequency: centerFrequency,
        centerMagnitude: peakMagnitude,
        centerMagnitudeDB: centerMagnitudeDB,
        frequencies: frequencies,
        magnitudes: magnitudes,
        magnitudesDB: magnitudesDB,
    )
}

func removeMean(_ values: inout [Double]) {
    guard !values.isEmpty else {
        return
    }
    let mean = values.reduce(0, +) / Double(values.count)
    for index in values.indices {
        values[index] -= mean
    }
}

/// Dominant spectral peak: strongest **local** maximum excluding DC (bin 0).
/// Local peaks avoid DC leakage skirts that can exceed a true tone after zero-padding.
func dominantPeakBin(magnitudes: [Double]) -> Int {
    guard magnitudes.count > 1 else {
        return 0
    }
    guard magnitudes.count > 2 else {
        return magnitudes[1] >= magnitudes[0] ? 1 : 0
    }

    var peakBin = 1
    var peakMagnitude = -Double.infinity

    for bin in 1 ..< (magnitudes.count - 1) {
        let magnitude = magnitudes[bin]
        let isLocalPeak = magnitude >= magnitudes[bin - 1] && magnitude >= magnitudes[bin + 1]
        if isLocalPeak, magnitude > peakMagnitude {
            peakMagnitude = magnitude
            peakBin = bin
        }
    }

    // Nyquist bin (last): local peak if not below its left neighbour.
    let last = magnitudes.count - 1
    if magnitudes[last] >= magnitudes[last - 1], magnitudes[last] > peakMagnitude {
        peakMagnitude = magnitudes[last]
        peakBin = last
    }

    // No local peak found (pathological): fall back to global max excluding DC.
    if peakMagnitude.isFinite == false || peakMagnitude < 0 {
        peakBin = 1
        peakMagnitude = magnitudes[1]
        for bin in 2 ..< magnitudes.count {
            if magnitudes[bin] > peakMagnitude {
                peakMagnitude = magnitudes[bin]
                peakBin = bin
            }
        }
    }

    // Pure DC (or numerical noise): fall back to bin 0 if AC peak is negligible.
    if magnitudes[0] > max(peakMagnitude, 0) * 1e6 {
        return 0
    }
    return peakBin
}

/// Parabolic interpolation around `peakBin` for a sub-bin frequency estimate.
func refinedPeakFrequency(
    magnitudes: [Double],
    frequencies: [Double],
    peakBin: Int,
) -> Double {
    guard peakBin > 0,
          peakBin < magnitudes.count - 1,
          peakBin < frequencies.count,
          frequencies.count >= 2 else {
        return frequencies.indices.contains(peakBin) ? frequencies[peakBin] : 0
    }

    let y0 = magnitudes[peakBin - 1]
    let y1 = magnitudes[peakBin]
    let y2 = magnitudes[peakBin + 1]
    let denom = y0 - 2 * y1 + y2
    guard abs(denom) > 1e-30, y1 > 0 else {
        return frequencies[peakBin]
    }

    let delta = 0.5 * (y0 - y2) / denom
    guard delta > -1, delta < 1 else {
        return frequencies[peakBin]
    }

    let binWidth = frequencies[1] - frequencies[0]
    return frequencies[peakBin] + delta * binWidth
}

func applyHannWindow(_ values: inout [Double]) {
    let count = values.count
    guard count > 1 else {
        return
    }
    let scale = 2 * Double.pi / Double(count - 1)
    for index in values.indices {
        values[index] *= 0.5 * (1 - cos(scale * Double(index)))
    }
}

func nextPowerOfTwo(_ value: Int) -> Int {
    guard value > 1 else {
        return 1
    }
    var power = 1
    while power < value {
        power <<= 1
    }
    return power
}

/// In-place radix-2 Cooley–Tukey FFT (length must be a power of two).
func radix2FFT(_ real: inout [Double], _ imag: inout [Double]) {
    let n = real.count
    precondition(n == imag.count && n > 0 && n & (n - 1) == 0)

    var j = 0
    for i in 1 ..< n {
        var bit = n >> 1
        while j & bit != 0 {
            j ^= bit
            bit >>= 1
        }
        j ^= bit
        if i < j {
            real.swapAt(i, j)
            imag.swapAt(i, j)
        }
    }

    var length = 2
    while length <= n {
        let angle = -2 * Double.pi / Double(length)
        let wLengthReal = cos(angle)
        let wLengthImag = sin(angle)
        let half = length / 2
        var blockStart = 0
        while blockStart < n {
            var wReal = 1.0
            var wImag = 0.0
            for k in 0 ..< half {
                let i = blockStart + k
                let j = i + half
                let tReal = wReal * real[j] - wImag * imag[j]
                let tImag = wReal * imag[j] + wImag * real[j]
                real[j] = real[i] - tReal
                imag[j] = imag[i] - tImag
                real[i] += tReal
                imag[i] += tImag

                let nextWReal = wReal * wLengthReal - wImag * wLengthImag
                wImag = wReal * wLengthImag + wImag * wLengthReal
                wReal = nextWReal
            }
            blockStart += length
        }
        length <<= 1
    }
}
