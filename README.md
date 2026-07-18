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

The output `.txt` file can be loaded directly as a PWL source in LTspice and other SPICE simulators.

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
| `AddNoise` | `AddNoise 10m` | Add zero-mean Gaussian noise with standard deviation equal to the scalar |
| `TVDenoise` | `TVDenoise 50m` | 1D total variation denoising with weight λ (piecewise-constant bias; preserves edges)⁶ |
| `Multiply` | `Multiply 10` | Multiply every value by the scalar |
| `Invert` | `Invert` | Multiply every value by −1 (alias of `Multiply -1`) |
| `PeakTo` | `PeakTo 3.3` | Scale so the peak absolute value equals the scalar |
| `PeakToPeak` | `PeakToPeak 2` | Scale so max − min equals the scalar |
| `Normalize` | `Normalize` | Alias of `PeakToPeak 1` |
| `ScaleRMS` | `ScaleRMS 707m` | Scale so the sample RMS equals the scalar |
| `dB` | `dB 6` | Scale amplitude by the given voltage dB (×10^(dB/20)) |
| `dBmW` | `dBmW 10` · `dBmW 0, 75` | × volts for that power into R Ω (e.g. 10 dBm @ 50 Ω ≈ 0.707 V)³ |
| `dBm` | `dBm 10` | Alias of `dBmW` |
| `dBW` | `dBW 0` · `dBW -30` | Same as `dBmW` but relative to 1 W (0 dBW = 30 dBm ≈ 7.07 V @ 50 Ω)³ |

### Clipping, gates & shaping

| Operation | Example | Effect |
|---|---|---|
| `ClampMin` | `ClampMin 0` | Clamp values below the scalar |
| `ClampMax` | `ClampMax 3.3` | Clamp values above the scalar |
| `Limit` | `Limit -0.7, 0.7` | Clamp values between low and high |
| `Gate` | `Gate 0.6` | Zero values below the threshold; keep the rest |
| `DeadZone` | `DeadZone 0.1` | Zero values inside ±threshold; keep the rest |
| `Digitize` | `Digitize 1.5` · `Digitize 1.5, 0, 3.3` · `Digitize 1.2, 1.8, 0, 3.3` | Map each sample to one of two levels (hard threshold or Schmitt)⁵ |
| `Threshold` | `Threshold 1.5` | Alias of `Digitize` |
| `SlewLimit` | `SlewLimit 100M` | Limit |dv/dt| to the given rate (V/s) |
| `SoftClip` | `SoftClip -0.7, 0.7` | Soft-clip into [low, high] via tanh |
| `Fade` | `Fade 100n` | Linear fade-in and fade-out over the given duration |
| `FadeIn` | `FadeIn 50n` | Linear fade-in only |
| `FadeOut` | `FadeOut 50n` | Linear fade-out only |
| `Quantize` | `Quantize 8, 3.3` · `Quantize 8, -1, 1` | Round to N-bit levels over [0, full-scale] or [low, high] |
| `Abs` | `Abs` | Replace every value with its absolute value |
| `Rectify` | `Rectify` | Half-wave rectify (keep values ≥ 0, zero the rest) |

### Time domain

| Operation | Example | Effect |
|---|---|---|
| `TimeShift` | `TimeShift -5m` | Shift timestamps; negative values shift left |
| `TimeScale` | `TimeScale 2` · `TimeScale 0.5` | Scale the time axis (preserve start time) |
| `Trigger` | `Trigger 0.5` · `Trigger either, 0.5` · `Trigger rising, 0.5` · `Trigger falling, 1.5, 2m` | Shift so the first edge at the threshold is at t=0. Direction is `rising`, `falling`, or `either` (first of either polarity). A single argument is the level with `either`. Optional final time is search-after. |
| `Seamless` | `Seamless` · `Seamless 100n` | Force last value = first (or append a ramp of the given duration) |
| `MatchEnds` | `MatchEnds` | Alias of `Seamless` |
| `Pad` | `Pad 5m` · `Pad 5m, 0` | Extend by a duration, holding the last value (or a given level) |
| `HoldLast` | `HoldLast 5m` | Alias of `Pad` |
| `ExtendTo` | `ExtendTo 10m` · `ExtendTo 10m, 0` | Extend to an absolute end time, holding the last value (or a given level) |
| `Resample` | `Resample 1n` | Linearly interpolate onto a uniform sample interval |
| `ExtractPeriod` | `ExtractPeriod` · `ExtractPeriod 0.5` | Keep one cycle from the first rising crossing (auto or given threshold); shift to t=0 |
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
| `Median` | `Median 5` | Centered median filter over N samples (spike-resistant) |
| `Diff` | `Diff` | Numerical derivative dv/dt |
| `Integrate` | `Integrate` | Cumulative trapezoidal integral (starts at 0) |

