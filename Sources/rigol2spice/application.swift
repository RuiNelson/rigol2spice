import Foundation

// MARK: - Rigol2SpiceError

enum Rigol2SpiceError: LocalizedError {
    case outputFileNotSpecified
    case inputFileContainsNoPoints
    case invalidDownsampleValue(value: Int)
    case mustHaveAtLeastTwoPointsToRepeat
    case operationRemovedEveryPoint

    var errorDescription: String? {
        switch self {
        case .outputFileNotSpecified: "Please specify the output file name after the input file name"
        case .inputFileContainsNoPoints: "Input file contains zero samples"
        case let .invalidDownsampleValue(value): "Invalid downsample value: \(value)"
        case .mustHaveAtLeastTwoPointsToRepeat: "Must have at least two original samples to repeat capture"
        case .operationRemovedEveryPoint: "Operation removed every sample"
        }
    }
}

// MARK: - ApplicationOptions

struct ApplicationOptions {
    let format: CaptureFormat
    let listChannels: Bool
    let channel: String
    let transformations: String?
    let downsample: Int?
    let keepAll: Bool
    let inputFile: String
    let outputFile: String?
}

// MARK: - Rigol2SpiceApplication

struct Rigol2SpiceApplication {
    private let options: ApplicationOptions
    private let console = Console()

    init(options: ApplicationOptions) {
        self.options = options
    }

    func run() throws {
        let transformations = try validateOptions()
        let data = try loadInput()
        let capture = try parseCapture(data)

        reportChannels(capture.channels)
        guard !options.listChannels else {
            return
        }

        guard !capture.points.isEmpty else {
            throw Rigol2SpiceError.inputFileContainsNoPoints
        }

        reportCapture(capture)
        let processedPoints = try process(capture.points, transformations: transformations)
        try write(processedPoints, sampleInterval: capture.sampleInterval ?? 0)

        console.section("Job complete")
        print("")
    }

    private func validateOptions() throws -> [Transformation] {
        guard options.listChannels || options.outputFile != nil else {
            throw Rigol2SpiceError.outputFileNotSpecified
        }

        if let downsample = options.downsample, downsample <= 1 {
            throw Rigol2SpiceError.invalidDownsampleValue(value: downsample)
        }

        guard let source = options.transformations else {
            return []
        }
        return try Transformation.parseList(source)
    }

    private func loadInput() throws -> Data {
        console.section("Loading input file...")
        let data = try Data(contentsOf: fileURL(for: options.inputFile))
        console.detail("Read \(fileSizeFormatter.string(fromByteCount: Int64(data.count)))")
        return data
    }

    private func parseCapture(_ data: Data) throws -> Capture {
        console.section("Parsing input file...")
        if data.count > 1_000_000 {
            console.detail("(This might take a while)")
        }

        let requestedChannel = options.listChannels ? nil : options.channel
        return try options.format.parser.parse(data, channel: requestedChannel)
    }

    private func reportChannels(_ channels: [String]) {
        console.detail("Channels:")
        for channel in channels {
            console.detail("- \(channel)", level: 2)
        }
    }

    private func reportCapture(_ capture: Capture) {
        if let selectedChannel = capture.selectedChannel {
            console.detail("Selected channel: \(selectedChannel)")
        }

        console.detail("Samples: \(numberOfPointsFormatter.string(for: capture.points.count)!)")

        if let lastPoint = capture.points.last {
            console.detail("Last sample point: \(engineeringFormatter.string(lastPoint.time))s")
        }

        guard capture.points.count >= 2,
              let interval = capture.sampleInterval,
              let duration = capture.duration,
              duration > 0 else {
            return
        }

        let sampleRate = Double(capture.points.count) / duration
        console.detail("Sample Interval : \(engineeringFormatter.string(interval))s")
        console.detail("Sample Rate     : \(engineeringFormatter.string(sampleRate))sa/s")
        console.detail("Capture Duration: \(engineeringFormatter.string(duration))s")
    }

