# rigol2spice

**Import real oscilloscope captures into your SPICE simulations.**

Converts Rigol oscilloscope CSV and WFM exports to:

- PWL (piece-wise linear) files for LTspice, Cadence, ngspice, and other SPICE simulators.
- MATLAB vectors for numerical analysis and further processing.
- Mono WAV files in 32-bit floating-point or 16-bit PCM format.

Supports multi-channel captures, channel selection, and channel math.

For convenient waveform processing, it provides an ordered transformation pipeline, measurements and FFT analysis, and optional SVG plots.

Written in Swift as a compiled native binary for high performance; runs on Windows, macOS, and Linux.

[![YouTube video](https://img.youtube.com/vi/AaCvPtJ-cZM/0.jpg)](https://www.youtube.com/watch?v=AaCvPtJ-cZM)

[Watch on YouTube](https://www.youtube.com/watch?v=AaCvPtJ-cZM)

## Supported Input Formats

Input format is detected from the file contents, not its filename extension.

| Format | Oscilloscope families |
|---|---|
| Legacy Rigol CSV | Legacy Rigol oscilloscopes |
| Centaurus CSV | Newer Centaurus-platform oscilloscopes, including DHO800/DHO900 |
| Rigol WFM | DS1000B, DS1000C, DS1000D/E, DS1000Z, DS2000/MSO2000, DS4000/MSO4000 |

DHO `.wfm`, logic-only WFM payloads, and Rigol `.trc` files are not supported.

## Quick Start

[Download the latest release](https://github.com/RuiCarneiro/rigol2spice/releases), then:

```
rigol2spice input.csv output.txt
```

The output `.txt` file can be loaded directly as a PWL source in LTspice and other SPICE simulators.

WFM captures use the same command:

```
rigol2spice capture.wfm output.txt
```

## Output Formats

Select the output format with `-f` or `--format`. The default is `pwl`.
The waveform output file is optional when using `--list-channels`, `--plot`, or `--analysis`.

### PWL

PWL output contains one tab-separated time/value pair per line and can be loaded directly by LTspice, ngspice, and other SPICE simulators:

```
0    1
0.5  -2
```

```
rigol2spice --format pwl input.csv output.txt
```

By default, redundant collinear points are removed to reduce the output size. Use `-k` or `--keep-all` to retain every processed point.

### MATLAB

MATLAB output is a column vector named `points` containing only the vertical sample values:

```matlab
points = [
1;
-2;
];
```

```
rigol2spice --format matlab input.csv output.m
```

MATLAB output always retains every processed point, as if `--keep-all` were enabled.

### WAV

`wav32` writes mono 32-bit IEEE floating-point samples. `wav16` writes mono signed 16-bit PCM samples:

```sh
rigol2spice --format wav32 input.csv output.wav
rigol2spice --format wav16 input.csv output.wav
```

WAV output does not normalize or resample automatically. Before conversion:

- Every vertical value must be finite and within `-1...1`. Apply an explicit amplitude transformation such as `PeakTo 1` when required.
- Timestamps must form a uniform grid at a whole-number sampling frequency. Apply `ResampleF`, normally as the final transformation, when required.
- At least two processed samples must remain.

For example, this explicitly scales the peak amplitude and converts the sampling grid to 48 kSa/s:

```sh
rigol2spice --format wav32 -t 'PeakTo 1; ResampleF 48k' input.csv output.wav
```

Timestamp validation allows small floating-point rounding errors but rejects genuinely nonuniform grids. If the signal is not ready for WAV conversion, the command exits without creating the output file and suggests the relevant transformation. WAV output always retains all processed samples; PWL point optimization is not applied.

## Channel Selection

List available channels in a capture with `-l` or `--list-channels`:

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
| `RemoveDC` | `RemoveDC` · `RemoveDC Avg` · `RemoveDC Median` · `RemoveDC Mid` | Estimate and subtract the DC component¹ |
| `Offset` | `Offset -1.5` | Add the scalar to every value |
| `Min0` | `Min0` | Shift so the lowest sample is 0 (subtract min) |
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
| `Seamless` | `Seamless` · `Seamless 100n` | Force last value = first (or append a ramp of the given duration) |
| `MatchEnds` | `MatchEnds` | Alias of `Seamless` |
| `Pad` | `Pad 5m` · `Pad 5m, 0` | Extend by a duration, holding the last value (or a given level) |
| `HoldLast` | `HoldLast 5m` | Alias of `Pad` |
| `ExtendTo` | `ExtendTo 10m` · `ExtendTo 10m, 0` | Extend to an absolute end time, holding the last value (or a given level) |
| `ResampleF` | `ResampleF 2.5k` · `ResampleF 1M, sinc` | Resample to a target sampling frequency using linear, PCHIP, or sinc interpolation |
| `ExtractPeriod` | `ExtractPeriod` · `ExtractPeriod 0.5` | Keep one cycle from the first rising crossing (auto or given threshold); shift to t=0 |
| `CutBefore` | `CutBefore 5m` | Discard samples before the timestamp |
| `CutAfter` | `CutAfter 10u` | Discard samples at or after the timestamp |
| `Trim` | `Trim 1m, 10m` | Keep samples with start ≤ t < end |
| `Repeat` | `Repeat 2.5` | Append copies of the capture⁴ |

### Resampling

**Target sampling frequency**

`ResampleF frequency[, interpolation]` creates a uniform grid at the requested sampling frequency. The default interpolation is `linear`; `pchip` and `sinc` are also available. Frequencies accept engineering notation:

```sh
rigol2spice input.csv output.txt -t 'ResampleF 2.5k'
rigol2spice input.csv output.txt -t 'ResampleF 1M, sinc'
```

The first timestamp is preserved and subsequent samples are exactly `1 / frequency` seconds apart. Sampling stops at the last interval that fits within the original capture, so the final timestamp can be up to one interval earlier than the original endpoint. As with `Downsample`, no anti-alias low-pass filter is applied automatically when reducing the sampling frequency.

**Downsampling**

`Downsample factor[, interpolation]` reduces the number of points by a factor greater than 1. The default interpolation is `linear`:

```sh
rigol2spice input.csv output.txt -t 'Downsample 2'
rigol2spice input.csv output.txt -t 'Downsample 4, sinc'
rigol2spice input.csv output.txt -t 'Downsample 4, fast'
```

With `linear` or `sinc`, the target count is `original count / factor`, rounded to the nearest whole sample, and the first and last timestamps are preserved. In `fast` mode, samples are selected at source positions `0`, `factor`, `2 × factor`, and so on, without generating new points. Fractional factors are supported; for example, 1,000 points downsampled by 1.5 produce 667 points.

| Interpolation | Behaviour |
|---|---|
| `linear` (default) | Interpolate linearly between adjacent samples; fastest and consistent with PWL output |
| `sinc` | Use a finite windowed-sinc kernel for better reconstruction of band-limited signals |
| `fast` | Keep original samples at the requested factor and discard the samples between them; performs no interpolation |

`linear` and `sinc` preserve the first and last timestamps. `fast` retains only original points, so the final timestamp is kept only when it falls on the selection sequence.

No anti-alias low-pass filter is applied automatically, including in `fast` mode. Add one earlier in the transformation chain when required:

```sh
rigol2spice input.csv output.txt -t 'LowPass 20k; Downsample 4, sinc'
```

The post-processing option `--downsample N` is equivalent to applying a final `Downsample N` with linear interpolation.

**Upsampling**

`Upsample factor[, interpolation]` increases the number of points by a factor greater than 1. The default interpolation is `linear`:

```sh
rigol2spice input.csv output.txt -t 'Upsample 4'
rigol2spice input.csv output.txt -t 'Upsample 4, pchip'
rigol2spice input.csv output.txt -t 'Upsample 4, sinc'
```

The target count is `original count × factor`, rounded to the nearest whole sample. As with downsampling, both time endpoints and the capture duration are preserved, and fractional factors are accepted.

| Interpolation | Behaviour |
|---|---|
| `linear` (default) | Interpolate linearly between adjacent samples; fastest and suitable for most PWL workflows |
| `pchip` | Monotonic piecewise-cubic interpolation; produces smoother curves without overshooting monotonic data |
| `sinc` | Finite windowed-sinc interpolation; best suited to sufficiently sampled, band-limited signals |

### Triggers

Trigger transformations find an event using interpolated crossings between samples and align the resulting waveform. Directions are `rising`, `falling`, or `either` where supported. An optional final `after` argument ignores events before that capture time.

| Operation | Example | Effect |
|---|---|---|
| `Trigger` | `Trigger 0.5` · `Trigger rising, auto` · `Trigger falling, 50%, 2m` | Shift the first level crossing to t=0 |
| `TriggerSchmitt` | `TriggerSchmitt rising, 1.4, 1.8` · `TriggerSchmitt falling, 1.4, 1.8, 2m` | Arm at the opposite hysteresis level, then trigger at the requested edge |
| `TriggerNth` | `TriggerNth rising, 0.5, 3` · `TriggerNth either, auto, 5, 2m` | Shift the Nth matching crossing to t=0 |
| `TriggerCapture` | `TriggerCapture rising, 0.5, 100u, 500u` | Keep the requested pre/post window around a level crossing; optional fifth argument is search-after |
| `TriggerWindow` | `TriggerWindow rising, 0.5, 100u, 500u` | Alias of `TriggerCapture` |
| `TriggerPulse` | `TriggerPulse high, 0.5, 10u` · `TriggerPulse low, 0.5, 10u, 20u` | Trigger at the start of a complete high/low pulse meeting a minimum or inclusive min/max width |
| `TriggerBand` | `TriggerBand enter, 1, 2` · `TriggerBand exit, 1, 2, 5m` | Trigger on `enter`, `exit`, rising `above`, or falling `below` a band |
| `TriggerSlew` | `TriggerSlew rising, 10, 90, 500k` · `TriggerSlew falling, 10, 90, 100k, 500k` | Trigger at the start of a percentage-level transition meeting a minimum or inclusive min/max slew rate |
| `TriggerDropout` | `TriggerDropout rising, 0.5, 2m` · `TriggerDropout either, auto, 2m, 5m` | Trigger when no matching edge occurs for the duration after an initial edge |
| `TriggerRunt` | `TriggerRunt rising, 1, 2, 20u` | Rising: cross low but return/fail to reach high; falling: cross high but return/fail to reach low |

Levels may be numeric, `auto`, or a percentage such as `50%` for `Trigger`, `TriggerNth`, `TriggerCapture`, `TriggerPulse`, and `TriggerDropout`. `auto` is the midpoint of the oscilloscope-style `Top` and `Base`; `P%` is that percentage of the same span.

Most triggers discard samples before the aligned event. `TriggerCapture` deliberately preserves context before it:

```sh
rigol2spice input.csv output.txt -t 'TriggerCapture rising, auto, 100u, 500u'
```

This keeps up to 100 µs before and 500 µs after the event. The output starts at t=0, so the trigger normally occurs at t=100 µs. The pre/post window is clipped to the samples available in the original capture.

### Filtering & calculus

| Operation | Example | Effect |
|---|---|---|
| `LowPass` | `LowPass 1k` | Apply a low-pass filter² |
| `HighPass` | `HighPass 100` | Apply a high-pass filter² |
| `BandPass` | `BandPass 900, 1.1k` | Apply a band-pass filter² |
| `BandStop` | `BandStop 48, 52` | Apply a band-stop filter² |
| `Notch` | `Notch 50, 4` | Reject a band centered on a frequency; arguments are center frequency and total bandwidth² |
| `MovingAverage` | `MovingAverage 5` | Centered moving average over N samples |
| `Median` | `Median 5` | Centered median filter over N samples (spike-resistant) |
| `Detrend` | `Detrend` | Remove the least-squares linear trend (slope and offset) |
| `Diff` | `Diff` | Numerical derivative dv/dt |
| `Integrate` | `Integrate` | Cumulative trapezoidal integral (starts at 0) |

For a capture with baseline drift and 50 Hz interference, both operations can be applied in one pass:

```
rigol2spice input.csv output.txt -t 'Detrend; Notch 50, 4'
```

¹ `RemoveDC` subtracts a DC estimate. Optional method (same names as analysis measurements; case-insensitive):

| Method | Meaning |
|---|---|
| `DC` (default; aliases `Cluster`, `KMeans`) | 1D k-means with `k = 3` on finite sample values; several deterministic initializations; pick smallest squared error; DC = midpoint of lower and upper centroids |
| `Avg` (aliases `Average`, `Mean`) | Arithmetic mean of sample values |
| `Median` | Median of sample values |
| `Mid` (alias `Midpoint`) | Midpoint of min/max: `(max + min) / 2` |

Bare `RemoveDC` is equivalent to `RemoveDC DC`.

² Filters are linear-phase windowed-sinc FIRs (Blackman–Harris). You only supply the cutoff frequency(ies); the sample rate comes from the capture, tap count is chosen automatically, and group delay is removed so event timing stays aligned. Frequencies must be greater than 0 and below Nyquist (`fs/2`). Band filters require `0 < f1 < f2`. `Notch center, width` is shorthand for `BandStop center-width/2, center+width/2`; both edges must remain inside the valid frequency range.

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

### Modulation & demodulation

The analog modulation transformations turn the current waveform into a carrier-modulated signal while preserving timestamps and sample count. `AM` automatically centers and peak-normalizes its message to −1…1 because its argument is a dimensionless modulation depth. `FM` and `PM` deliberately use the sample values unchanged, allowing earlier transformations such as `RemoveDC`, `Offset`, `Multiply`, or `PeakTo` to define the desired message scale.

| Operation | Example | Effect |
|---|---|---|
| `AM` | `AM 100k, 0.8` · `AM 100k, 0.8, 2` | Amplitude modulation: carrier frequency, modulation depth, and optional carrier amplitude (default 1) |
| `FM` | `FM 100k, 10k` · `FM 100k, 10k, 2` | Frequency modulation: carrier frequency, sensitivity in Hz per input unit (normally Hz/V), and optional carrier amplitude (default 1) |
| `PM` | `PM 100k, 1.2` · `PM 100k, 1.2, 2` | Phase modulation: carrier frequency, sensitivity in radians per input unit (normally rad/V), and optional carrier amplitude (default 1) |
| `DemodAM` | `DemodAM 100k, 0.8, 20k` | Recover AM baseband: carrier frequency, modulation depth, and baseband low-pass cutoff |
| `DemodFM` | `DemodFM 100k, 10k, 20k` | Recover FM input units: carrier frequency, sensitivity in Hz/unit, and quadrature low-pass cutoff |
| `DemodPM` | `DemodPM 100k, 1.2, 20k` | Recover PM input units: carrier frequency, sensitivity in rad/unit, and quadrature low-pass cutoff |

For FM, the instantaneous frequency is `carrier + sensitivity × value`; a sensitivity of `10k` applied to a ±2 V message therefore produces a ±20 kHz frequency deviation. For PM, the phase offset is `sensitivity × value`. The FM instantaneous frequency must remain above 0 and below Nyquist. PM changes can also alias if the signal produces phase changes that are too fast for the sample rate.

`ModulateAM`, `ModulateFM`, and `ModulatePM` are aliases of the short modulation names. `AMDemod`, `FMDemod`, and `PMDemod` are aliases of the corresponding demodulators. Demodulation uses coherent quadrature mixing followed by the existing FIR low-pass filter, so its carrier and sensitivity parameters should match the modulator. Its cutoff must cover the occupied modulated baseband while remaining below both the carrier and its distance from Nyquist. A carrier-frequency error appears as a DC error in FM; an unknown carrier phase appears as a DC ambiguity in PM. For AM, depths up to 1 avoid overmodulation; values above 1 are accepted deliberately.

For example, modulate a captured message in FM and then recover its baseband:

```sh
rigol2spice input.csv fm.txt -t 'RemoveDC; PeakTo 1; FM 100k, 10k, 2'
rigol2spice fm-capture.csv recovered.txt -t 'DemodFM 100k, 10k, 20k'
```

## Analysis

Pass measurement commands with `-a` or `--analysis`. Syntax matches `-t` (semicolon-separated, case-insensitive, engineering scalars). Results print to the console with one fractional digit and combine the engineering prefix with the physical unit, for example `2.4ms`, `8.4mV`, `1.2MV/s`, or `2mW`. Signal amplitudes are reported in volts; ratios such as duty cycle and THD are displayed as percentages, while crest factor uses `×`. Analyses always run **after** transformations (and downsample), on the processed waveform. When `-a` is used, the PWL output file is optional (same as `-l` / `-p`).

```
rigol2spice input.csv -a 'Max; Min; RMS; PkPk; Frequency'
rigol2spice input.csv output.txt -t 'RemoveDC' -a 'DC; Avg; ZeroCrossing'
rigol2spice input.csv -p -a 'FFT 1024; Frequency'
rigol2spice input.csv -a 'Basic; Timing'
```

Frequently used measurements are also available as presets. A preset expands to the listed analyses and can be mixed with individual operations or other presets:

| Preset | Expansion |
|---|---|
| `Basic` | `Duration; Points; Min; Max; PkPk; Avg; RMS` |
| `Timing` | `Frequency; Duty; PulseWidth; RiseTime; FallTime` |
| `Spectrum` | `FFT; THD` |
| `WaveType` | `SineWaveType; SquareWaveType; SawtoothWaveType; TriangleWaveType` (requires a preceding `FFT`) |

For example, `-a 'Basic; SlewRise'` prints the basic summary followed by the rising-edge slew rate. Preset names, like all analysis operations, are case-insensitive.

### Capture

| Operation | Example | Result |
|---|---|---|
| `Duration` | `Duration` | Capture time span `t_last − t_first` |
| `Points` | `Points` | Number of samples |
| `SampleRate` | `SampleRate` | Estimated sample rate `(N−1) / Duration` |
| `Interval` | `Interval` | Mean sample interval `1 / SampleRate` |
| `Start` | `Start` | First sample timestamp |
| `End` | `End` | Last sample timestamp |

### Amplitude & level

| Operation | Example | Result |
|---|---|---|
| `Max` | `Max` | Maximum sample value |
| `Min` | `Min` | Minimum sample value |
| `HiPeak` | `HiPeak` | Alias of `Max` |
| `LowPeak` | `LowPeak` | Alias of `Min` |
| `PkPk` | `PkPk` | Peak-to-peak (`max − min`, same as `PeakToPeak`) |
| `Peak` | `Peak` | Peak absolute value `max\|v\|` (same as `PeakTo`) |
| `Amplitude` | `Amplitude` | Half of peak-to-peak (`PkPk / 2`) |
| `Mid` | `Mid` | Midpoint of min/max: `(max + min) / 2` |
| `Avg` | `Avg` | Arithmetic mean of sample values |
| `DC` | `DC` | DC estimate (same default k-means method as bare `RemoveDC`)¹ |
| `RMS` | `RMS` | Sample RMS (same definition as `ScaleRMS`) |
| `ACRms` | `ACRms` | AC RMS: `√max(0, RMS² − Avg²)` |
| `StdDev` | `StdDev` | Population standard deviation (same value as `ACRms`) |
| `Stdev` | `Stdev` | Alias of `StdDev` |
| `Crest` | `Crest` | Crest factor: peak absolute / RMS |
| `Median` | `Median` | Median sample value |
| `PeakTime` | `PeakTime` | Timestamp of the first maximum sample |
| `MinTime` | `MinTime` | Timestamp of the first minimum sample |
| `MeanAbs` | `MeanAbs` | Arithmetic mean of the absolute sample values |
| `Top` | `Top` | Upper histogram mode (scope-style high level) |
| `Base` | `Base` | Lower histogram mode (scope-style low level) |
| `Overshoot` | `Overshoot` | `(max − Top) / (Top − Base)` (fraction) |
| `Undershoot` | `Undershoot` | `(Base − min) / (Top − Base)` (fraction) |

### Timing

| Operation | Example | Result |
|---|---|---|
| `Crossing` | `Crossing 0` · `Crossing 1.5` | Average period/frequency of **complete** waves at that level (rise+fall crossings; first wave needs 3 crossings, each next wave +2, sharing the boundary; partial start/end ignored) |
| `ZeroCrossing` | `ZeroCrossing` | Alias of `Crossing 0` |
| `Frequency` | `Frequency` | Same as `Crossing` at the sample average (`Avg`) |
| `RiseTime` | `RiseTime` · `RiseTime 20, 80` | First rising edge time from low% to high% of min/max span (default 10 → 90) |
| `FallTime` | `FallTime` · `FallTime 20, 80` | First falling edge time from high% to low% of min/max span (default 90 → 10 via the same percent pair) |
| `SlewRise` | `SlewRise` · `SlewRise 20, 80` | First rising-edge slew rate Δv/Δt over the same percentage levels as `RiseTime` (default 10 → 90) |
| `SlewFall` | `SlewFall` · `SlewFall 20, 80` | First falling-edge slew rate Δv/Δt over the same percentage levels as `FallTime` (default 90 → 10; reported as a positive magnitude) |
| `PulseWidth` | `PulseWidth` · `PulseWidth 0.5` | Average high pulse width (rise→fall) at threshold (default `Avg`) |
| `LowPulseWidth` | `LowPulseWidth` · `LowPulseWidth 0.5` | Average low pulse width (fall→rise) at threshold (default `Avg`) |
| `Duty` | `Duty` · `Duty 0.5` | Average duty cycle as a fraction 0…1 (high time / period) at threshold (default `Avg`) |
| `EdgeCount` | `EdgeCount` · `EdgeCount 0` | Number of level crossings at threshold (default `Avg`) |
| `RiseCount` | `RiseCount` · `RiseCount 0` | Number of rising crossings at threshold (default `Avg`) |
| `FallCount` | `FallCount` · `FallCount 0` | Number of falling crossings at threshold (default `Avg`) |
| `Jitter` | `Jitter` · `Jitter 0` | Std. dev. of complete-wave periods at threshold (default `Avg`; needs ≥ 2 periods) |
| `PeriodStd` | `PeriodStd` | Alias of `Jitter` |
| `PeriodMin` | `PeriodMin` · `PeriodMin 0` | Minimum complete-wave period at threshold (default `Avg`) |
| `PeriodMax` | `PeriodMax` · `PeriodMax 0` | Maximum complete-wave period at threshold (default `Avg`) |
| `PeriodPkPk` | `PeriodPkPk` · `PeriodPkPk 0` | Range of complete-wave periods (`max − min`) at threshold (default `Avg`) |

### Integrals & power

| Operation | Example | Result |
|---|---|---|
| `Integral` | `Integral` | Trapezoidal ∫v dt over the capture |
| `Power` | `Power` · `Power 75` | Mean RMS power `Vrms²/R` in watts (default 50 Ω) |
| `Energy` | `Energy` · `Energy 50` | Trapezoidal ∫v²/R dt in joules (default 1 Ω, preserving the original bare `Energy`) |
| `dBm` | `dBm` · `dBm 75` | RMS power in dBm into R Ω (default 50): `10·log₁₀(Vrms²/R / 1mW)` |

### Spectrum

| Operation | Example | Result |
|---|---|---|
| `FFT` | `FFT` · `FFT 1024` · `FFT 1024, middle` · `FFT 1024, end` | Calculate and retain a real FFT for subsequent spectral analyses |
| `THD` | `THD` | Total harmonic distortion from the retained FFT: `√(Σ Aₕ²) / A₁` for harmonics 2…10; displayed as a percentage |
| `Fundamental` | `Fundamental` | Frequency and Hann-corrected peak amplitude of the retained FFT's strongest AC component |
| `Harmonic` | `Harmonic 3` | Hann-corrected peak amplitude of harmonic N of the retained FFT fundamental |
| `SineWaveType` | `SineWaveType` | Similarity to a sinusoid: fundamental with no ideal higher harmonics |
| `SquareWaveType` | `SquareWaveType` | Similarity to a 50% square wave: odd harmonics proportional to `1/n` |
| `SawtoothWaveType` | `SawtoothWaveType` | Similarity to a sawtooth: every harmonic proportional to `1/n`; `SawWaveType` is an alias |
| `TriangleWaveType` | `TriangleWaveType` | Similarity to a triangle wave: odd harmonics proportional to `1/n²` |
| `WaveType` | `WaveType` | Preset that runs all four wave-type similarity analyses |

FFT-dependent analyses are sequential. `THD`, `Fundamental`, `Harmonic`, and all wave-type analyses must appear after an `FFT` in the same analysis list; otherwise parsing fails. They reuse that exact spectrum instead of calculating another FFT and therefore do not accept a point-count argument:

```sh
rigol2spice input.csv -a 'FFT 1024, middle; THD; Fundamental; Harmonic 3'
rigol2spice input.csv -a 'FFT 4096, start; WaveType'
```

If another `FFT` appears later, subsequent dependent analyses use the new result. Other analyses between them do not discard the retained spectrum.

FFT syntax is `FFT [points][, position]`. The position may be `start`, `middle`, or `end`; `start` is the default. The position can also be supplied without a point count (`FFT middle`), although it only changes the selected samples when the requested window is shorter than the capture. If the capture has fewer than the requested number of points, all available samples are used.

Before the FFT, the selected values have their mean removed and receive a Hann window. They are then zero-padded to the next power of two. The reported peak is the strongest local AC maximum with sub-bin refinement. Console output includes the actual point count and window position; `-p` adds the retained magnitude spectrum in dB to the SVG plot. Its axes use rounded 1–2–5 frequency divisions, labelled dB grid lines, and a maximum 120 dB visual range; the title also shows the FFT bin resolution `Δf`.

Wave-type analysis compares measured harmonic-amplitude ratios, up to harmonic 10 or Nyquist, with the four ideal profiles above. `SineWaveType` is `max(0, 100% − THD%)` over those harmonics. Each other score is 100% minus the harmonic-profile vector error relative to the energy of its ideal higher harmonics, limited to 0–100%. The four scores are independent and are not normalized to sum to 100%. This allows an unknown waveform to score poorly in every analysis and an ambiguous waveform to match more than one profile. At least the third harmonic must fit below Nyquist. Noise, PWM duty cycles other than 50%, clipping, asymmetry, frequency drift, too few periods, analogue bandwidth, and spectral leakage can reduce the match. The classifier deliberately uses magnitudes rather than phase, making it insensitive to time reversal and waveform polarity.

## Post-processing Options

| Option | Effect |
|---|---|
| `-d, --downsample N` | Reduce point count by factor N using linear interpolation, equivalent to a final `Downsample N` |
| `-k, --keep-all` | Disable removal of redundant (collinear) points |
| `-p, --plot [file]` | Write an SVG plot of the processed signal (default: `plot.svg`) |
| `-a, --analysis <list>` | Print measurements to the console (see above) |

The plot uses 1 pixel per sample, auto-scaled Y (min / avg / max markers), and decade-spaced X time markers. When `-a` is combined with `-p`, analysis results are listed in a text block under the time plot (not drawn over the waveform). An `FFT` analysis also appends a spectrum panel (dB vs frequency, peak marker). A console warning is emitted above 10 000 points (prefer downsample or a shorter time window).

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
  -l,  --list-channels            List channels and exit
  -c,  --channel <channel>        Channel or math expression (default: CH1)
  -t,  --transformations <value>  Ordered transformations separated by semicolons
  -a,  --analysis <value>         Ordered analyses separated by semicolons; FFT dependants follow FFT
  -d,  --downsample <ratio>       Downsample ratio
  -f,  --format <format>          Output format: pwl, matlab, wav32, or wav16 (default: pwl)
  -k,  --keep-all                 Keep all sample points
  -p,  --plot [<file>]            Write SVG plot (default: plot.svg)
  -h,  --help                     Show help
```

`output-file` is optional with `-l`, `-p`, or `-a`.

## Building from Source

Requires Swift 6.2+.

```
git submodule update --init --recursive
swift build
```

Builds on macOS, Windows, and Linux.

## Acknowledgements

Special thanks to [Scott Prahl](https://github.com/scottprahl), author of [RigolWFM](https://github.com/scottprahl/RigolWFM), for publishing the reverse-engineering research and Kaitai Struct schema that made DS1000Z WFM support possible.

## Legal

This is an independent project, not affiliated with Rigol Technologies, Inc.
