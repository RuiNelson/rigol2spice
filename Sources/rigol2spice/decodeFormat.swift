import ArgumentParser

/// Serialization format for protocol-decoder results.
enum DecodeFormat: String, CaseIterable, ExpressibleByArgument {
    /// Human-readable, line-oriented output.
    case text
    /// One lossless row per decoded frame.
    case csv
    /// Only the decoded payload bytes, with no metadata.
    case bin
}
