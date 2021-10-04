# drownedgod-asset-dump
Dump image files (and other resources) from Drowned God: Conspiracy of the Ages ASSETS?.DAT files.

## Overview
This tool reads the RIFF-formatted ASSETS.DAT files from Drowned God, and places the outputs into the same folder.

## Usage
`./drownedgod-asset-dump.pl ASSETS1.DAT`

## Notes
The RIFF format for Drowned God assets is somewhat complex, supporting nested data structures and lists of values
in addition to the raw contents itself.

Only file blocks are stored to output: there are a number of integer / string / floating point bits in here as well,
probably for game logic and state, that are not output by the tool.
