import Foundation

// MARK: - TriggerLevel

enum TriggerLevel: Equatable, CustomStringConvertible {
    case value(Double)
    case automatic
    case percent(Double)

    var description: String {
        switch self {
        case let .value(value): engineeringFormatter.string(value)
        case .automatic: "auto"
        case let .percent(percent): "\(engineeringFormatter.string(percent))%"
        }
    }

    func resolved(on points: [Point]) -> Double? {
        switch self {
        case let .value(value):
            value
        case .automatic:
            topBaseLevels(points).map { ($0.base + $0.top) / 2 }
        case let .percent(percent):
            topBaseLevels(points).map { levels in
                levels.base + (levels.top - levels.base) * percent / 100
            }
        }
    }
}

// MARK: - TriggerPulsePolarity

enum TriggerPulsePolarity: String, Equatable, CustomStringConvertible {
    case high
    case low

    var description: String {
        rawValue
    }
}

// MARK: - TriggerBandMode

enum TriggerBandMode: String, Equatable, CustomStringConvertible {
    case enter
    case exit
    case above
    case below

    var description: String {
        rawValue
    }
}

// MARK: - TriggerEvent

struct TriggerEvent: Equatable {
    let time: Double
    let value: Double
}

// MARK: - Shared event helpers

func thresholdTriggerEvent(
    _ points: [Point],
    edge: TriggerEdge,
    threshold: Double,
    after: Double? = nil,
    occurrence: Int = 1,
) -> TriggerEvent? {
    guard points.count >= 2, occurrence >= 1 else {
        return nil
    }
    var remaining = occurrence
    for index in 1 ..< points.count {
        let previous = points[index - 1]
        let current = points[index]
        let crossedUp = previous.value < threshold && current.value >= threshold
        let crossedDown = previous.value > threshold && current.value <= threshold
        let crossed = switch edge {
        case .rising: crossedUp
        case .falling: crossedDown
        case .either: crossedUp || crossedDown
        }
        guard crossed else {
            continue
        }
        let time = interpolatedCrossingTime(previous: previous, current: current, threshold: threshold)
        if let after, time < after {
            continue
        }
        remaining -= 1
        if remaining == 0 {
            return TriggerEvent(time: time, value: threshold)
        }
    }
    return nil
}

func alignToTriggerEvent(_ points: [Point], event: TriggerEvent) -> [Point] {
    var shifted = timeShiftPoints(points, value: -event.time)
    if shifted.isEmpty || shifted[0].time > 0 {
        shifted.insert(Point(time: 0, value: event.value), at: 0)
    }
    else {
        shifted[0] = Point(time: 0, value: event.value)
    }
    return shifted
}

private func valueAtTime(_ time: Double, in points: [Point]) -> Double? {
    guard let first = points.first, let last = points.last,
          time >= first.time, time <= last.time else {
        return nil
    }
    if time == first.time {
        return first.value
    }
    for index in 1 ..< points.count {
        let previous = points[index - 1]
        let current = points[index]
        guard time <= current.time else {
            continue
        }
        let dt = current.time - previous.time
        guard dt > 0 else {
            return current.value
        }
        let fraction = (time - previous.time) / dt
        return previous.value + fraction * (current.value - previous.value)
    }
    return last.value
}

private func capturedWindow(
    _ points: [Point],
    event: TriggerEvent,
    pre: Double,
    post: Double,
) -> [Point] {
    guard let first = points.first, let last = points.last else {
        return []
    }
    let start = max(first.time, event.time - pre)
    let end = min(last.time, event.time + post)
    guard end >= start,
          let startValue = valueAtTime(start, in: points),
          let endValue = valueAtTime(end, in: points) else {
        return []
    }

    var selected = [Point(time: start, value: startValue)]
    selected.append(contentsOf: points.filter { $0.time > start && $0.time < end })
    if event.time > start, event.time < end {
        selected.append(Point(time: event.time, value: event.value))
    }
    if end > start {
        selected.append(Point(time: end, value: endValue))
    }
    selected.sort { $0.time < $1.time }

    var deduplicated: [Point] = []
    for point in selected {
        if let lastIndex = deduplicated.indices.last, deduplicated[lastIndex].time == point.time {
            deduplicated[lastIndex] = point
        }
        else {
            deduplicated.append(point)
        }
    }
    return deduplicated.map { Point(time: $0.time - start, value: $0.value) }
}

