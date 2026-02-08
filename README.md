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

## Signal Processing

All transforms are applied in the order shown below, letting you chain them predictably.

### Vertical

| Option | Example | Effect |
|---|---|---|
| `--clamp-min` / `--clamp-max` | `--clamp-min 0 --clamp-max 3.3` | Clamp signal to 0 V -- 3.3 V |
| `--removedc` | `--removedc` | Subtract the DC average |
| `--offset` | `--offset P1.5` | Shift signal +1.5 V (use `M` for minus, `P` for plus) |
| `--multiply` | `--multiply 10` | Amplify 10x (use `N` prefix for inversion) |

### Horizontal

| Option | Example | Effect |
|---|---|---|
| `--shift` | `--shift L5ms` | Shift 5 ms left (`L`eft / `R`ight) |
| `--cut` | `--cut 10us` | Discard everything after 10 us |
| `--repeat` | `--repeat 3` | Repeat the waveform 3 times |

### Post-processing

| Option | Effect |
|---|---|
| `--downsample N` | Keep every Nth sample (e.g. `2` halves the sample rate) |
| `--keep-all` | Disable removal of redundant (collinear) points |

Values accept engineering notation: `5ms`, `100us`, `3.3ns`, `5E-3s`.

## Example: Extract One Period and Repeat

```
rigol2spice --shift L5ms --cut 7.5ms --repeat 2 input.csv output.txt
```

1. Shift waveform 5 ms left (removes first 5 ms, time starts at 0)
2. Cut at 7.5 ms (keeps only 0 -- 7.5 ms of the shifted waveform)
3. Repeat 2 times (creates 3 total copies -- original + 2 repetitions = 22.5 ms total)

## Full Usage Reference

```
USAGE: rigol2spice [<options>] <input-file> [<output-file>]

OPTIONS:
  -n,  --new-models               Newer Rigol Centaurus platform format
  -l,  --list-channels            List channels and exit
  -c,  --channel <channel>        Channel to process (default: CH1)
       --clamp-min <value>        Clamp lower bound (N prefix = negative)
       --clamp-max <value>        Clamp upper bound (N prefix = negative)
       --removedc                 Remove DC component
  -o,  --offset <value>           Vertical offset (M/P prefix)
  -m,  --multiply <value>         Multiply signal (N prefix = negative)
  -s,  --shift <value>            Time-shift (L/R prefix)
  -x,  --cut <timestamp>          Cut after timestamp
  -r,  --repeat <count>           Repeat signal
  -d,  --downsample <ratio>       Downsample ratio
  -k,  --keep-all                 Keep all sample points
  -h,  --help                     Show help
```

## Building from Source

Requires Swift 5.6+.

```
swift build
```

Builds on macOS, Windows, and Linux.

## Legal

This is an independent project, not affiliated with Rigol Technologies, Inc.
