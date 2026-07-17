import ArgumentParser
import Foundation
import Progress

func printI(_ indent: Int, _ text: String) {
    if indent == 0 {
        print("")
        print("> " + text)
    }
    else {
        let spaces = Array(repeating: "    ", count: indent).joined()
        print(spaces + text)
    }
}

// MARK: - Rigol2SpiceErrors

enum Rigol2SpiceErrors: LocalizedError {
    case outputFileNotSpecified
    case inputFileContainsNoPoints
    case invalidDownsampleValue(value: Int)
    case mustHaveAtLeastTwoPointsToRepeat
    case operationRemovedEveryPoint

    var errorDescription: String? {
        switch self {
        case .outputFileNotSpecified:
            "Please specify the output file name after the input file name"
        case .inputFileContainsNoPoints:
            "Input file contains zero samples"
        case let .invalidDownsampleValue(value: v):
            "Invalid downsample value: \(v)"
        case .mustHaveAtLeastTwoPointsToRepeat:
            "Must have at least two original samples to repeat capture"
        case .operationRemovedEveryPoint:
            "Operation removed every sample"
        }
    }
}

// MARK: - rigol2spice

@main
struct rigol2spice: ParsableCommand {
    @Flag(
        name: .shortAndLong,
        help: "Adopts the format used by the newer Rigol Centaurus platform oscilloscopes.",
    )
    var newModels = false

    @Flag(
        name: .shortAndLong,
        help: "Only list channels present in the file and quit",
    )
    var listChannels = false

    @Option(
        name: .shortAndLong, help: "The label of the channel to be processed",
    )
    var channel: String?

    @Option(
        name: .shortAndLong,
        help: "Ordered transformations separated by semicolons",
    )
    var transformations: String?

    @Option(
        name: .shortAndLong,
        help: "Downsample ratio",
    )
    var downsample: Int?

    @Flag(
        name: .shortAndLong,
        help:
        "Don't remove redundant sample points. Sample points where the signal value maintains (useful for output file post-processing)",
    )
    var keepAll = false

    @Argument(
        help: "The filename of the .csv from the oscilloscope to be read",
        completion: CompletionKind.file(extensions: ["csv"]),
    )
    var inputFile: String

    @Argument(help: "The PWL filename to write to", completion: nil)
    var outputFile: String?

    func filenameToURL(_ filename: String) -> URL {
        let ns = NSString(string: filename)
        let expandedNs = ns.expandingTildeInPath
        let expandedStr = String(expandedNs)

        let cd = FileManager.default.currentDirectoryPath
        let cdURL = URL(fileURLWithPath: cd)

        return URL(fileURLWithPath: expandedStr, relativeTo: cdURL)
    }

    func nPointsReport(before: Int, after: Int) throws {
        guard after > 0 else {
            throw Rigol2SpiceErrors.operationRemovedEveryPoint
        }

        if after != before {
            let before = numberOfPointsFormatter.string(for: before)!
            let after = numberOfPointsFormatter.string(for: after)!
            printI(1, "From \(before) samples to \(after) samples")
        }
        else {
            printI(1, "Maintained all the samples")
        }
    }