private func resolvedThreshold(_ level: TriggerLevel, points: [Point], operation: String) throws -> Double {
    guard let threshold = level.resolved(on: points), threshold.isFinite else {
        throw Rigol2SpiceError.triggerEventNotFound(operation: operation)
    }
    return threshold
}

// MARK: - Level / Nth / Capture

func triggerLevelPoints(
    _ points: [Point],
    edge: TriggerEdge,
    level: TriggerLevel,
    after: Double?,
) throws -> [Point] {
    let threshold = try resolvedThreshold(level, points: points, operation: "Trigger")
    guard let event = thresholdTriggerEvent(points, edge: edge, threshold: threshold, after: after) else {
        throw Rigol2SpiceError.edgeNotFound(edge: edge, threshold: threshold)
    }
    return alignToTriggerEvent(points, event: event)
}

func triggerNthPoints(
    _ points: [Point],
    edge: TriggerEdge,
    level: TriggerLevel,
    occurrence: Int,
    after: Double?,
) throws -> [Point] {
    let threshold = try resolvedThreshold(level, points: points, operation: "TriggerNth")
    guard let event = thresholdTriggerEvent(
        points,
        edge: edge,
        threshold: threshold,
        after: after,
        occurrence: occurrence,
    ) else {
        throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerNth")
    }
    return alignToTriggerEvent(points, event: event)
}

func triggerCapturePoints(
    _ points: [Point],
    edge: TriggerEdge,
    level: TriggerLevel,
    pre: Double,
    post: Double,
    after: Double?,
) throws -> [Point] {
    let threshold = try resolvedThreshold(level, points: points, operation: "TriggerCapture")
    guard let event = thresholdTriggerEvent(points, edge: edge, threshold: threshold, after: after) else {
        throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerCapture")
    }
    return capturedWindow(points, event: event, pre: pre, post: post)
}

// MARK: - Schmitt

func triggerSchmittPoints(
    _ points: [Point],
    edge: TriggerEdge,
    low: Double,
    high: Double,
    after: Double?,
) throws -> [Point] {
    guard let first = points.first, points.count >= 2 else {
        throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerSchmitt")
    }
    var risingArmed = first.value <= low
    var fallingArmed = first.value >= high

    for index in 1 ..< points.count {
        let previous = points[index - 1]
        let current = points[index]
        var candidates: [TriggerEvent] = []

        if risingArmed, previous.value < high, current.value >= high {
            let time = interpolatedCrossingTime(previous: previous, current: current, threshold: high)
            risingArmed = false
            if edge != .falling, after.map({ time >= $0 }) ?? true {
                candidates.append(TriggerEvent(time: time, value: high))
            }
        }
        if fallingArmed, previous.value > low, current.value <= low {
            let time = interpolatedCrossingTime(previous: previous, current: current, threshold: low)
            fallingArmed = false
            if edge != .rising, after.map({ time >= $0 }) ?? true {
                candidates.append(TriggerEvent(time: time, value: low))
            }
        }

        if let event = candidates.min(by: { $0.time < $1.time }) {
            return alignToTriggerEvent(points, event: event)
        }
        if current.value <= low {
            risingArmed = true
        }
        if current.value >= high {
            fallingArmed = true
        }
    }
    throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerSchmitt")
}

// MARK: - Pulse / Band

func triggerPulsePoints(
    _ points: [Point],
    polarity: TriggerPulsePolarity,
    level: TriggerLevel,
    minimumWidth: Double,
    maximumWidth: Double?,
) throws -> [Point] {
    let threshold = try resolvedThreshold(level, points: points, operation: "TriggerPulse")
    let crossings = directedLevelCrossings(points, threshold: threshold)
    for index in 0 ..< max(0, crossings.count - 1) {
        let start = crossings[index]
        let end = crossings[index + 1]
        let correctPolarity = switch polarity {
        case .high: start.rising && !end.rising
        case .low: !start.rising && end.rising
        }
        guard correctPolarity else {
            continue
        }
        let width = end.time - start.time
        guard width >= minimumWidth else {
            continue
        }
        if let maximumWidth, width > maximumWidth {
            continue
        }
        return alignToTriggerEvent(points, event: TriggerEvent(time: start.time, value: threshold))
    }
    throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerPulse")
}

