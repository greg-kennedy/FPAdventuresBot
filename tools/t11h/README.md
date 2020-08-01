# t11h-image-dump
Dump image files (and other resources?) from The 11th Hour .gjd/.rl/ game data files.

## Overview
This is a quick-and-dirty image dumper for The 11th Hour.  Given DIR.RL, GJD.GJD, and a media/ folder, this will
* parse out every .roq/.rol/.rnr file stored within,
* retrieve every still-image JPEG from the file,
* and store it into a subdirectory as `out/GJD_NAME/<file>.jpg`.

## Usage
`./t11h-image-dump.pl DIR.RL GJD.GJD MEDIAPATH`

## Notes
Some files contain multiple JPG images - they will be numbered .0, .1, .2 etc. as needed.

Video files are a series of delta frames played over the initial still.  See the link below for more details.

## References
<http://wiki.xentax.com/index.php/The_11th_Hour_GJD>

<http://wiki.xentax.com/index.php/The_11th_Hour_ROL>
