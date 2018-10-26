# t7g-image-dump
Dump image files (and other resources?) from The 7th Guest .gjd game data files.

## Overview
This is a quick-and-dirty image dumper for The 7th Guest.  Given a .RL and .GJD file, this tool will
* parse out every .vdx file stored within,
* unpack the first (still) image from the .vdx,
* and store it into a subdirectory as `BASENAME/<file>.ppm`.

## Usage
`./t7g-image-dump.pl BASENAME`

## Notes
Only the first still image is exported.  For the other blocks, the `lzss()` method should be used to unpack them as well.

This could be easily extended to cover the sound files (type 0x80), which are just 22khz 8bit mono RAW files.

Video files are a series of delta frames played over the initial still.  See the link below for more details.

## References
http://wiki.xentax.com/index.php/The_7th_Guest_VDX