func triggerBandPoints(
    _ points: [Point],
    mode: TriggerBandMode,
    low: Double,
    high: Double,
    after: Double?,
) throws -> [Point] {
    guard points.count >= 2 else {
        throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerBand")
    }
    for index in 1 ..< points.count {
        let previous = points[index - 1]
        let current = points[index]
        var candidates: [TriggerEvent] = []

        func addCrossing(_ threshold: Double) {
            let time = interpolatedCrossingTime(previous: previous, current: current, threshold: threshold)
            if after.map({ time >= $0 }) ?? true {
                candidates.append(TriggerEvent(time: time, value: threshold))
            }
        }

        switch mode {
        case .enter:
            if previous.value < low, current.value >= low { addCrossing(low) }
            if previous.value > high, current.value <= high { addCrossing(high) }
        case .exit:
            if previous.value <= high, current.value > high { addCrossing(high) }
            if previous.value >= low, current.value < low { addCrossing(low) }
        case .above:
            if previous.value <= high, current.value > high { addCrossing(high) }
        case .below:
            if previous.value >= low, current.value < low { addCrossing(low) }
        }
        if let event = candidates.min(by: { $0.time < $1.time }) {
            return alignToTriggerEvent(points, event: event)
        }
    }
    throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerBand")
}

// MARK: - Slew / Dropout / Runt

func triggerSlewPoints(
    _ points: [Point],
    edge: TriggerEdge,
    lowPercent: Double,
    highPercent: Double,
    minimumRate: Double,
    maximumRate: Double?,
) throws -> [Point] {
    guard let range = valueRange(points) else {
        throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerSlew")
    }
    let span = range.maximum - range.minimum
    guard span > 0 else {
        throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerSlew")
    }
    let lowLevel = range.minimum + span * lowPercent / 100
    let highLevel = range.minimum + span * highPercent / 100
    let rising = edge == .rising
    let startLevel = rising ? lowLevel : highLevel
    let endLevel = rising ? highLevel : lowLevel
    let starts = directedLevelCrossings(points, threshold: startLevel).filter { $0.rising == rising }
    let ends = directedLevelCrossings(points, threshold: endLevel).filter { $0.rising == rising }

    for start in starts {
        guard let end = ends.first(where: { $0.time > start.time }) else {
            continue
        }
        let rate = abs(endLevel - startLevel) / (end.time - start.time)
        guard rate >= minimumRate else {
            continue
        }
        if let maximumRate, rate > maximumRate {
            continue
        }
        return alignToTriggerEvent(points, event: TriggerEvent(time: start.time, value: startLevel))
    }
    throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerSlew")
}

func triggerDropoutPoints(
    _ points: [Point],
    edge: TriggerEdge,
    level: TriggerLevel,
    duration: Double,
    after: Double?,
) throws -> [Point] {
    let threshold = try resolvedThreshold(level, points: points, operation: "TriggerDropout")
    let crossings = directedLevelCrossings(points, threshold: threshold).filter { crossing in
        let matchesEdge = switch edge {
        case .rising: crossing.rising
        case .falling: !crossing.rising
        case .either: true
        }
        return matchesEdge && (after.map { crossing.time >= $0 } ?? true)
    }
    guard let captureEnd = points.last?.time else {
        throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerDropout")
    }
    for index in crossings.indices {
        let deadline = crossings[index].time + duration
        if index + 1 < crossings.count, crossings[index + 1].time <= deadline {
            continue
        }
        guard captureEnd >= deadline,
              let value = valueAtTime(deadline, in: points) else {
            continue
        }
        return alignToTriggerEvent(points, event: TriggerEvent(time: deadline, value: value))
    }
    throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerDropout")
}

