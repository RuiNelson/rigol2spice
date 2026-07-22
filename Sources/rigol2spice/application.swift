import Foundation

// MARK: - Rigol2SpiceError

enum Rigol2SpiceError: LocalizedError, Equatable {
    case outputFileNotSpecified
    case inputFileContainsNoPoints
    case invalidDownsampleValue(value: Int)
    case mustHaveAtLeastTwoPointsToRepeat
    case operationRemovedEveryPoint
    case edgeNotFound(edge: TriggerEdge, threshold: Double)
    case triggerEventNotFound(operation: String)
    case periodNotDetected
    case commandFileUnreadable(option: String, path: String, reason: String)
    case decodeOutputWithoutDecoder
    case binaryDecodeRequiresOutput

    var errorDescription: String? {
        switch self {
        case .outputFileNotSpecified:
            "Please specify an output file, or use --list-channels, --plot, --analysis, and/or --decode"
        case .inputFileContainsNoPoints: "Input file contains zero samples"
        case let .invalidDownsampleValue(value): "Invalid downsample value: \(value)"
        case .mustHaveAtLeastTwoPointsToRepeat: "Must have at least two original samples to repeat capture"
        case .operationRemovedEveryPoint: "Operation removed every sample"
        case let .edgeNotFound(edge, threshold):
            "No \(edge.description) edge found at threshold \(threshold)"
        case let .triggerEventNotFound(operation):
            "No event matching \(operation) was found in the capture"
        case .periodNotDetected:
            "Could not detect a repeating period in the capture"
        case let .commandFileUnreadable(option, path, reason):
            "Could not read \(option) file \"\(path)\": \(reason)"
        case .decodeOutputWithoutDecoder:
            "--decode-output and --decode-format require --decode"
        case .binaryDecodeRequiresOutput:
            "--decode-format bin requires --decode-output"
        }
    }
}

// MARK: - ApplicationOptions

struct ApplicationOptions {
    let listChannels: Bool
    let channel: String
    let transformations: String?
    let transformationsFile: String?
    let analysis: String?
    let analysisFile: String?
    let decode: String?
    let decodeFormat: DecodeFormat
    let decodeOutput: String?
    let downsample: Int?
    let format: OutputFormat
    let keepAll: Bool
    let plotFile: String?
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
        let (transformations, analyses, decoder) = try validateOptions()
        let data = try loadInput()
        let capture = try parseCapture(data, channel: decoder?.primaryChannel)
        let decoderCaptures = try decoder.map {
            try loadDecoderChannels($0, data: data, primaryCapture: capture)
        }

        reportMetadata(capture.metadata)
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
        let decoderPoints = try decoderCaptures.map {
            try processDecoderChannels(
                $0,
                primaryChannel: decoder?.primaryChannel ?? "",
                primaryPoints: processedPoints,
                transformations: transformations,
            )
        }

        let analysisReports = AnalysisReport.reports(for: analyses, on: processedPoints)
        if !analysisReports.isEmpty {
            reportAnalysis(analysisReports)
        }

        let decodedResult: ProtocolDecodeResult? = if let decoder, let decoderPoints {
            try decode(decoder, pointsByChannel: decoderPoints)
        }
        else {
            nil
        }

        // Plot the dense processed waveform (before collinear optimization).
        if let plotFile = options.plotFile {
            try writePlot(
                processedPoints,
                to: plotFile,
                sourceFile: options.inputFile,
                channel: capture.selectedChannel ?? options.channel,
                analysisReports: analysisReports,
                decodeResult: decodedResult,
            )
        }

        let signalPoints = if options.outputFile != nil {
            try downsampleSignalOutput(processedPoints)
        }
        else {
            processedPoints
        }

        let outputPoints: [Point]
        if options.format == .pwl,
           !options.keepAll,
           signalPoints.count >= 3,
           options.outputFile != nil {
            Console.section("Removing redundant sample points (optimize)...")
            let countBefore = signalPoints.count
            outputPoints = removeRedundant(signalPoints)
            try reportPointCount(before: countBefore, after: outputPoints.count)
        }
        else {
            outputPoints = signalPoints
        }

