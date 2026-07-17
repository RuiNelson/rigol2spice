import Foundation

private let dcClusterCount = 3
private let maximumKMeansIterations = 100
private let relativeConvergenceTolerance = 1e-12

// MARK: - DCEstimate

struct DCEstimate: Equatable {
    let value: Double
    let centroids: [Double]
    let iterations: Int
}

// MARK: - KMeansResult

private struct KMeansResult {
    let centroids: [Double]
    let iterations: Int
    let error: Double
}

func calculateDC(_ points: [Point]) -> Double {
    estimateDC(points).value
}

func estimateDC(_ points: [Point]) -> DCEstimate {
    let values = points.lazy.map(\.value).filter(\.isFinite)
    let sortedValues = values.sorted()
    guard let minimum = sortedValues.first, let maximum = sortedValues.last else {
        return DCEstimate(value: 0, centroids: [0, 0, 0], iterations: 0)
    }

    guard minimum < maximum else {
        return DCEstimate(
            value: minimum,
            centroids: [minimum, minimum, minimum],
            iterations: 0,
        )
    }

    let convergenceTolerance = max(Double.leastNormalMagnitude, maximum - minimum)
        * relativeConvergenceTolerance
    let median = interpolatedQuantile(0.5, in: sortedValues)
    let initializations = [
        quantileCentroids(from: sortedValues),
        [minimum, median, maximum],
        [
            interpolatedQuantile(0.25, in: sortedValues),
            median,
            interpolatedQuantile(0.75, in: sortedValues),
        ],
    ]
    let result = initializations
        .map {
            runKMeans(
                values: sortedValues,
                initialCentroids: $0,
                convergenceTolerance: convergenceTolerance,
            )
        }
        .min { $0.error < $1.error }!

    return DCEstimate(
        value: (result.centroids[0] + result.centroids[2]) / 2,
        centroids: result.centroids,
        iterations: result.iterations,
    )
}

private func runKMeans(
    values: [Double],
    initialCentroids: [Double],
    convergenceTolerance: Double,
) -> KMeansResult {
    var centroids = initialCentroids.sorted()
    var completedIterations = 0

    for iteration in 1 ... maximumKMeansIterations {
        var sums = Array(repeating: 0.0, count: dcClusterCount)
        var compensations = Array(repeating: 0.0, count: dcClusterCount)
        var counts = Array(repeating: 0, count: dcClusterCount)
        var farthestValue = values[0]
        var farthestDistance = -Double.infinity

        for value in values {
            let cluster = nearestCluster(to: value, centroids: centroids)
            addCompensated(
                value,
                sum: &sums[cluster],
                compensation: &compensations[cluster],
            )
            counts[cluster] += 1

            let distance = abs(value - centroids[cluster])
            if distance > farthestDistance {
                farthestDistance = distance
                farthestValue = value
            }
        }

        var updatedCentroids = (0 ..< dcClusterCount).map { cluster in
            guard counts[cluster] > 0 else {
                return farthestValue
            }
            return (sums[cluster] + compensations[cluster]) / Double(counts[cluster])
        }
        updatedCentroids.sort()

        completedIterations = iteration
        let maximumMovement = zip(centroids, updatedCentroids)
            .map { abs($0 - $1) }
            .max() ?? 0
        centroids = updatedCentroids

        if maximumMovement <= convergenceTolerance {
            break
        }
    }

    return KMeansResult(
        centroids: centroids,
        iterations: completedIterations,
        error: clusteringError(values: values, centroids: centroids),
    )
}

private func quantileCentroids(from sortedValues: [Double]) -> [Double] {
    (0 ..< dcClusterCount).map { cluster in
        let quantile = (Double(cluster) + 0.5) / Double(dcClusterCount)
        return interpolatedQuantile(quantile, in: sortedValues)
    }
}

private func clusteringError(values: [Double], centroids: [Double]) -> Double {
    var error = 0.0
    var compensation = 0.0

    for value in values {
        let cluster = nearestCluster(to: value, centroids: centroids)
        let distance = value - centroids[cluster]
        addCompensated(
            distance * distance,
            sum: &error,
            compensation: &compensation,
        )
    }

    return error + compensation
}

private func nearestCluster(to value: Double, centroids: [Double]) -> Int {
    var nearestIndex = 0
    var nearestDistance = abs(value - centroids[0])

    for index in 1 ..< centroids.count {
        let distance = abs(value - centroids[index])
        if distance < nearestDistance {
            nearestIndex = index
            nearestDistance = distance
        }
    }

    return nearestIndex
}

private func interpolatedQuantile(_ quantile: Double, in sortedValues: [Double]) -> Double {
    guard sortedValues.count > 1 else {
        return sortedValues[0]
    }

    let position = quantile * Double(sortedValues.count - 1)
    let lowerIndex = Int(position.rounded(.down))
    let upperIndex = Int(position.rounded(.up))
    guard lowerIndex != upperIndex else {
        return sortedValues[lowerIndex]
    }

    let fraction = position - Double(lowerIndex)
    return sortedValues[lowerIndex]
        + (sortedValues[upperIndex] - sortedValues[lowerIndex]) * fraction
}

private func addCompensated(_ value: Double, sum: inout Double, compensation: inout Double) {
    let updatedSum = sum + value
    if abs(sum) >= abs(value) {
        compensation += (sum - updatedSum) + value
    }
    else {
        compensation += (value - updatedSum) + sum
    }
    sum = updatedSum
}
