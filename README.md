# rigol2spice

**Import real oscilloscope captures into your SPICE simulations.**

Converts Rigol oscilloscope CSV exports to PWL (Piece-Wise Linear) files for LTspice and other SPICE simulators. Supports both legacy and newer Centaurus-platform Rigol scopes.

[![YouTube video](https://img.youtube.com/vi/AaCvPtJ-cZM/0.jpg)](https://www.youtube.com/watch?v=AaCvPtJ-cZM)

[Watch on YouTube](https://www.youtube.com/watch?v=AaCvPtJ-cZM)

## Quick Start

[Download the latest release](https://github.com/RuiCarneiro/rigol2spice/releases), then:

```
rigol2spice input.csv output.txt
```

For newer Centaurus-platform scopes (e.g. DHO800/900 series), add `-n`:

```
rigol2spice -n input.csv output.txt
```

The output `.txt` file can be loaded directly as a PWL source in LTspice.

## Channel Selection

List available channels in a CSV with `-l` or `--list-channels`:

```
rigol2spice -l input.csv
```

Select a specific channel (default is `CH1`) with `-c` or `-channel`:

```
rigol2spice -c CH2 input.csv output.txt
```

Combine channels with `+`, `-`, `*`, and `/` (standard precedence; parentheses allowed). Transformations then apply to the result:

```
rigol2spice -c 'CH1+CH2' input.csv output.txt
rigol2spice -c '(CH1-CH2)/CH3' input.csv output.txt
rigol2spice -c 'CH1-CH2' -t 'RemoveDC' input.csv output.txt
```

## Transformations

Pass an ordered list of transformation commands with `-t` or `--transformations`. Separate commands with semicolons and quote the complete string for the shell:

```
rigol2spice input.csv output.txt -t 'RemoveDC; ClampMax 0.7; Offset -1.2'
```

Commands use the syntax `OPERATION argument`. Operation names are case-insensitive. Scalars accept decimal (`0.7`), engineering (`3n`, `10u`), and scientific (`5e-3`) notation. Use `-` for negative values. Transformations run strictly from left to right.

### Amplitude & level

| Operation | Example | Effect |
|---|---|---|
| `RemoveDC` | `RemoveDC` | Estimate and subtract the DC component¹ |
| `Offset` | `Offset -1.5` | Add the scalar to every value |
| `Multiply` | `Multiply 10` | Multiply every value by the scalar |
| `Invert` | `Invert` | Multiply every value by −1 (alias of `Multiply -1`) |
| `PeakTo` | `PeakTo 3.3` | Scale so the peak absolute value equals the scalar |
| `Normalize` | `Normalize` | Alias of `PeakTo 1` |
| `dB` | `dB 6` | Scale amplitude by the given voltage dB (×10^(dB/20)) |
| `dBmW` | `dBmW 10` · `dBmW 0, 75` | × volts for that power into R Ω (e.g. 10 dBm @ 50 Ω ≈ 0.707 V)³ |
| `dBW` | `dBW 0` · `dBW -30` | Same as `dBmW` but relative to 1 W (0 dBW = 30 dBm ≈ 7.07 V @ 50 Ω)³ |

### Clipping, gates & shaping

| Operation | Example | Effect |
|---|---|---|
| `ClampMin` | `ClampMin 0` | Clamp values below the scalar |
| `ClampMax` | `ClampMax 3.3` | Clamp values above the scalar |
| `Limit` | `Limit -0.7, 0.7` | Clamp values between low and high |
| `Gate` | `Gate 0.6` | Zero values below the threshold; keep the rest |
| `DeadZone` | `DeadZone 0.1` | Zero values inside ±threshold; keep the rest |
| `Digitize` | `Digitize 0.8` · `Digitize 0.8, 0, 3.3` · `Digitize 1.2, 0.8, 0, 3.3` | Two-level digital output (threshold; low/high out; optional Schmitt hysteresis); alias `Threshold` |
| `Abs` | `Abs` | Replace every value with its absolute value |
| `Rectify` | `Rectify` | Half-wave rectify (keep values ≥ 0, zero the rest) |

### Time domain

| Operation | Example | Effect |
|---|---|---|
| `TimeShift` | `TimeShift -5m` | Shift timestamps; negative values shift left |
| `TimeScale` | `TimeScale 2` · `TimeScale 0.5` | Scale the time axis (preserve start time); alias `Stretch` |
| `AlignEdge` | `AlignEdge rising, 0.5` · `AlignEdge falling, 1.5, 2m` | Shift so the first rising/falling crossing of the threshold is at t=0 (optional search-after time); alias `TriggerAt` |
| `Seamless` | `Seamless` · `Seamless 100n` | Force last value = first (or append a ramp of the given duration); alias `MatchEnds` |
| `Pad` | `Pad 5m` · `Pad 5m, 0` | Extend by a duration, holding the last value (or a given level); alias `HoldLast` |
| `ExtendTo` | `ExtendTo 10m` · `ExtendTo 10m, 0` | Extend to an absolute end time, holding the last value (or a given level) |
| `CutBefore` | `CutBefore 5m` | Discard samples before the timestamp |
| `CutAfter` | `CutAfter 10u` | Discard samples at or after the timestamp |
| `Trim` | `Trim 1m, 10m` | Keep samples with start ≤ t < end |
| `Repeat` | `Repeat 2.5` | Append copies of the capture⁴ |

### Filtering & calculus

| Operation | Example | Effect |
|---|---|---|
| `LowPass` | `LowPass 1k` | Apply a low-pass filter² |
| `HighPass` | `HighPass 100` | Apply a high-pass filter² |
| `BandPass` | `BandPass 900, 1.1k` | Apply a band-pass filter² |
| `BandStop` | `BandStop 48, 52` | Apply a band-stop filter² |
| `MovingAverage` | `MovingAverage 5` | Centered moving average over N samples |
| `Diff` | `Diff` | Numerical derivative dv/dt |
| `Integrate` | `Integrate` | Cumulative trapezoidal integral (starts at 0) |

¹ `RemoveDC` estimates the DC component from the capture by applying one-dimensional k-means clustering with `k = 3` to all finite sample values. Several deterministic initializations are evaluated and the clustering with the smallest squared error is selected. The DC estimate is the midpoint between the lower and upper centroids.

² Filters are linear-phase windowed-sinc FIRs (Blackman–Harris). You only supply the cutoff frequency(ies); the sample rate comes from the capture, tap count is chosen automatically, and group delay is removed so event timing stays aligned. Frequencies must be greater than 0 and below Nyquist (`fs/2`). Band filters require `0 < f1 < f2`.

³ `dBmW` (alias `dBm`) and `dBW` convert an absolute power level to a voltage scale factor: `V = √(P · R)`, with `P = 1 mW · 10^(dBmW/10)` or `P = 1 W · 10^(dBW/10)`. Optional second argument is load impedance in ohms (default 50). Unlike `dB`, these are not relative gains — they multiply the waveform by that absolute voltage (useful for unit-amplitude templates).

⁴ `Repeat` requires a value greater than zero and accepts fractional repetitions; its final point is interpolated when needed.

### Post-processing Options

| Option | Effect |
|---|---|
| `-d, --downsample N` | Keep every Nth sample (e.g. `2` halves the sample rate) |
| `-k, --keep-all` | Disable removal of redundant (collinear) points |
| `-p, --plot [file]` | Write an SVG plot of the processed signal (default: `plot.svg`) |

The PWL output file is optional when using `--list-channels` or `--plot`. The plot uses 1 pixel per sample, auto-scaled Y (min / avg / max markers), and decade-spaced X time markers. A console warning is emitted above 10 000 points (prefer downsample or a shorter time window).

## Example: Extract One Period and Repeat

```
rigol2spice -t 'TimeShift -5m; CutAfter 7.5m; Repeat 2' input.csv output.txt
```

1. Shift waveform 5 ms left (removes the first 5 ms, then time starts at 0)
2. Cut at 7.5 ms (keeps only 0 -- 7.5 ms of the shifted waveform)
3. Repeat 2 times (creates 3 total copies -- original + 2 repetitions = 22.5 ms total)

## Full Usage Reference

```
USAGE: rigol2spice [<options>] <input-file> [<output-file>]

OPTIONS:
  -n,  --new-models               Newer Rigol Centaurus platform format
  -l,  --list-channels            List channels and exit
  -c,  --channel <channel>        Channel or math expression (default: CH1)
  -t,  --transformations <value>  Ordered transformations separated by semicolons
  -d,  --downsample <ratio>       Downsample ratio
  -k,  --keep-all                 Keep all sample points
  -p,  --plot [<file>]            Write SVG plot (default: plot.svg)
  -h,  --help                     Show help
```

`output-file` is optional with `-l` or `-p`.

## Building from Source

Requires Swift 6.2+.

```
swift build
```

Builds on macOS, Windows, and Linux.

## Legal

This is an independent project, not affiliated with Rigol Technologies, Inc.