func triggerRuntPoints(
    _ points: [Point],
    edge: TriggerEdge,
    low: Double,
    high: Double,
    maximumDuration: Double,
) throws -> [Point] {
    let rising = edge == .rising
    let startLevel = rising ? low : high
    let targetLevel = rising ? high : low
    let starts = directedLevelCrossings(points, threshold: startLevel).filter { $0.rising == rising }
    let targets = directedLevelCrossings(points, threshold: targetLevel).filter { $0.rising == rising }
    let returns = directedLevelCrossings(points, threshold: startLevel).filter { $0.rising != rising }
    guard let captureEnd = points.last?.time else {
        throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerRunt")
    }

    for start in starts {
        let deadline = start.time + maximumDuration
        guard captureEnd >= deadline else {
            continue
        }
        let target = targets.first(where: { $0.time > start.time })
        let returnCrossing = returns.first(where: { $0.time > start.time })
        if let returnCrossing, returnCrossing.time <= deadline {
            let returnedBeforeTarget = target.map { returnCrossing.time < $0.time } ?? true
            if returnedBeforeTarget {
                return alignToTriggerEvent(points, event: TriggerEvent(time: start.time, value: startLevel))
            }
        }
        if let target, target.time <= deadline {
            continue
        }
        return alignToTriggerEvent(points, event: TriggerEvent(time: start.time, value: startLevel))
    }
    throw Rigol2SpiceError.triggerEventNotFound(operation: "TriggerRunt")
}

// MARK: - Console descriptions

extension Transformation {
    var triggerSummary: String? {
        func afterSuffix(_ after: Double?) -> String {
            after.map { " after \(engineeringFormatter.string($0))s" } ?? ""
        }

        return switch self {
        case let .trigger(edge, threshold, after):
            "Triggering on \(edge) edge at \(engineeringFormatter.string(threshold))\(afterSuffix(after)) to t=0..."
        case let .triggerLevel(edge, level, after):
            "Triggering on \(edge) edge at \(level)\(afterSuffix(after)) to t=0..."
        case let .triggerSchmitt(edge, low, high, after):
            "Triggering with \(edge) Schmitt levels \(engineeringFormatter.string(low))/\(engineeringFormatter.string(high))\(afterSuffix(after))..."
        case let .triggerNth(edge, level, occurrence, after):
            "Triggering on \(edge) edge #\(occurrence) at \(level)\(afterSuffix(after))..."
        case let .triggerCapture(edge, level, pre, post, after):
            "Capturing \(engineeringFormatter.string(pre))s before and \(engineeringFormatter.string(post))s after \(edge) trigger at \(level)\(afterSuffix(after))..."
        case let .triggerPulse(polarity, level, minimumWidth, maximumWidth):
            if let maximumWidth {
                "Triggering on \(polarity) pulse at \(level), width \(engineeringFormatter.string(minimumWidth))s...\(engineeringFormatter.string(maximumWidth))s..."
            }
            else {
                "Triggering on \(polarity) pulse at \(level), minimum width \(engineeringFormatter.string(minimumWidth))s..."
            }
        case let .triggerBand(mode, low, high, after):
            "Triggering when signal goes \(mode) band \(engineeringFormatter.string(low))...\(engineeringFormatter.string(high))\(afterSuffix(after))..."
        case let .triggerSlew(edge, lowPercent, highPercent, minimumRate, maximumRate):
            if let maximumRate {
                "Triggering on \(edge) slew \(engineeringFormatter.string(lowPercent))%...\(engineeringFormatter.string(highPercent))%, rate \(engineeringFormatter.string(minimumRate))...\(engineeringFormatter.string(maximumRate)) units/s..."
            }
            else {
                "Triggering on \(edge) slew \(engineeringFormatter.string(lowPercent))%...\(engineeringFormatter.string(highPercent))%, minimum \(engineeringFormatter.string(minimumRate)) units/s..."
            }
        case let .triggerDropout(edge, level, duration, after):
            "Triggering after \(engineeringFormatter.string(duration))s without a \(edge) edge at \(level)\(afterSuffix(after))..."
        case let .triggerRunt(edge, low, high, maximumDuration):
            "Triggering on \(edge) runt between \(engineeringFormatter.string(low)) and \(engineeringFormatter.string(high)) within \(engineeringFormatter.string(maximumDuration))s..."
        default:
            nil
        }
    }
}