    mutating func run() throws {
        // argument validation
        if !listChannels, outputFile == nil {
            throw Rigol2SpiceErrors.outputFileNotSpecified
        }

        let parsedTransformations: [Transformation] = if let transformations {
            try Transformation.parseList(transformations)
        }
        else {
            []
        }

        // Loading
        printI(0, "Loading input file...")
        let inputFileURL = filenameToURL(inputFile)
        let data = try Data(contentsOf: inputFileURL)
        let numBytesString = fileSizeFormatter.string(
            fromByteCount: Int64(data.count),
        )

        printI(1, "Read \(numBytesString)")

        // Parsing
        printI(0, "Parsing input file...")
        if data.count > 1_000_000 {
            printI(1, "(This might take a while)")
        }

        func presentNumberOfPoints() {
            let num = points.count
            let str = numberOfPointsFormatter.string(for: num)!
            printI(1, "Samples: \(str)")

            if let last = points.last {
                let lastTime = engineeringFormatter.string(last.time)
                printI(1, "Last sample point: \(lastTime)s")
            }
        }

        func presentSampleIntervalAndSampleRate(
            interval: Double, duration: Double, pointsCount: Int,
        ) {
            let rate = Double(pointsCount) / duration

            let intervalString = engineeringFormatter.string(interval)
            let rateString = engineeringFormatter.string(rate)
            let durationString = engineeringFormatter.string(duration)

            printI(1, "Sample Interval : \(intervalString)s")
            printI(1, "Sample Rate     : \(rateString)sa/s")
            printI(1, "Capture Duration: \(durationString)s")
        }

        var points: [Point] = .init()
        var sampleTimeInterval: Double = .init()
        var sampleDuration: Double = .init()

        if newModels {
            points = try CentaurusParser.parseCsv(
                data,
                forChannel: channel ?? "CH1",
                listChannelsOnly: listChannels,
            )

            guard !listChannels else {
                return
            }

            guard !points.isEmpty else {
                throw Rigol2SpiceErrors.inputFileContainsNoPoints
            }

            presentNumberOfPoints()

            if points.count >= 2 {
                let lastPointIndex = points.count - 1
                let penultimatePointIndex = points.count - 2

                sampleTimeInterval =
                    points[lastPointIndex].time
                        - points[penultimatePointIndex].time

                sampleDuration =
                    points[lastPointIndex].time + sampleTimeInterval

                presentSampleIntervalAndSampleRate(
                    interval: sampleTimeInterval,
                    duration: sampleDuration,
                    pointsCount: points.count,
                )
            }
        }
        else {
            let parsed = try CSVParser.parseCsv(
                data,
                forChannel: channel ?? "CH1",
                listChannelsOnly: listChannels,
            )

            guard !listChannels else {
                return
            }

            points = parsed.points

            guard !points.isEmpty else {
                throw Rigol2SpiceErrors.inputFileContainsNoPoints
            }

            presentNumberOfPoints()

            sampleTimeInterval = parsed.header.increment ?? 0.0
            sampleDuration = points.last!.time + sampleTimeInterval

            // Sample Rate Calculation
            if points.count >= 2 {
                presentSampleIntervalAndSampleRate(
                    interval: sampleTimeInterval,
                    duration: sampleDuration,
                    pointsCount: points.count,
                )
            }
        }

        guard !listChannels else {
            return
        }

        guard let outputFile else {
            throw Rigol2SpiceErrors.outputFileNotSpecified
        }

        // Transformations
        for transformation in parsedTransformations {
            switch transformation {
            case .removeDC:
                printI(0, "Removing DC component...")
                let dcComponent = calculateDC(points)
                let dcComponentString = engineeringFormatter.string(dcComponent)
                printI(1, "Automatically calculated DC component: \(dcComponentString)")
            case let .clampMin(value):
                printI(0, "Clamping the signal above \(engineeringFormatter.string(value))...")
            case let .clampMax(value):
                printI(0, "Clamping the signal below \(engineeringFormatter.string(value))...")
            case let .offset(value):
                let sign = value >= 0 ? "+" : ""
                printI(0, "Offsetting signal by \(sign)\(engineeringFormatter.string(value))...")
            case let .multiply(value):
                printI(0, "Multiplying the signal by a factor of \(engineeringFormatter.string(value))...")
            case let .timeShift(value):
                printI(0, "Shifting signal for \(engineeringFormatter.string(value))s...")
            case let .cutAfter(value):
                printI(0, "Cutting signal after \(engineeringFormatter.string(value))s...")
            case let .repeat(amount):
                printI(0, "Repeating capture for \(engineeringFormatter.string(amount)) times...")
            }

            let nPointsBefore = points.count
            points = try transformation.applying(to: points)

            if transformation.reportsPointCount {
                try nPointsReport(before: nPointsBefore, after: points.count)
            }
        }

        // Downsample
        if let ds = downsample {
            guard ds > 1 else {
                throw Rigol2SpiceErrors.invalidDownsampleValue(value: ds)
            }

            printI(0, "Downsampling at 1/\(ds)...")

            let nPointsBefore = points.count
            points = downsamplePoints(points, interval: ds)
            let nPointsAfter = points.count

            try nPointsReport(before: nPointsBefore, after: nPointsAfter)
        }

        // Compacting...
        if !keepAll, points.count >= 3 {
            printI(0, "Removing redundant sample points (optimize)...")

            let nPointsBefore = points.count
            points = removeRedundant(points)
            let nPointsAfter = points.count

            try nPointsReport(before: nPointsBefore, after: nPointsAfter)
        }

        // Output
        printI(0, "Writing output file...")
        let nPoints = points.count
        let newFirstPointTime = points.first!.time
        let newLastPointTime = points.last!.time
        let captureDuration = newLastPointTime + sampleTimeInterval

        let nSamplesString = numberOfPointsFormatter.string(for: nPoints)!
        let firstSampleString = engineeringFormatter.string(newFirstPointTime)
        let lastSampleString = engineeringFormatter.string(newLastPointTime)
        let captureDurationString = engineeringFormatter.string(captureDuration)

        printI(1, "Number of sample points: \(nSamplesString)")

        var outputFileData = Data()
        var outputFileProgressBar = ProgressBar(count: points.count)

        for point in points {
            let pointBytes = point.serialize.data(using: .ascii)!
            outputFileData.append(pointBytes)
            outputFileData.append(newlineBytes)

            outputFileProgressBar.next()
        }

        let fileSizeStr = fileSizeFormatter.string(
            fromByteCount: Int64(outputFileData.count),
        )

        printI(1, "First sample: \(firstSampleString)s")
        printI(1, "Last sample: \(lastSampleString)s")
        printI(1, "Capture duration: \(captureDurationString)s")
        printI(1, "Saving file: \(fileSizeStr)...")

        let outputFileURL = filenameToURL(outputFile)
        if FileManager.default.fileExists(atPath: outputFileURL.path) {
            try FileManager.default.removeItem(at: outputFileURL)
        }
        FileManager.default.createFile(
            atPath: outputFileURL.path, contents: outputFileData,
        )

        printI(0, "Job complete")
        print("")
    }
}