    private func process(_ source: [Point], transformations: [Transformation]) throws -> [Point] {
        var points = source

        for transformation in transformations {
            let countBefore = points.count
            if case .removeDC = transformation {
                let estimate = estimateDC(points)
                reportTransformation(transformation, points: points, dcEstimate: estimate)
                points = offsetPoints(points, offset: -estimate.value)
            }
            else {
                reportTransformation(transformation, points: points)
                points = try transformation.applying(to: points)
            }

            if transformation.reportsPointCount {
                try reportPointCount(before: countBefore, after: points.count)
            }
        }

        if let interval = options.downsample {
            console.section("Downsampling at 1/\(interval)...")
            let countBefore = points.count
            points = downsamplePoints(points, interval: interval)
            try reportPointCount(before: countBefore, after: points.count)
        }

        if !options.keepAll, points.count >= 3 {
            console.section("Removing redundant sample points (optimize)...")
            let countBefore = points.count
            points = removeRedundant(points)
            try reportPointCount(before: countBefore, after: points.count)
        }

        return points
    }

    private func reportTransformation(
        _ transformation: Transformation,
        points: [Point],
        dcEstimate: DCEstimate? = nil,
    ) {
        switch transformation {
        case .removeDC:
            let estimate = dcEstimate ?? estimateDC(points)
            console.section("Removing DC component...")
            console.detail("Automatically calculated DC component: \(engineeringFormatter.string(estimate.value))")
            let centroids = estimate.centroids
                .map { engineeringFormatter.string($0) }
                .joined(separator: ", ")
            console.detail("K-means centroids: \(centroids) (\(estimate.iterations) iterations)")
        case let .clampMin(value):
            console.section("Clamping the signal above \(engineeringFormatter.string(value))...")
        case let .clampMax(value):
            console.section("Clamping the signal below \(engineeringFormatter.string(value))...")
        case let .offset(value):
            let sign = value >= 0 ? "+" : ""
            console.section("Offsetting signal by \(sign)\(engineeringFormatter.string(value))...")
        case let .multiply(value):
            console.section("Multiplying the signal by a factor of \(engineeringFormatter.string(value))...")
        case let .timeShift(value):
            console.section("Shifting signal for \(engineeringFormatter.string(value))s...")
        case let .cutAfter(value):
            console.section("Cutting signal after \(engineeringFormatter.string(value))s...")
        case let .repeat(amount):
            console.section("Repeating capture for \(engineeringFormatter.string(amount)) times...")
        }
    }

    private func reportPointCount(before: Int, after: Int) throws {
        guard after > 0 else {
            throw Rigol2SpiceError.operationRemovedEveryPoint
        }

        guard before != after else {
            console.detail("Maintained all the samples")
            return
        }

        let formattedBefore = numberOfPointsFormatter.string(for: before)!
        let formattedAfter = numberOfPointsFormatter.string(for: after)!
        console.detail("From \(formattedBefore) samples to \(formattedAfter) samples")
    }

    private func write(_ points: [Point], sampleInterval: Double) throws {
        guard let outputFile = options.outputFile else {
            throw Rigol2SpiceError.outputFileNotSpecified
        }

        console.section("Writing output file...")
        console.detail("Number of sample points: \(numberOfPointsFormatter.string(for: points.count)!)")

        let byteCount = try PWLWriter().write(points, to: fileURL(for: outputFile))

        let firstTime = points[0].time
        let lastTime = points[points.count - 1].time
        console.detail("First sample: \(engineeringFormatter.string(firstTime))s")
        console.detail("Last sample: \(engineeringFormatter.string(lastTime))s")
        console.detail("Capture duration: \(engineeringFormatter.string(lastTime + sampleInterval))s")
        console.detail("Saving file: \(fileSizeFormatter.string(fromByteCount: Int64(byteCount)))...")
    }

    private func fileURL(for filename: String) -> URL {
        let expandedPath = NSString(string: filename).expandingTildeInPath
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return URL(fileURLWithPath: expandedPath, relativeTo: workingDirectory).standardizedFileURL
    }
}
