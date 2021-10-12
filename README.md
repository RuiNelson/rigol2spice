# rigol2spice

*A program to convert Rigol oscilloscope's .CSV files to a format readable by LTSpice.*

Your Rigol oscilloscope can output .CSV files that capture a waveform, this program reads the .CSV file and converts it to [a PWL (piecewise linear)](https://www.analog.com/en/technical-articles/ltspice-importing-exporting-pwl-data.html) format.

## How to use (simple) 

1. **Acquire**s waveform on your machine, after you have acquired a waveform, use the `Storage` key to save it to `CSV` file format and store it on a pen drive. Note that you can have more than one channel in a CSV file, but a PWL file can only have one signal. Also, large captures will take a long time to be processed both this program and LTSpice.

2. **Download** or compile the program from the [releases](https://github.com/RuiCarneiro/rigol2spice/releases) (binaries provided only for Windows x64 at the moment) and [decompress](https://www.7-zip.org) the files to a folder in your computer (e.g. `C:\rigol2spice`), make sure you remember the folder you decompressed the files to.

3. To **Run**, insert the pen-drive on your PC, open [Windows's command prompt](https://www.lifewire.com/how-to-open-command-prompt-2618089) and execute the program with the argument being the path to the .CSV file, e.g. if your pen-drive is the `D:` drive and the file-name is `NewFile1.csv`:

    C:\rigol2spice\rigol2spice.exe D:\NewFile1.csv

The program will run and will output the PWL data points to the standard output (screen). If you want to save to a file, use the ` > ` operator and specify the name of the file, e.g.:

    C:\rigol2spice\rigol2spice.exe D:\NewFile1.csv > D:\PWLFile.txt

To see how long your capture lasts, open the generated file in a text editor and check the last line.

4. **Load** the file in LTSpice. Insert a voltage or current source in your design, right click on the component and click the `Advanced` button, in the dialog that appears. Select `PWL FILE` option and click the `Browse` button to select your PWL file. LTSpice should parse the file and use your waveform in the simulation.

## How to use (multiple channels)

First, note that a Rigol .CSV file can have information of multiple channels, but a LTSpice PWL file can have only one channel.

By default, the program reads only the `CH1` channel, if the `CH1` channel is not found, it reads the first channel that it finds. To see what channels a .CSV contains, run the program with the `-a` flag:

    C:\rigol2spice\rigol2spice.exe -a D:\NewFile2.csv

The output:

    Channels:
        CH1 (unit: Volt)
        CH2 (unit: Volt)
    Time step: 0.00000000005

Now if you want to use the `CH2`, run the program with the `--channel` option, then a space, then the channel name, note that channel names are CaSe-SeNsItIvE for this program:

    C:\rigol2spice\rigol2spice.exe --channel CH2 D:\NewFile2.csv > D:\CH2.txt

## Usage reference

    USAGE: rigol2spice <filename> [--channel <channel>] [--analyse]

    ARGUMENTS:
    <filename>              The filename of the .csv file from your oscilloscope

    OPTIONS:
    -c, --channel <channel> The label of the channel to be processed (case
                            sensitive) (default: CH1)
    -a, --analyse           Analyse the file's header and quit
    -h, --help              Show help information.


## Building

To build this program, it's just a simple Swift package, you should be able to build it with a simple on macOS, Windows or Linux:

    swift build

## Legal

I'm not affiliated with Rigol and this is not a project related to Rigol Technologies, Inc.
