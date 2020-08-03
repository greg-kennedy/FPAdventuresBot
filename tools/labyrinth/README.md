# labyrinth-image-dump
Dump image files (and other resources?) from The Labyrinth of Time `DIFF` game data files.

## Overview
This is a very hacky image dumper for The Labyrinth of Time.  It can parse images in `DIFF` format into a full-screen image, write it as a .ppm and exit.  It will also output embedded .wav files it encounters before reaching EOF.

## Usage
`./labyrinth-image-dump.pl INPUT_FILE

## Notes
Labyrinth images are typically built up in multiple steps, each block adding up to 64k of data to the result buffer.  Once the image is completely loaded (usually 5 or 6 blocks), the script dumps the image and exits.  This means no animations are decoded as they follow the full-image decode.

Certain animations have embedded sound blocks.  If these are encountered they can be dumped too.  Check the constants at top of file.

## References
<https://wiki.scummvm.org/index.php/Lab>
