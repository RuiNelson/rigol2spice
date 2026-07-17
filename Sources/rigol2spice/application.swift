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
        let processedPoints = try process(
            capture.points,
            transformations: transformations,
            sampleInterval: capture.sampleInterval,
        )
        try write(processedPoints, sampleInterval: capture.sampleInterval ?? 0)

        Console.section("Job complete")
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
        Console.section("Loading input file...")
        let data = try Data(contentsOf: fileURL(for: options.inputFile))
        Console.detail("Read \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
        return data
    }

    private func parseCapture(_ data: Data) throws -> Capture {
        Console.section("Parsing input file...")
        if data.count > 1_000_000 {
            Console.detail("(This might take a while)")
        }

        let requestedChannel = options.listChannels ? nil : options.channel
        return try options.format.parser.parse(data, channel: requestedChannel)
    }

    private func reportChannels(_ channels: [String]) {
        Console.detail("Channels:")
        for channel in channels {
            Console.detail("- \(channel)", level: 2)
        }
    }

    private func reportCapture(_ capture: Capture) {
        if let selectedChannel = capture.selectedChannel {
            Console.detail("Selected channel: \(selectedChannel)")
        }

        Console.detail("Samples: \(numberOfPointsFormatter.string(for: capture.points.count)!)")

        if let lastPoint = capture.points.last {
            Console.detail("Last sample point: \(engineeringFormatter.string(lastPoint.time))s")
        }

        guard capture.points.count >= 2,
              let interval = capture.sampleInterval,
              let duration = capture.duration,
              duration > 0 else {
            return
        }

        let sampleRate = Double(capture.points.count) / duration
        Console.detail("Sample Interval : \(engineeringFormatter.string(interval))s")
        Console.detail("Sample Rate     : \(engineeringFormatter.string(sampleRate))sa/s")
        Console.detail("Capture Duration: \(engineeringFormatter.string(duration))s")
    }

    private func process(
        _ source: [Point],
        transformations: [Transformation],
        sampleInterval: Double?,
    ) throws -> [Point] {
        var points = source

        for transformation in transformations {
            let countBefore = points.count
            if case .removeDC = transformation {
                let estimate = estimateDC(points)
                reportTransformation(transformation, points: points, dcEstimate: estimate)
                points = offsetPoints(points, offset: -estimate.value)
            }
            else if let kind = transformation.filterKind {
                let design = try transformation.designFilter(
                    kind: kind,
                    points: points,
                    sampleInterval: sampleInterval,
                )
                reportFilter(design)
                points = applyFIRFilter(taps: design.taps, to: points)
            }
            else {
                reportTransformation(transformation, points: points)
                points = try transformation.applying(to: points, sampleInterval: sampleInterval)
            }

            if transformation.reportsPointCount {
                try reportPointCount(before: countBefore, after: points.count)
            }
        }

        if let interval = options.downsample {
            Console.section("Downsampling at 1/\(interval)...")
            let countBefore = points.count
            points = downsamplePoints(points, interval: interval)
            try reportPointCount(before: countBefore, after: points.count)
        }

        if !options.keepAll, points.count >= 3 {
            Console.section("Removing redundant sample points (optimize)...")
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
            Console.section("Removing DC component...")
            Console.detail("Automatically calculated DC component: \(engineeringFormatter.string(estimate.value))")
            let centroids = estimate.centroids
                .map { engineeringFormatter.string($0) }
                .joined(separator: ", ")
            Console.detail("K-means centroids: \(centroids) (\(estimate.iterations) iterations)")
        case let .clampMin(value):
            Console.section("Clamping the signal above \(engineeringFormatter.string(value))...")
        case let .clampMax(value):
            Console.section("Clamping the signal below \(engineeringFormatter.string(value))...")
        case let .gate(value):
            Console.section("Gating the signal at \(engineeringFormatter.string(value))...")
        case let .offset(value):
            let sign = value >= 0 ? "+" : ""
            Console.section("Offsetting signal by \(sign)\(engineeringFormatter.string(value))...")
        case let .multiply(value):
            Console.section("Multiplying the signal by a factor of \(engineeringFormatter.string(value))...")
        case .invert:
            Console.section("Inverting the signal...")
        case .abs:
            Console.section("Taking the absolute value of the signal...")
        case .rectify:
            Console.section("Half-wave rectifying the signal...")
        case .normalize:
            Console.section("Normalizing the signal to unit peak...")
        case let .peakTo(value):
            Console.section("Scaling peak absolute value to \(engineeringFormatter.string(value))...")
        case let .scaleTo(value):
            Console.section("Scaling peak absolute value to \(engineeringFormatter.string(value))...")
        case let .db(value):
            let sign = value >= 0 ? "+" : ""
            Console.section("Scaling the signal by \(sign)\(engineeringFormatter.string(value))dB...")
        case let .dbmW(level, resistance):
            let volts = voltageFromDBmW(level, resistance: resistance)
            Console.section(
                "Scaling the signal by \(engineeringFormatter.string(level))dBmW (×\(engineeringFormatter.string(volts)) V at \(engineeringFormatter.string(resistance))Ω)...",
            )
        case let .dbW(level, resistance):
            let volts = voltageFromDBW(level, resistance: resistance)
            Console.section(
                "Scaling the signal by \(engineeringFormatter.string(level))dBW (×\(engineeringFormatter.string(volts)) V at \(engineeringFormatter.string(resistance))Ω)...",
            )
        case let .timeShift(value):
            Console.section("Shifting signal for \(engineeringFormatter.string(value))s...")
        case let .cutAfter(value):
            Console.section("Cutting signal after \(engineeringFormatter.string(value))s...")
        case let .cutBefore(value):
            Console.section("Cutting signal before \(engineeringFormatter.string(value))s...")
        case let .trim(start, end):
            Console.section(
                "Trimming signal from \(engineeringFormatter.string(start))s to \(engineeringFormatter.string(end))s...",
            )
        case let .repeat(amount):
            Console.section("Repeating capture for \(engineeringFormatter.string(amount)) times...")
        case let .lowPass(cutoff):
            Console.section("Applying low-pass FIR filter at \(engineeringFormatter.string(cutoff))Hz...")
        case let .highPass(cutoff):
            Console.section("Applying high-pass FIR filter at \(engineeringFormatter.string(cutoff))Hz...")
        case let .bandPass(low, high):
            Console.section(
                "Applying band-pass FIR filter from \(engineeringFormatter.string(low))Hz to \(engineeringFormatter.string(high))Hz...",
            )
        case let .bandStop(low, high):
            Console.section(
                "Applying band-stop FIR filter from \(engineeringFormatter.string(low))Hz to \(engineeringFormatter.string(high))Hz...",
            )
        }
    }

    private func reportFilter(_ design: FIRFilterDesign) {
        switch design.kind {
        case let .lowPass(cutoff):
            Console.section("Applying low-pass FIR filter at \(engineeringFormatter.string(cutoff))Hz...")
        case let .highPass(cutoff):
            Console.section("Applying high-pass FIR filter at \(engineeringFormatter.string(cutoff))Hz...")
        case let .bandPass(low, high):
            Console.section(
                "Applying band-pass FIR filter from \(engineeringFormatter.string(low))Hz to \(engineeringFormatter.string(high))Hz...",
            )
        case let .bandStop(low, high):
            Console.section(
                "Applying band-stop FIR filter from \(engineeringFormatter.string(low))Hz to \(engineeringFormatter.string(high))Hz...",
            )
        }

        Console.detail("Window: Blackman-Harris (linear phase, group delay removed)")
        Console.detail("Taps: \(numberOfPointsFormatter.string(for: design.tapCount)!)")
        Console.detail("Sample rate: \(engineeringFormatter.string(design.sampleRate))sa/s")
        Console.detail(
            "Group delay removed: \(design.groupDelaySamples) samples (\(engineeringFormatter.string(design.groupDelaySeconds))s)",
        )
    }

    private func reportPointCount(before: Int, after: Int) throws {
        guard after > 0 else {
            throw Rigol2SpiceError.operationRemovedEveryPoint
        }

        guard before != after else {
            Console.detail("Maintained all the samples")
            return
        }

        let formattedBefore = numberOfPointsFormatter.string(for: before)!
        let formattedAfter = numberOfPointsFormatter.string(for: after)!
        Console.detail("From \(formattedBefore) samples to \(formattedAfter) samples")
    }

    private func write(_ points: [Point], sampleInterval: Double) throws {
        guard let outputFile = options.outputFile else {
            throw Rigol2SpiceError.outputFileNotSpecified
        }

        Console.section("Writing output file...")
        Console.detail("Number of sample points: \(numberOfPointsFormatter.string(for: points.count)!)")

        let byteCount = try PWLWriter().write(points, to: fileURL(for: outputFile))

        let firstTime = points[0].time
        let lastTime = points[points.count - 1].time
        Console.detail("First sample: \(engineeringFormatter.string(firstTime))s")
        Console.detail("Last sample: \(engineeringFormatter.string(lastTime))s")
        Console.detail("Capture duration: \(engineeringFormatter.string(lastTime + sampleInterval))s")
        Console
            .detail("Saving file: \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))...")
    }

    private func fileURL(for filename: String) -> URL {
        let expandedPath = NSString(string: filename).expandingTildeInPath
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return URL(fileURLWithPath: expandedPath, relativeTo: workingDirectory).standardizedFileURL
    }
}