¹ `RemoveDC` estimates the DC component from the capture by applying one-dimensional k-means clustering with `k = 3` to all finite sample values. Several deterministic initializations are evaluated and the clustering with the smallest squared error is selected. The DC estimate is the midpoint between the lower and upper centroids.

² Filters are linear-phase windowed-sinc FIRs (Blackman–Harris). You only supply the cutoff frequency(ies); the sample rate comes from the capture, tap count is chosen automatically, and group delay is removed so event timing stays aligned. Frequencies must be greater than 0 and below Nyquist (`fs/2`). Band filters require `0 < f1 < f2`.

³ `dBmW` and `dBW` convert an absolute power level to a voltage scale factor: `V = √(P · R)`, with `P = 1 mW · 10^(dBmW/10)` or `P = 1 W · 10^(dBW/10)`. Optional second argument is load impedance in ohms (default 50). Unlike `dB`, these are not relative gains — they multiply the waveform by that absolute voltage (useful for unit-amplitude templates).

⁴ `Repeat` requires a value greater than zero and accepts fractional repetitions; its final point is interpolated when needed.

⁵ `Digitize` turns an analog capture into a two-level digital PWL. Argument forms:

| Form | Meaning |
|---|---|
| `Digitize T` | Hard threshold: output `1` when the sample is ≥ `T`, else `0` |
| `Digitize T, low, high` | Same compare, but output `low` / `high` instead of `0` / `1` |
| `Digitize fall, rise, low, high` | Schmitt trigger: go high when the sample is ≥ `rise`, go low when ≤ `fall`; stay put while between the two (hysteresis). `fall` and `rise` may be given in either order |

The first sample seeds the state (`≥ rise` → high, otherwise low). With a single threshold the compare is hard (no band between levels). Use hysteresis when the analog edge is noisy so the digital output does not chatter.

⁶ `TVDenoise λ` solves min_x ½‖x − y‖² + λ · TV(x) with TV(x) = Σ |xᵢ₊₁ − xᵢ| (Condat’s direct 1D algorithm). Larger λ flattens plateaus more aggressively while keeping large jumps; λ = 0 is a no-op. λ has the same units as the sample amplitude. Not an inverse of `AddNoise`.

### Analysis

Pass measurement commands with `-a` or `--analysis`. Syntax matches `-t` (semicolon-separated, case-insensitive, engineering scalars). Results print to the console with one fractional digit (engineering notation). Analyses always run **after** transformations (and downsample), on the processed waveform. When `-a` is used, the PWL output file is optional (same as `-l` / `-p`).

```
rigol2spice input.csv -a 'Max; Min; RMS; PkPk; Frequency'
rigol2spice input.csv output.txt -t 'RemoveDC' -a 'DC; Avg; ZeroCrossing'
rigol2spice input.csv -p -a 'FFT 1024; Frequency'
```

