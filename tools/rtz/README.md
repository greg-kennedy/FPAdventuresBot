# rtz-image-dump
Dump image files from Return to Zork .PRJ game data files.

## Overview
This is a quick-and-dirty image dumper for Return to Zork.  Given a .PRJ, it will trawl through all still-image data and dump it to disk.  Output files are stored into a subdirectory as `out/<file>.ppm`.

## Usage
`./rtz-image-dump.pl RTZCD.PRJ`

## Notes
Image decoding currently works for both MS-DOS and Mac versions of the game.  Mac version supports 640x480 images, which also requires an RLE decompressor.  EGA (16-color) aka "nibble-mode" images are not supported.

## References
https://wiki.scummvm.org/index.php/MADE
