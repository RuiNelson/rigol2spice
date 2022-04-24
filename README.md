# rigol2spice

*A program to convert Rigol oscilloscopes CSV files to a format readable by LTspice.*

This program reads CSV files from Rigol oscillospes and outputs to a time-value format used by LtSpice and other SPICE programs ([PWL data](https://www.analog.com/en/technical-articles/ltspice-importing-exporting-pwl-data.html)). 

[![YouTube video](https://img.youtube.com/vi/AaCvPtJ-cZM/0.jpg)](https://www.youtube.com/watch?v=AaCvPtJ-cZM)

[YouTube demo/instructions](https://www.youtube.com/watch?v=AaCvPtJ-cZM)

## Install

Download the program from [here](https://github.com/RuiCarneiro/rigol2spice/releases), unpack all the files in the [RAR file](https://www.rarlab.com/) to a folder in your computer (e.g., `C:\rigol2spice` used in this document)

## How to Use (simple) 

1. Use your oscilloscope to save a capture in the CSV format to a pen drive, then mount the pen-drive in your computer (example for the pen-drive mounted as drive `D:`, and file saved as `NewFile1.csv`)
2. Open the Windows command prompt (right-click the Start menu (or press Windows+X) and select "Command Prompt")
3. Run `rigol2spice.exe` with the first argument being the input file an the second argument where you want to save the file to, e.g.:
    
       C:\rigol2spice\rigol2spice.exe D:\NewFile1.csv D:\my_capture.txt
    Will write a PWL file as `my_capture.txt` in `D:\`

## Advanced Options

### Multiple Channels

A Rigol CSV file can store captures from multiple channels (including physical channels and math channels), but a PWL file can only have one channel.

You can analyse and list all the channels in your CSV file with the `--list-channels` flag (e.g. `C:\rigol2spice\rigol2spice.exe --list-channels D:\NewFile1.csv`) can produce:

    Channels:
       - CH1 (unit: Volt)
       - CH2 (unit: Volt)
    Increment: 2us

By default, `rigol2spice` will use `CH1`. If you want to use channel 2, use the `--channel` option and then the channel name (e.g. `C:\rigol2spice\rigol2spice.exe --channel CH2 D:\NewFile1.csv D:\chan2.txt`) will save `CH2` to `D:\chan2.txt`) 

### Vertical Operations

#### Remove the DC Component

You can remove the DC component using the `--remove-dc` flag. `rigol2spice` will calculate the DC component by averaging the waveform capture.

#### Apply Vertical Offset

The `--offset` option alllows you to apply a vertical offsset to a signal. In the argument, use the `U` or `D` prefixes for up and down direction then the desired value, e.g.:

* `--offset U1` will offset the signal 1 up (positive)
* `--offset D0.500` will offset the singal negatively (down) by 500m

You can also use SI prefixes, e.g. `D500m` equals `D0.500`.

#### Multiply Verically (Amplify or Attenuate)

If you want to amplify or attenature the signal (for example, if you forgot to change the probe attenuation compensation on the scope), you can use the `--multiply` option. Use the `N` prefix to indicate a negative value, e.g.:

* `--multiply 10` will amplify the signal by 10X
* `--multiply 0.001` will attenuate the singnal by 1000X
* `--multiply N1` will change the polarity of the signal

#### Combining Vertical Operations

`rigol2spice` will remove the DC component (if speccified)  then will apply the vertical offset (if speccified) and will multiply vertically by last (if speccified).

### Horizontal Operations

#### Time-Shifting

You can shift in time the signal to the left or to the right using the `--shift` option, then `L` or `R` for "left" or "right", and the amount of time you want to shift, e.g:

* `--shift L5ms` will shift 5 milliseconds to the left
* `--shift R100us` will shift 100 microseconds to the right
* `--shift L0.2ms` will shift 200 microseconds to the left
* `--shift R1s` will shift 1 second to the right

Sample points that end before 0 seconds will be removed.

You can use engineering (e.g., `3.3ns`) or scientific notation (e.g., `5E-3s`). The `s` unit is facultative.

#### Cutting

Using the `--cut` option you can remove sample points of the signal after a certain timestamp. For example, `--cut 10us` will remove points of the capture after 10 microseconds, inclusively.

#### Repeating

The `--repeat`  option will allow you to repeat the signal multiple times. E.g., `-- repeat 3` will add 3 repetitions of the original signal.

#### Combining Horizontal Operations

`--shift`, `--cut` and `--repeat` will apply to the capture in this order, from the result of the previous operation.

For example `rigol2spice.exe --shift L5ms --cut 7.5ms --repeat 3` will result in:

1. Nullify the first 5 milliseconds of the capture, and bring the waveform 5ms to the left
2. Remove everything after the new 7.5ms mark. (12.5ms in the original waveform), the total width of the waveform is now 7.5ms.
3. Repeat the same 7.5ms three times, the resulting PWL file is 30ms in lenght

### Downsampling and Post-Processing

#### Downsampling

You can reduce the sample rate of the capture with the `--downsample` option. A `--downsample 2` will skip every odd point of the capture and will turn a 100 Megasample/s capture into a 50 Megsample/s capture for example.

#### Deactivating Optimisations

To optimize the resulting PWL file, `rigol2spice` will skip sample points where the value maintained from the previous point. This produces smaller PWL files for LtSpice that will save CPU time when simulating (due to less parsing), while producing the exact same results.

But you might want to disable this optimisation, for example, if you are passing the results to another tool for analysis/transformation. Use the `--keep-all` flag if you want this.

## Usage reference

    USAGE: rigol2spice [--list-channels] [--channel <channel>] [-dc] [--offset <offset>] [--multiply <multiply>] [--shift <shift>] [--cut <cut>] [--repeat <repeat>] [--downsample <downsample>] [--keep-all] <input-file> [<output-file>]

    ARGUMENTS:
      <input-file>            The filename of the .csv from the oscilloscope to be read
      <output-file>           The PWL filename to write to

    OPTIONS:
      -l,  --list-channels            Only list channels present in the file and quit
      -c,  --channel <channel>        The label of the channel to be processed (default: CH1)
      -dc, --remove-dc                Remove DC component
      -o,  --offset <offset>          Offset value for signal (use D and U prefixes)
      -m,  --multiply <multiply>      Multiplication factor for signal (use M prefix for negative)
      -s,  --shift <shift>            Time-shift seconds (use L and R prefixes)
      -x,  --cut <cut>                Cut signal after timestamp
      -r,  --repeat <repeat>          Repeat signal number of times
      -d,  --downsample <downsample>  Downsample ratio
      -k,  --keep-all                 Don't remove redundant sample points. Sample points where the signal value maintains (useful for output file post-processing)
      -h,  --help                     Show help information.

## Building

To build this program, it's just a simple Swift package, you should be able to build it with a simple on macOS, Windows or Linux:

    swift build

## Legal

I'm not affiliated with Rigol and this is not a project related to Rigol Technologies, Inc.