| Operation | Example | Result |
|---|---|---|
| `Max` | `Max` | Maximum sample value |
| `Min` | `Min` | Minimum sample value |
| `HiPeak` | `HiPeak` | Alias of `Max` |
| `LowPeak` | `LowPeak` | Alias of `Min` |
| `Avg` | `Avg` | Arithmetic mean of sample values |
| `DC` | `DC` | DC estimate (same k-means method as `RemoveDC`)¹ |
| `Duration` | `Duration` | Capture time span `t_last − t_first` |
| `Points` | `Points` | Number of samples |
| `SampleRate` | `SampleRate` | Estimated sample rate `(N−1) / Duration` |
| `Interval` | `Interval` | Mean sample interval `1 / SampleRate` |
| `Start` | `Start` | First sample timestamp |
| `End` | `End` | Last sample timestamp |
| `Peak` | `Peak` | Peak absolute value `max|v|` (same as `PeakTo`) |
| `Amplitude` | `Amplitude` | Half of peak-to-peak (`PkPk / 2`) |
| `Mid` | `Mid` | Midpoint of min/max: `(max + min) / 2` |
| `ACRms` | `ACRms` | AC RMS: `√max(0, RMS² − Avg²)` |
| `StdDev` | `StdDev` | Population standard deviation (same value as `ACRms`) |
| `Stdev` | `Stdev` | Alias of `StdDev` |
| `Crest` | `Crest` | Crest factor: peak absolute / RMS |
| `Median` | `Median` | Median sample value |
| `Top` | `Top` | Upper histogram mode (scope-style high level) |
| `Base` | `Base` | Lower histogram mode (scope-style low level) |
| `Overshoot` | `Overshoot` | `(max − Top) / (Top − Base)` (fraction) |
| `Undershoot` | `Undershoot` | `(Base − min) / (Top − Base)` (fraction) |
| `RiseTime` | `RiseTime` · `RiseTime 20, 80` | First rising edge time from low% to high% of min/max span (default 10 → 90) |
| `FallTime` | `FallTime` · `FallTime 20, 80` | First falling edge time from high% to low% of min/max span (default 90 → 10 via the same percent pair) |
| `PulseWidth` | `PulseWidth` · `PulseWidth 0.5` | Average high pulse width (rise→fall) at threshold (default `Avg`) |
| `Duty` | `Duty` · `Duty 0.5` | Average duty cycle as a fraction 0…1 (high time / period) at threshold (default `Avg`) |
| `Period` | `Period` | Average period only (same threshold as `Frequency`) |
| `EdgeCount` | `EdgeCount` · `EdgeCount 0` | Number of level crossings at threshold (default `Avg`) |
| `Jitter` | `Jitter` · `Jitter 0` | Std. dev. of complete-wave periods at threshold (default `Avg`; needs ≥ 2 periods) |
| `PeriodStd` | `PeriodStd` | Alias of `Jitter` |
| `Integral` | `Integral` | Trapezoidal ∫v dt over the capture |
| `Crossing` | `Crossing 0` · `Crossing 1.5` | Average period/frequency of **complete** waves at that level (rise+fall crossings; first wave needs 3 crossings, each next wave +2, sharing the boundary; partial start/end ignored) |
| `ZeroCrossing` | `ZeroCrossing` | Alias of `Crossing 0` |
| `Frequency` | `Frequency` | Same as `Crossing` at the sample average (`Avg`) |
| `RMS` | `RMS` | Sample RMS (same definition as `ScaleRMS`) |
| `PkPk` | `PkPk` | Peak-to-peak (`max − min`, same as `PeakToPeak`) |
| `FFT` | `FFT` · `FFT 1024` · `FFT 1k` | Real FFT: remove mean (DC), Hann window, zero-pad to next 2ⁿ. Bare `FFT` uses **all** samples. `FFT N` uses a **centered** window of up to N samples; if the capture is shorter than N, all available samples are used. Peak is the strongest local AC maximum (sub-bin refined). Console prints that frequency and the N actually used; with `-p`, the SVG also shows the magnitude spectrum in dB. |

### Post-processing Options

| Option | Effect |
|---|---|
| `-d, --downsample N` | Keep every Nth sample (e.g. `2` halves the sample rate) |
| `-k, --keep-all` | Disable removal of redundant (collinear) points |
| `-p, --plot [file]` | Write an SVG plot of the processed signal (default: `plot.svg`) |
| `-a, --analysis <list>` | Print measurements to the console (see above) |

The PWL output file is optional when using `--list-channels`, `--plot`, or `--analysis`. The plot uses 1 pixel per sample, auto-scaled Y (min / avg / max markers), and decade-spaced X time markers. When `-a` is combined with `-p`, analysis results are listed in a text block under the time plot (not drawn over the waveform). An `FFT` analysis also appends a spectrum panel (dB vs frequency, peak marker). A console warning is emitted above 10 000 points (prefer downsample or a shorter time window).

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
  -a,  --analysis <value>         Analyses separated by semicolons (console; order independent)
  -d,  --downsample <ratio>       Downsample ratio
  -k,  --keep-all                 Keep all sample points
  -p,  --plot [<file>]            Write SVG plot (default: plot.svg)
  -h,  --help                     Show help
```

`output-file` is optional with `-l`, `-p`, or `-a`.

## Building from Source

Requires Swift 6.2+.

```
swift build
```

Builds on macOS, Windows, and Linux.

## Legal

This is an independent project, not affiliated with Rigol Technologies, Inc.
