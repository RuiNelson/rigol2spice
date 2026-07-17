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

List available channels in a CSV:

```
rigol2spice --list-channels input.csv
```

Select a specific channel (default is `CH1`):

```
rigol2spice --channel CH2 input.csv output.txt
```

## Transformations

Pass an ordered list of transformation commands with `-t` or `--transformations`. Separate commands with semicolons and quote the complete string for the shell:

```
rigol2spice input.csv output.txt -t 'RemoveDC; ClampMax 0.7; Offset -1.2'
```

Commands use the syntax `OPERATION argument`. Operation names are case-insensitive.

| Operation | Example | Effect |
|---|---|---|
| `RemoveDC` | `RemoveDC` | Estimate and subtract the DC component¹ |
| `ClampMin` | `ClampMin 0` | Clamp values below the scalar |
| `ClampMax` | `ClampMax 3.3` | Clamp values above the scalar |
| `Offset` | `Offset -1.5` | Add the scalar to every value |
| `Multiply` | `Multiply 10` | Multiply every value by the scalar |
| `TimeShift` | `TimeShift -5m` | Shift timestamps; negative values shift left |
| `CutAfter` | `CutAfter 10u` | Discard samples at or after the timestamp |
| `Repeat` | `Repeat 2.5` | Append two copies and the first 50% of another |

Scalars accept decimal (`0.7`), engineering (`3n`, `10u`), and scientific (`5e-3`) notation. Use `-` for negative values. `Repeat` requires a value greater than zero and accepts fractional repetitions; its final point is interpolated when needed. Transformations run strictly from left to right.

¹ `RemoveDC` estimates the DC component from the capture by applying one-dimensional k-means clustering with `k = 3` to all finite sample values. Several deterministic initializations are evaluated and the clustering with the smallest squared error is selected. The DC estimate is the midpoint between the lower and upper centroids.

### Post-processing Options

| Option | Effect |
|---|---|
| `--downsample N` | Keep every Nth sample (e.g. `2` halves the sample rate) |
| `--keep-all` | Disable removal of redundant (collinear) points |

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
  -c,  --channel <channel>        Channel to process (default: CH1)
  -t,  --transformations <value>  Ordered transformations separated by semicolons
  -d,  --downsample <ratio>       Downsample ratio
  -k,  --keep-all                 Keep all sample points
  -h,  --help                     Show help
```

## Building from Source

Requires Swift 6.3+.

```
swift build
```

Builds on macOS, Windows, and Linux.

## Legal

This is an independent project, not affiliated with Rigol Technologies, Inc.
