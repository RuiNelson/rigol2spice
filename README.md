# rigol2spice

*A program to convert Rigol oscilloscopes .CSV files to a format readable by LTspice.*

This program reads CSV files from Rigol oscillospes and outputs to a time-value format used by LtSpice and other SPICE programs ([PWL data](https://www.analog.com/en/technical-articles/ltspice-importing-exporting-pwl-data.html)). 

[![YouTube video](https://img.youtube.com/vi/LTEc7fjmXSg/0.jpg)](https://www.youtube.com/watch?v=LTEc7fjmXSg)

[YouTube demo/instructions](https://www.youtube.com/watch?v=LTEc7fjmXSg)

## Intstall

Download the program from [here](https://github.com/RuiCarneiro/rigol2spice/releases), unpack all the files in the RAR file to a folder in your computer (e.g. `C:\rigol2spice` used in this document)

## How to use (simple) 

1. **Acquire**s waveform on your machine, after you have acquired a waveform, use the `Storage` button to save it as a `CSV` and store it to a pen drive.

2. To **Run**, insert the pen-drive on your PC, open Window's command line (Windows+R and enter `cmd` and run) and execute the program like this (if the pen-drive is drive `D:` and the file name is `NewFile1.csv`)

    `C:\rigol2spice\rigol2spice.exe D:\NewFile1.csv`

    The program will run and will output the PWL data points to the standard output (screen). If you want to save to a file, use the ` > ` operator and specify the name of the file, e.g.:

    `C:\rigol2spice\rigol2spice.exe D:\NewFile1.csv > D:\PWLFile.txt`

    To see how long your capture lasts, open the generated file in a text editor and check the last line.

3. **Load** the file in LTSpice. Insert a voltage or current source in your design, right click on the component and click the `Advanced` button, in the dialog that appears. Select `PWL FILE` option and click the `Browse` button to select your PWL file. LTSpice should parse the file and use your waveform in the simulation.

## Multiple Channels

First, note that a Rigol .CSV file can have information of multiple channels, but a LTspice PWL file can have only one channel.

By default, the program reads only the `CH1` channel. To see what channels a .CSV contains, run the program with the `-a` flag:

    C:\rigol2spice\rigol2spice.exe -a D:\NewFile2.csv

The output:

    Channels:
        CH1 (unit: Volt)
        CH2 (unit: Volt)
    Time step: 0.00000000005

Now if you want to use the `CH2`, run the program with the `--channel` option, then a space, then the channel name:

    C:\rigol2spice\rigol2spice.exe --channel CH2 D:\NewFile2.csv > D:\CH2.txt

## Usage reference

    USAGE: rigol2spice [--analyse] [--channel <channel>] <filename>
    
    ARGUMENTS:
      <filename>              The filename of the .csv from your oscilloscope
    
    OPTIONS:
      -a, --analyse           Analyse the file's header and quit
      -c, --channel <channel> The label of the channel to be processed (default: CH1)
      -h, --help              Show help information.


## Building

To build this program, it's just a simple Swift package, you should be able to build it with a simple on macOS, Windows or Linux:

    swift build

## Legal

I'm not affiliated with Rigol and this is not a project related to Rigol Technologies, Inc.