        if options.outputFile != nil {
            try write(
                outputPoints,
                sampleInterval: inferredSampleInterval(from: signalPoints) ?? capture.sampleInterval ?? 0,
            )
        }

        Console.section("Job complete")
        print("")
    }

    private func validateOptions() throws -> (
        transformations: [Transformation],
        analyses: [Analysis],
        decoder: DecodeRequest?,
    ) {
        let hasAnalysis = options.analysis != nil || options.analysisFile != nil
        guard options.listChannels || options.outputFile != nil || options.plotFile != nil || hasAnalysis
            || options.decode != nil else {
            throw Rigol2SpiceError.outputFileNotSpecified
        }

        guard options.decode != nil || (options.decodeOutput == nil && options.decodeFormat == .text) else {
            throw Rigol2SpiceError.decodeOutputWithoutDecoder
        }
        if options.decode != nil, options.decodeFormat == .bin, options.decodeOutput == nil {
            throw Rigol2SpiceError.binaryDecodeRequiresOutput
        }

        if let downsample = options.downsample, downsample <= 1 {
            throw Rigol2SpiceError.invalidDownsampleValue(value: downsample)
        }

        let transformationSource = try combinedCommandSource(
            file: options.transformationsFile,
            inline: options.transformations,
            option: "transformations",
        )
        let transformations: [Transformation] = if let transformationSource {
            try Transformation.parseList(transformationSource)
        }
        else {
            []
        }

        let analysisSource = try combinedCommandSource(
            file: options.analysisFile,
            inline: options.analysis,
            option: "analysis",
        )
        let analyses: [Analysis] = if let analysisSource {
            try Analysis.parseList(analysisSource)
        }
        else {
            []
        }

        let decoder = try options.decode.map(DecodeRequest.parse)
        return (transformations, analyses, decoder)
    }

    private func combinedCommandSource(file: String?, inline: String?, option: String) throws -> String? {
        var sources: [String] = []
        if let file {
            do {
                try sources.append(String(contentsOfFile: file, encoding: .utf8))
            }
            catch {
                throw Rigol2SpiceError.commandFileUnreadable(
                    option: option,
                    path: file,
                    reason: error.localizedDescription,
                )
            }
        }
        if let inline {
            sources.append(inline)
        }
        return sources.isEmpty ? nil : sources.joined(separator: "\n")
    }

    private func reportAnalysis(_ reports: [AnalysisReport]) {
        Console.section("Analysis...")
        for report in reports {
            Console.detail(report.displayLine)
            if case let .fft(spectrum) = report.outcome,
               spectrum.usedPointCount < spectrum.requestedPointCount {
                Console.detail(
                    "Using all \(spectrum.usedPointCount) available samples (fewer than requested \(spectrum.requestedPointCount))",
                    level: 2,
                )
            }
        }
    }

    private func loadDecoderChannels(
        _ request: DecodeRequest,
        data: Data,
        primaryCapture: Capture,
    ) throws -> [String: Capture] {
        var result = [request.primaryChannel: primaryCapture]
        let parser = CaptureFormat.detect(in: data).parser
        for channel in request.channels where result[channel] == nil {
            result[channel] = try parser.parse(data, channel: channel)
        }
        return result
    }

    private func processDecoderChannels(
        _ captures: [String: Capture],
        primaryChannel: String,
        primaryPoints: [Point],
        transformations: [Transformation],
    ) throws -> [String: [Point]] {
        var result: [String: [Point]] = [:]
        for (channel, capture) in captures {
            if channel == primaryChannel {
                result[channel] = primaryPoints
            }
            else {
                result[channel] = try process(
                    capture.points,
                    transformations: transformations,
                    sampleInterval: capture.sampleInterval,
                    reporting: false,
                )
            }
        }
        return result
    }

    private func decode(
        _ request: DecodeRequest,
        pointsByChannel: [String: [Point]],
    ) throws -> ProtocolDecodeResult {
        func points(_ channel: String) throws -> [Point] {
            guard let points = pointsByChannel[channel] else {
                throw ParseError.channelNotFound(channelLabel: channel)
            }
            return points
        }

        let result: ProtocolDecodeResult
        switch request {
        case let .uart(request):
            Console.section("Decoding UART on \(request.channel)...")
            let decoded = try UARTDecoder(configuration: request.configuration)
                .decode(points: points(request.channel))
            Console.detail("Baud rate: \(engineeringFormatter.string(decoded.baudRate)) baud")
            Console.detail("Decoded frames: \(decoded.frames.count)")
            let invalidCount = decoded.frames.count(where: { $0.parityError || $0.framingError })
            if invalidCount > 0 {
                Console.warning(
                    "\(invalidCount) UART frame(s) have parity or framing errors; bin output omits them.",
                )
            }
            result = .uart(decoded)

        case let .i2c(request):
            Console.section("Decoding I2C on SDA=\(request.sdaChannel), SCL=\(request.sclChannel)...")
            let decoded = try I2CDecoder(configuration: request.configuration).decode(
                sdaPoints: points(request.sdaChannel),
                sclPoints: points(request.sclChannel),
            )
            Console.detail("Transactions: \(decoded.transactions.count)")
            Console.detail("Decoded bytes: \(decoded.frames.count)")
            result = .i2c(decoded)

        case let .spi(request):
            Console.section("Decoding SPI mode \(request.configuration.mode) on CLK=\(request.clockChannel)...")
            let decoded = try SPIDecoder(configuration: request.configuration).decode(
                clockPoints: points(request.clockChannel),
                mosiPoints: request.mosiChannel.map(points),
                misoPoints: request.misoChannel.map(points),
                chipSelectPoints: request.chipSelectChannel.map(points),
            )
            Console.detail("Decoded words: \(decoded.frames.count)")
            result = .spi(decoded)
        }

        let writer = DecodeWriter()
        if let outputFile = options.decodeOutput {
            Console.section("Writing decoded \(options.decodeFormat.rawValue.uppercased()) output...")
            let byteCount = try writer.write(
                result,
                format: options.decodeFormat,
                to: fileURL(for: outputFile),
            )
            Console.detail("File: \(outputFile)")
            Console.detail(
                "Saved \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))",
            )
        }
        else {
            let data = try writer.data(for: result, format: options.decodeFormat)
            FileHandle.standardOutput.write(data)
        }
        return result
    }

    private func loadInput() throws -> Data {
        Console.section("Loading input file...")
        let data = try Data(contentsOf: fileURL(for: options.inputFile))
        Console.detail("Read \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
        return data
    }

    private func parseCapture(_ data: Data, channel: String? = nil) throws -> Capture {
        Console.section("Parsing input file...")
        if data.count > 1_000_000 {
            Console.detail("(This might take a while)")
        }

        let detectedFormat = CaptureFormat.detect(in: data)
        Console.detail("Detected format: \(detectedFormat.displayName)")
        let requestedChannel = options.listChannels ? nil : (channel ?? options.channel)
        return try detectedFormat.parser.parse(data, channel: requestedChannel)
    }

    private func reportMetadata(_ metadata: CaptureMetadata?) {
        guard let metadata else {
            return
        }

        Console.detail("WFM information:")
        Console.detail("Format              : \(metadata.format)", level: 2)
        Console.detail("Model               : \(metadata.model)", level: 2)
        if let serialNumber = metadata.serialNumber {
            Console.detail("Serial number       : \(serialNumber)", level: 2)
        }
        Console.detail("Firmware            : \(metadata.firmware)", level: 2)
        Console.detail("File version        : \(metadata.fileVersion)", level: 2)
        Console.detail(
            "Structure version   : \(String(format: "0x%04X", metadata.structureVersion))",
            level: 2,
        )
        Console.detail("Acquisition mode    : \(metadata.acquisitionMode)", level: 2)
        Console.detail("Time mode           : \(metadata.timeMode)", level: 2)
        Console.detail(
            "Horizontal scale    : \(engineeringFormatter.string(metadata.horizontalScale))s/div",
            level: 2,
        )
        Console.detail(
            "Horizontal offset   : \(engineeringFormatter.string(metadata.horizontalOffset))s",
            level: 2,
        )
        Console.detail(
            "Raw memory depth    : \(numberOfPointsFormatter.string(for: metadata.memoryDepth)!) bytes",
            level: 2,
        )
        Console.detail(
            "Raw data file offset: \(String(format: "0x%X", metadata.rawDataOffset))",
            level: 2,
        )

        for channel in metadata.channels {
            let inversion = channel.inverted ? ", inverted" : ""
            Console.detail(
                "\(channel.name): \(channel.coupling), \(engineeringFormatter.string(channel.voltsPerDivision))\(channel.unit)/div, offset \(engineeringFormatter.string(channel.verticalOffset))\(channel.unit), probe \(engineeringFormatter.string(channel.probeRatio))×, \(channel.bandwidth)\(inversion)",
                level: 2,
            )
        }
        if let conversion = metadata.voltageConversion {
            Console.detail("Voltage conversion  : \(conversion)", level: 2)
        }
    }

    private func reportChannels(_ channels: [String]) {
        Console.detail("Channels:")
        for channel in channels {
            Console.detail("- \(channel)", level: 2)
        }
    }

    private func reportCapture(_ capture: Capture) {
        if let selectedChannel = capture.selectedChannel {
            Console.detail("Selected channel / expression: \(selectedChannel)")
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
        reporting: Bool = true,
    ) throws -> [Point] {
        var points = source
        var currentSampleInterval = sampleInterval

        for transformation in transformations {
            let countBefore = points.count
            if case let .removeDC(method) = transformation {
                let estimate = estimateDC(points, method: method)
                if reporting { reportTransformation(transformation, points: points, dcEstimate: estimate) }
                points = offsetPoints(points, offset: -estimate.value)
            }
            else if let kind = transformation.filterKind {
                let design = try transformation.designFilter(
                    kind: kind,
                    points: points,
                    sampleInterval: currentSampleInterval,
                )
                if reporting { reportFilter(design, transformation: transformation, points: points) }
                points = applyZeroPhaseFilter(design, to: points)
            }
            else if case let .tcn(duration, sampleCount) = transformation {
                if reporting { reportTransformation(transformation, points: points) }
                let result = try tcnForecast(
                    points,
                    duration: duration,
                    sampleCount: sampleCount,
                    sampleInterval: currentSampleInterval,
                )
                if reporting {
                    Console.detail("Automatic model: \(result.method.displayName)")
                    Console.detail("Backtest confidence: \(Int((result.confidence * 100).rounded()))%")
                    if result.confidence < 0.2 {
                        Console.warning(
                            "The capture has little repeatable information about its future. Forecast selected a conservative model; treat it as low confidence.",
                        )
                    }
                }
                points = result.points
            }
            else {
                if reporting { reportTransformation(transformation, points: points) }
                points = try transformation.applying(to: points, sampleInterval: currentSampleInterval)
            }

            if transformation.changesSampleSpacing {
                currentSampleInterval = inferredSampleInterval(from: points) ?? currentSampleInterval
            }

            if transformation.reportsPointCount {
                if reporting {
                    try reportPointCount(before: countBefore, after: points.count)
                }
                else if points.isEmpty {
                    throw Rigol2SpiceError.operationRemovedEveryPoint
                }
            }
        }

        return points
    }

    private func downsampleSignalOutput(_ source: [Point]) throws -> [Point] {
        guard let interval = options.downsample else { return source }
        Console
            .section("Downsampling signal output by \(interval)× using linear interpolation (no anti-alias filter)...")
        let points = try resamplePoints(
            source,
            factor: Double(interval),
            direction: .downsample,
            interpolation: .linear,
        )
        try reportPointCount(before: source.count, after: points.count)
        return points
    }

    private func reportTransformation(
        _ transformation: Transformation,
        points: [Point],
        dcEstimate: DCEstimate? = nil,
    ) {
        switch transformation {
        case let .removeDC(method):
            let estimate = dcEstimate ?? estimateDC(points, method: method)
            Console.section("Removing DC component (\(method.displayName))...")
            Console.detail("Automatically calculated DC component: \(engineeringFormatter.string(estimate.value))")
            if method == .dc {
                let centroids = estimate.centroids
                    .map { engineeringFormatter.string($0) }
                    .joined(separator: ", ")
                Console.detail("K-means centroids: \(centroids) (\(estimate.iterations) iterations)")
            }
        case .detrend:
            Console.section("Removing least-squares offset and linear trend...")
        case let .clampMin(value):
            Console.section("Clamping the signal above \(engineeringFormatter.string(value))...")
        case let .clampMax(value):
            Console.section("Clamping the signal below \(engineeringFormatter.string(value))...")
        case let .gate(value):
            Console.section("Gating the signal at \(engineeringFormatter.string(value))...")
        case let .offset(value):
            let sign = value >= 0 ? "+" : ""
            Console.section("Offsetting signal by \(sign)\(engineeringFormatter.string(value))...")
        case .min0:
            Console.section("Shifting signal so minimum is 0...")
        case let .addNoise(value):
            Console.section(
                "Adding Gaussian noise (σ=\(engineeringFormatter.string(value)))...",
            )
        case let .tvDenoise(value):
            Console.section(
                "Total variation denoising (λ=\(engineeringFormatter.string(value)))...",
            )
        case let .multiply(value):
            Console.section("Multiplying the signal by a factor of \(engineeringFormatter.string(value))...")
        case .invert:
            Console.section("Inverting the signal...")
        case .abs:
            Console.section("Taking the absolute value of the signal...")
        case .rectify:
            Console.section("Half-wave rectifying the signal...")
        case .normalize:
            Console.section("Normalizing the signal to unit peak-to-peak (PeakToPeak 1)...")
        case let .peakTo(value):
            Console.section("Scaling peak absolute value to \(engineeringFormatter.string(value))...")
        case let .peakToPeak(value):
            Console.section("Scaling peak-to-peak amplitude to \(engineeringFormatter.string(value))...")
        case let .scaleRMS(value):
            Console.section("Scaling RMS to \(engineeringFormatter.string(value))...")
        case let .movingAverage(window):
            Console.section("Applying moving average over \(window) samples...")
        case let .median(window):
            Console.section("Applying median filter over \(window) samples...")
        case .diff:
            Console.section("Differentiating the signal (dv/dt)...")
        case .integrate:
            Console.section("Integrating the signal...")
        case let .deadZone(value):
            Console.section("Applying dead zone of ±\(engineeringFormatter.string(value))...")
        case let .digitize(lowThreshold, highThreshold, lowOut, highOut):
            if lowThreshold == highThreshold {
                Console.section(
                    "Digitizing at \(engineeringFormatter.string(lowThreshold)) → \(engineeringFormatter.string(lowOut))/\(engineeringFormatter.string(highOut))...",
                )
            }
            else {
                Console.section(
                    "Digitizing with hysteresis \(engineeringFormatter.string(lowThreshold))/\(engineeringFormatter.string(highThreshold)) → \(engineeringFormatter.string(lowOut))/\(engineeringFormatter.string(highOut))...",
                )
            }
        case let .slewLimit(value):
            Console.section("Limiting slew rate to \(engineeringFormatter.string(value)) V/s...")
        case let .softClip(lower, upper):
            Console.section(
                "Soft-clipping the signal between \(engineeringFormatter.string(lower)) and \(engineeringFormatter.string(upper))...",
            )
        case let .fade(inDuration, outDuration):
            if inDuration > 0, outDuration > 0 {
                if inDuration == outDuration {
                    Console.section(
                        "Fading signal in/out over \(engineeringFormatter.string(inDuration))s...",
                    )
                }
                else {
                    Console.section(
                        "Fading signal in over \(engineeringFormatter.string(inDuration))s and out over \(engineeringFormatter.string(outDuration))s...",
                    )
                }
            }
            else if inDuration > 0 {
                Console.section(
                    "Fading signal in over \(engineeringFormatter.string(inDuration))s...",
                )
            }
            else {
                Console.section(
                    "Fading signal out over \(engineeringFormatter.string(outDuration))s...",
                )
            }
        case let .quantize(bits, lower, upper):
            Console.section(
                "Quantizing to \(bits) bits between \(engineeringFormatter.string(lower)) and \(engineeringFormatter.string(upper))...",
            )
        case let .limit(lower, upper):
            Console.section(
                "Limiting the signal between \(engineeringFormatter.string(lower)) and \(engineeringFormatter.string(upper))...",
            )
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
        case let .timeScale(value):
            Console.section("Scaling time axis by \(engineeringFormatter.string(value))...")
        case .trigger,
             .triggerLevel,
             .triggerSchmitt,
             .triggerNth,
             .triggerCapture,
             .triggerPulse,
             .triggerBand,
             .triggerSlew,
             .triggerDropout,
             .triggerRunt:
            Console.section(transformation.triggerSummary ?? "Applying trigger...")
        case let .seamless(rampDuration):
            if let rampDuration {
                Console.section(
                    "Making ends match with a \(engineeringFormatter.string(rampDuration))s ramp...",
                )
            }
            else {
                Console.section("Making last sample match the first (seamless loop)...")
            }
        case let .pad(duration, value):
            if let value {
                Console.section(
                    "Padding signal by \(engineeringFormatter.string(duration))s at \(engineeringFormatter.string(value))...",
                )
            }
            else {
                Console.section(
                    "Padding signal by \(engineeringFormatter.string(duration))s (hold last value)...",
                )
            }
        case let .padPoints(count, value):
            if let value {
                Console.section(
                    "Padding signal by \(count) sample points at \(engineeringFormatter.string(value))...",
                )
            }
            else {
                Console.section(
                    "Padding signal by \(count) sample points (hold last value)...",
                )
            }
        case let .extendTo(endTime, value):
            if let value {
                Console.section(
                    "Extending signal to \(engineeringFormatter.string(endTime))s at \(engineeringFormatter.string(value))...",
                )
            }
            else {
                Console.section(
                    "Extending signal to \(engineeringFormatter.string(endTime))s (hold last value)...",
                )
            }
        case let .downsample(factor, interpolation):
            if interpolation == .fast {
                Console.section(
                    "Downsampling by \(engineeringFormatter.string(factor))× in fast mode (discarding samples)...",
                )
            }
            else {
                Console.section(
                    "Downsampling by \(engineeringFormatter.string(factor))× using \(interpolation.rawValue) interpolation (no anti-alias filter)...",
                )
            }
        case let .upsample(factor, interpolation):
            Console.section(
                "Upsampling by \(engineeringFormatter.string(factor))× using \(interpolation.rawValue) interpolation...",
            )
        case let .resampleF(frequency, interpolation):
            Console.section(
                "Resampling to \(engineeringFormatter.string(frequency))Sa/s using \(interpolation.rawValue) interpolation...",
            )
        case let .extractPeriod(threshold):
            if let threshold {
                Console.section(
                    "Extracting one period (threshold \(engineeringFormatter.string(threshold)))...",
                )
            }
            else {
                Console.section("Extracting one period (auto threshold)...")
            }
        case let .cutAfter(value):
            Console.section("Cutting signal after \(engineeringFormatter.string(value))s...")
        case let .cutBefore(value):
            Console.section(
                "Cutting signal before \(engineeringFormatter.string(value))s and shifting it to t=0...",
            )
        case let .dropLast(duration):
            Console.section(
                "Removing the final \(engineeringFormatter.string(duration))s of the signal...",
            )
        case let .dropLastPoints(count):
            Console.section("Removing the final \(count) sample points...")
        case let .trim(start, end):
            Console.section(
                "Trimming signal from \(engineeringFormatter.string(start))s to \(engineeringFormatter.string(end))s and shifting it to t=0...",
            )
        case let .repeat(amount):
            Console.section("Repeating capture for \(engineeringFormatter.string(amount)) times...")
        case let .oversample(factor):
            Console.section(
                "Averaging \(factor) equal capture segments to improve amplitude resolution...",
            )
        case let .tcn(duration, sampleCount):
            if let sampleCount {
                Console.section(
                    "Forecasting \(engineeringFormatter.string(duration))s as \(sampleCount) samples automatically...",
                )
            }
            else {
                Console.section(
                    "Forecasting \(engineeringFormatter.string(duration))s automatically...",
                )
            }
        case let .am(carrier, depth, amplitude):
            Console.section(
                "AM-modulating at \(engineeringFormatter.string(carrier))Hz (depth \(engineeringFormatter.string(depth)), carrier amplitude \(engineeringFormatter.string(amplitude)))...",
            )
        case let .fm(carrier, sensitivity, amplitude):
            Console.section(
                "FM-modulating at \(engineeringFormatter.string(carrier))Hz (sensitivity \(engineeringFormatter.string(sensitivity))Hz/unit, carrier amplitude \(engineeringFormatter.string(amplitude)))...",
            )
        case let .pm(carrier, sensitivity, amplitude):
            Console.section(
                "PM-modulating at \(engineeringFormatter.string(carrier))Hz (sensitivity \(engineeringFormatter.string(sensitivity))rad/unit, carrier amplitude \(engineeringFormatter.string(amplitude)))...",
            )
        case let .demodAM(carrier, depth, cutoff):
            Console.section(
                "AM-demodulating at \(engineeringFormatter.string(carrier))Hz (depth \(engineeringFormatter.string(depth)), baseband cutoff \(engineeringFormatter.string(cutoff))Hz)...",
            )
        case let .demodFM(carrier, sensitivity, cutoff):
            Console.section(
                "FM-demodulating at \(engineeringFormatter.string(carrier))Hz (sensitivity \(engineeringFormatter.string(sensitivity))Hz/unit, baseband cutoff \(engineeringFormatter.string(cutoff))Hz)...",
            )
        case let .demodPM(carrier, sensitivity, cutoff):
            Console.section(
                "PM-demodulating at \(engineeringFormatter.string(carrier))Hz (sensitivity \(engineeringFormatter.string(sensitivity))rad/unit, baseband cutoff \(engineeringFormatter.string(cutoff))Hz)...",
            )
        case let .lowPass(cutoff):
            Console.section("Applying automatic low-pass filter at \(engineeringFormatter.string(cutoff))Hz...")
        case let .highPass(cutoff):
            Console.section("Applying automatic high-pass filter at \(engineeringFormatter.string(cutoff))Hz...")
        case let .bandPass(low, high):
            Console.section(
                "Applying automatic band-pass filter from \(engineeringFormatter.string(low))Hz to \(engineeringFormatter.string(high))Hz...",
            )
        case let .bandStop(low, high):
            Console.section(
                "Applying automatic band-stop filter from \(engineeringFormatter.string(low))Hz to \(engineeringFormatter.string(high))Hz...",
            )
        case let .notch(center, width):
            Console.section(
                "Applying zero-phase IIR notch at \(engineeringFormatter.string(center))Hz with width \(engineeringFormatter.string(width))Hz...",
            )
        }
    }

    private func reportFilter(
        _ design: DigitalFilterDesign,
        transformation _: Transformation,
        points: [Point],
    ) {
        switch design.kind {
        case let .lowPass(cutoff):
            Console.section("Applying automatic low-pass filter at \(engineeringFormatter.string(cutoff))Hz...")
        case let .highPass(cutoff):
            Console.section("Applying automatic high-pass filter at \(engineeringFormatter.string(cutoff))Hz...")
        case let .bandPass(low, high):
            Console.section(
                "Applying automatic band-pass filter from \(engineeringFormatter.string(low))Hz to \(engineeringFormatter.string(high))Hz...",
            )
        case let .bandStop(low, high):
            Console.section(
                "Applying automatic band-stop filter from \(engineeringFormatter.string(low))Hz to \(engineeringFormatter.string(high))Hz...",
            )
        case let .notch(center, width):
            Console.section(
                "Applying automatic notch at \(engineeringFormatter.string(center))Hz with width \(engineeringFormatter.string(width))Hz...",
            )
        }

        Console.detail("Type: IIR biquad sections, forward and reverse (zero phase)")
        Console.detail("Sections: \(design.sections.count)")
        Console.detail("Sample rate: \(engineeringFormatter.string(design.sampleRate))sa/s")
        Console.detail("Estimated settling time: \(engineeringFormatter.string(design.settlingTime))s")

        if let first = points.first, let last = points.last,
           last.time - first.time < 2 * design.settlingTime {
            Console.warning(
                "This capture is short relative to the selected frequencies. "
                    +
                    "Filtering remains automatic, but rejection near the boundaries may improve with a longer capture.",
            )
        }
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

        Console.section("Writing \(options.format.rawValue.uppercased()) output file...")
        Console.detail("Number of sample points: \(numberOfPointsFormatter.string(for: points.count)!)")

        let outputURL = fileURL(for: outputFile)
        let byteCount = switch options.format {
        case .pwl:
            try PWLWriter().write(points, to: outputURL)
        case .matlab:
            try MATLABWriter().write(points, to: outputURL)
        case .wav32:
            try WAVWriter(encoding: .float32).write(points, to: outputURL)
        case .wav16:
            try WAVWriter(encoding: .pcm16).write(points, to: outputURL)
        case .npy:
            try NPYWriter().write(points.map(\.value), to: outputURL)
        case .npz:
            try NPZWriter().write(points, to: outputURL)
        }

        let firstTime = points[0].time
        let lastTime = points[points.count - 1].time
        Console.detail("First sample: \(engineeringFormatter.string(firstTime))s")
        Console.detail("Last sample: \(engineeringFormatter.string(lastTime))s")
        Console.detail("Capture duration: \(engineeringFormatter.string(lastTime + sampleInterval))s")
        Console
            .detail("Saving file: \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))...")
    }

    private func writePlot(
        _ points: [Point],
        to filename: String,
        sourceFile: String,
        channel: String,
        analysisReports: [AnalysisReport] = [],
        decodeResult: ProtocolDecodeResult? = nil,
    ) throws {
        if points.count > PlotWriter.largePlotPointThreshold {
            Console.warning(
                "Plot has \(numberOfPointsFormatter.string(for: points.count)!) points. "
                    + "Large SVG files may be slow or unstable to open. "
                    + "Prefer --downsample or Trim/CutAfter/CutBefore to plot a shorter segment.",
            )
        }

        Console.section("Writing SVG plot...")
        Console.detail("File: \(filename)")
        Console.detail("Source: \(sourceFile)")
        Console.detail("Channel / expression: \(channel)")
        Console.detail("Number of sample points: \(numberOfPointsFormatter.string(for: points.count)!)")
        Console.detail("Plot width: \(points.count)px (1 px per sample)")
        if !analysisReports.isEmpty {
            Console.detail("Including \(analysisReports.count) analysis result(s)")
        }

        let url = fileURL(for: filename)
        let byteCount = try PlotWriter.write(
            points,
            to: url,
            sourceFile: sourceFile,
            channel: channel,
            analysisReports: analysisReports,
            decodeTitle: decodeResult?.plotTitle,
            decodeAnnotations: decodeResult?.plotAnnotations ?? [],
        )
        Console.detail(
            "Saving file: \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))...",
        )
    }

    private func fileURL(for filename: String) -> URL {
        let expandedPath = NSString(string: filename).expandingTildeInPath
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return URL(fileURLWithPath: expandedPath, relativeTo: workingDirectory).standardizedFileURL
    }
}
