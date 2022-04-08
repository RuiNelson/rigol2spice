# rigol2spice

*A program to convert Rigol oscilloscopes CSV files to a format readable by LTspice.*

This program reads CSV files from Rigol oscillospes and outputs to a time-value format used by LtSpice and other SPICE programs ([PWL data](https://www.analog.com/en/technical-articles/ltspice-importing-exporting-pwl-data.html)). 

[![YouTube video](https://img.youtube.com/vi/LTEc7fjmXSg/0.jpg)](https://www.youtube.com/watch?v=LTEc7fjmXSg)

[YouTube demo/instructions](https://www.youtube.com/watch?v=LTEc7fjmXSg)

## Install

Download the program from [here](https://github.com/RuiCarneiro/rigol2spice/releases), unpack all the files in the [RAR file](https://www.rarlab.com/) to a folder in your computer (e.g., `C:\rigol2spice` used in this document)

## How to Use (simple) 

1. Use your oscilloscpe to save a capture in the CSV format to a pen drive, then mount the pen-drive in your computer (example for the pen-drive mounted as drive `D:`, and file saved as `NewFile1.csv`)
2. Open the Windows command prompt (right-click the Start menu and select *"Command Prompt"*)
3. Run `rigol2spice.exe` with the first argument being the input file an the second argument where you want to save the file to, e.g.:
    
       C:\rigol2spice\rigol2spice.exe D:\NewFile1.csv D:\my_capture.txt
    Will write a PWL file as `my_capture.txt` in `D:\`

## Advanced Options

### Multiple Channels

A Rigol CSV file can store captures from multiple channels (including physical channels and math channels), but a PWL file can only have one channel.

You can analyse and list all the channels in your CSV file with the `-l` flag (e.g. `C:\rigol2spice\rigol2spice.exe -l D:\NewFile1.csv`) can produce:

    Channels:
      CH1 (unit: Volt)
      CH2 (unit: Volt)
    Increment: 2.0E-9 s

By default, `rigol2spice` will use `CH1`. If you want to use channel 2, use the `--channel` option and then the channel name (e.g. `C:\rigol2spice\rigol2spice.exe --channel CH2 D:\NewFile1.csv D:\chan2.txt`) will save `CH2` to `D:\chan2.txt`) 

### Time Operations

#### Time-Shifting

You can shift in time the signal to the left or to the right using the `--shift` option, then `l` or `r` for "left" or "right", and the amount of time you want to shift, e.g:

* `--shift l5ms` will shift 5 milliseconds to the left
* `--shift r100ns` will shift 100 nanoseconds to the right
* `--shift l0.2ms` will shift 200 microseconds to the left
* `--shift r1s` will shift 1 second to the right

Points before 0.0 seconds will be removed.

#### Cutting

Using the `--cut` option you can remove points of the signal after a certain timestamp. For example, `--cut 10u` will remove points of the signal after 10 microseconds, inclusively.

#### Repeating

The `--repeat`  option will allow you to repeat the signal multiple times. E.g. `-- repeat 3` will add 3 repetitions of the original signal.

#### Combining Time Operations

`--shift`, `--cut` and `--repeat` will apply to the capture in this order.

### Downsampling and Post-Processing

#### Downsampling

You can reduce the sample rate of the capture with the `--downsample` option. A `--downsample 2` will skip every odd point of the capture and will turn a 100 Megasample/s capture into a 50 Megsample/s capture for example.

#### Deactivating Optimizations

To optimize the resulting PWL file, `rigol2spice` will skip points where the value is the same as the previous point. This will produce smaller PWL files for LtSpice that will save CPU time when simulating, while producing the exact same results.

But you might want to disable this optimization, for example, if you are passing the results to another tool for analysis/transformation. Use the `--keep-all` flag if you want this.


## Usage reference

    USAGE: rigol2spice [--list-channels] [--channel <channel>] [--shift <shift>] [--cut <cut>] [--repeat <repeat>] [--downsample <downsample>] [--keep-all] <input-file> [<output-file>]

    ARGUMENTS:
    <input-file>            The filename of the .csv from the oscilloscope to be read
    <output-file>           The PWL filename to write to

    OPTIONS:
    -l, --list-channels             Only list channels present in the file and quit
    -c, --channel <channel>         The label of the channel to be processed (default: CH1)
    -t, --shift <shift>             Time-shift seconds
    -x, --cut <cut>                 Cut signal after timestamp
    -r, --repeat <repeat>           Repeat signal number of times
    -d, --downsample <downsample>   Downsample ratio
    -k, --keep-all                  Don't remove redundant points. Points where the signal value maintains (useful for output file post-processing)
    -h, --help                      Show help information.


## Building

To build this program, it's just a simple Swift package, you should be able to build it with a simple on macOS, Windows or Linux:

    swift build

## Legal

I'm not affiliated with Rigol and this is not a project related to Rigol Technologies, Inc.
