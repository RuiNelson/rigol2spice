# Repository Guidelines

## Project Structure & Module Organization

This repository is a Swift Package Manager command-line application. `Package.swift` defines the `rigol2spice` executable and its pinned dependencies. Production code lives in `Sources/rigol2spice/`: `entry.swift` owns argument parsing and the processing pipeline, `transformations.swift` parses ordered transformations, `parser.swift` and `parser-new.swift` read legacy and Centaurus CSV formats, and `xTransforms.swift`/`yTransforms.swift` apply signal transforms. XCTest code belongs in `Tests/rigol2spiceTests/`. Keep generated `.build/`, `.swiftpm/`, and `Package.resolved` files untracked as specified by `.gitignore`.

## Build, Test, and Development Commands

- `swift build` — resolve exact dependency versions and compile a debug executable.
- `swift build -c release` — create an optimized binary under `.build/release/`.
- `swift run rigol2spice --help` — run the CLI locally and inspect supported options.
- `swift run rigol2spice input.csv output.txt` — exercise a legacy CSV conversion; add `-n` for Centaurus-format captures.
- `swift test` — build and execute the XCTest target.
- `swiftformat .` — format all Swift source and test files.

## Coding Style & Naming Conventions

Run `swiftformat .` before submitting changes. Follow Swift naming conventions: `UpperCamelCase` for types, `lowerCamelCase` for functions and properties, and descriptive enum cases. Preserve established package and compatibility filenames such as `rigol2spice` and `parser-new.swift`.

## Testing Guidelines

Write XCTest cases named `testBehaviorUnderCondition()` in `rigol2spiceTests.swift` or focused sibling test files. Cover parser variants, engineering notation, transform edge cases, CLI exit status, and exact PWL output. Use temporary directories for generated output and keep any CSV fixtures small. There is no formal coverage threshold, but each behavior change should include a regression test.

## Commit & Pull Request Guidelines

Use short, imperative commit subjects consistent with history, for example `Fix repeat example in README`; avoid vague messages such as `code cleanup`. Keep commits focused. Pull requests should explain the user-visible change, list verification commands and results, link relevant issues, and include a minimal CSV/CLI example when conversion behavior changes. Call out format-specific effects (`legacy` versus `-n`) and update `README.md` for option or usage changes.
