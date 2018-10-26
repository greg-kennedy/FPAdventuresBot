#!/usr/bin/env perl
use strict;
use warnings;

use v5.014;

use Fcntl qw( :seek );

####
# helper: safe read
#  params: fp, length
sub _rd
{
  my $bytes_read = read $_[0], my $buffer, $_[1];
  die "Short read on file: expected $_[1] but got $bytes_read: $!" unless $bytes_read == $_[1];
  return $buffer;
}

# read an iff block - just the header info
#  params: fp, (optional) expected IFF header type
sub _iff_meta
{
  my $type = _rd($_[0], 4);
  my $size = unpack 'V', _rd($_[0], 4);
  if (defined $_[1]) {
    die "IFF Header mismatch: expected $_[1], got $type" if $type ne $_[1];
    return $size;
  } else {
    return ($type, $size);
  }
}

####
####
####
die "Usage: $0 <filename>" unless scalar @ARGV == 1;

my $file_size = -s $ARGV[0];
open (my $fp, '<', $ARGV[0]) or die "Couldn't open file $ARGV[0]: $!";
binmode($fp);

# read PRJ header and INDX area
my %idx_offset;
{
  my $proj_size = _iff_meta($fp, 'PROJ');
  warn "File size $file_size != expect. $proj_size + 8" unless ($file_size == $proj_size + 8);
  # skip unknown 2x uint16
  seek $fp, 4, SEEK_CUR;
  # DDIT entry
  my $ddit_size = _iff_meta($fp, 'DDIT');
  # skip unknown uint32
  seek $fp, 4, SEEK_CUR;
  # read the count of number of indexes
  my $idx_count = unpack 'v', _rd($fp, 2);

  say "== DDIT INDEX: $idx_count ENTRIES ==";

  # Read each DDIT index entry
  for (my $i = 0; $i < $idx_count; $i ++)
  {
    my $type = _rd($fp, 4);
    my $offset = unpack 'V', _rd($fp, 4);
  
    $idx_offset{$type} = $offset;
  
    printf(" %02d. '%s', offset 0x%08x\n", $i, $type, $offset);
  
  # skip more unknown bytes
    seek $fp, 16, SEEK_CUR;
  }
}

# Picture resources are stored in the FLEX area of the file.
my @resources;
{
  #say "... Advancing to FLEX offset.";
  # advance to the FLEX $offsets
  seek $fp, $idx_offset{FLEX}, SEEK_SET;

  # read index at this point
  my $indx_size = _iff_meta($fp, 'INDX');
  seek $fp, 4, SEEK_CUR; # unknown
  my $res_type = _rd($fp, 4);
  die "Expected FLEX but got $res_type instead" unless $res_type eq 'FLEX';

  # weird 2-count system
  my $count1 = unpack 'v', _rd($fp, 2);
  my $count2 = unpack 'v', _rd($fp, 2);
  my $count = ($count1 > $count2 ? $count1 : $count2);
  #say "SIZE: $size, C1: $count1, C2: $count2, max(C1,C2): $count";
  say "== INDX: type FLEX: $count ENTRIES ==";

  seek $fp, 2, SEEK_CUR; # unknown count

  # get offset+size of actual resource info
  for (my $i = 0; $i < $count; $i ++) {
    my $offset = unpack 'V', _rd($fp, 4);
    my $size = unpack 'V', _rd($fp, 4);

    if ($offset != 0 || $size != 0) {
      printf(" %04d. offset 0x%08x, length %d bytes\n", $i, $offset, $size);
      push @resources, [ $offset, $size ];
    } else {
      printf(" %04d. <empty>\n", $i);
      push @resources, undef;
    }
  }

  # Sanity check: are we at the expected end point?
  if (tell($fp) != $idx_offset{FLEX} + 8 + $indx_size) {
    die "Not at expected point in file.";
  }
}

# FINALLY: seek and dump each resource
for (my $i = 0; $i < scalar @resources; $i ++)
{
  next if (!defined $resources[$i]);
  my ($offset, $length) = @{$resources[$i]};

# skip to the resource
  printf("== FLEX Resource #%d (offset 0x%08x, length %d) ==\n", $i, $offset, $length);
  seek $fp, $offset, SEEK_SET;
  my $data_size = _iff_meta($fp, 'DATA');
  # skip unknown 4 bytes
  seek $fp, 4, SEEK_CUR;

  # FLEX details
  my $flex_size = _iff_meta($fp, 'FLEX');

#FLEX header info
  seek $fp, 10, SEEK_CUR;
  my $basename = unpack 'Z16', _rd($fp, 16);
  my $filename = unpack 'Z16', _rd($fp, 16);

# this is the actual beginning of raw picture data.
#  record the current offset
  my $source = tell($fp);

  my $hasPalette = ord(_rd($fp, 1)) > 0;
  my $cmdFlags = ord _rd($fp, 1);
  my $pixelFlags = ord _rd($fp, 1);
  my $maskFlags = ord _rd($fp, 1);
  my $cmdOffs = unpack 'v', _rd($fp, 2);
  my $pixelOffs = unpack 'v', _rd($fp, 2);
  my $maskOffs = unpack 'v', _rd($fp, 2);
  my $lineSize = unpack 'v', _rd($fp, 2);
  seek $fp, 2, SEEK_CUR;
  my $w = unpack 'v', _rd($fp, 2);
  my $h = unpack 'v', _rd($fp, 2);

next unless ($w > 620 && $h > 470);

  say "  FILENAME: $filename";
  say "  WIDTH: $w";
  say "  HEIGHT: $h";
next unless ($w > 300 && $h > 180);
  say "  Line Size: $lineSize";
  say "  Flags: cmd=$cmdFlags pixel=$pixelFlags mask=$maskFlags";
  printf("  Offsets: cmd=0x%08x pixel=0x%08x mask=0x%08x\n", $cmdOffs, $pixelOffs, $maskOffs);

# palette hackery
  my $palette;
  if ($hasPalette) {
    my $paletteSize = $cmdOffs - 18;
    say "  HAS PALETTE of size $paletteSize";
    $palette = _rd($fp, $paletteSize);
  } else {
    say "  NO PALETTE!";
    # TODO: This means we should re-use a palette from a previous screen image.
    #  But since I have no clue what that would be (depends on the game state),
    #  this is just output in grayscale instead.
  }

# We only support certain combinations of mask, pixel, and command flags
#  if (($maskFlags != 0 && $maskFlags != 2) || ($pixelFlags != 0 && $pixelFlags != 2) || ($cmdFlags != 0)) {

# TODO: maskFlags == 2 causes the mask to be read in "nibble" mode - meaning, if you are in code==3,
#  you get a 4-bit pixel at a time instead of 8-bit.
# Similar for pixelFlags == 2.  These are used for inventory items and such that need only 16 colors.
# Since I only care about the 320x200 images, this never comes up, so I am just skipping these.
  if ($cmdFlags != 0 || $maskFlags != 0 || $pixelFlags != 0) {
    say "ERROR: Unsupported Flags in decompression.";
    next;
  }

####
# IMAGE DECOMPRESSION
#  Decompression is handled as a series of 2-bit commands, stored in a "command line" of length $lineSize.

# output image
  my @output;

#  sanity
  my $cmdSize = $pixelOffs - $cmdOffs;
  my $pixelSize = $maskOffs - $pixelOffs;
  my $maskSize = ($length - 62) - $maskOffs;
say "cmdSize = $cmdSize, pixelSize = $pixelSize, maskSize = $maskSize";

# Parse one image row at a time
  for (my $y = 0; $y < $h; $y += 4) {
    # Read an entire "line" of commands.
    seek $fp, $source + $cmdOffs, SEEK_SET;
    my $cmdBuf = _rd($fp, $lineSize);
    $cmdOffs += $lineSize; $cmdSize -= $lineSize;

    # track ptr for "uh, which 2bytes are we looking at?"
    my $cmdPtr = 0;

    my $x = 0;
    while ($x < $w) {
# Parse the line of commands, 2 bytes at a time.
# Process one 16-bit block at a time.
#  This corresponds to up to 8 commands - a 32x4 block.

      my $bits = ord (substr( $cmdBuf, $cmdPtr, 1));
      $cmdPtr ++;

# Parse each 2-bit command.
      for (my $curCmd = 0; $curCmd < 4 && $x < $w; $curCmd++) {
        my $cmd = $bits & 3;
        $bits >>= 2;

#say "  x=$x y=$y cmd=$cmd";

        if ($cmd == 0) {
# solid-color block
          seek $fp, $source + $pixelOffs, SEEK_SET;
          my $pixel = ord (_rd($fp, 1));
          $pixelOffs ++; $pixelSize --;
          die "Out of pixel data at $x, $y" if $pixelSize < 0;

          for (my $j = 0; $j < 4; $j ++) {
            for (my $i = 0; $i < 4; $i ++) {
              $output[$y + $j][$x + $i] = $pixel;
            }
          }
        } elsif ($cmd == 1) {
# two-color block
          seek $fp, $source + $pixelOffs, SEEK_SET;
          my @pixels = unpack 'C2', _rd($fp, 2);
          $pixelOffs += 2; $pixelSize -= 2;
          die "Out of pixel data at $x, $y" if $pixelSize < 0;

# bit mask determines whether to use color A or B
          seek $fp, $source + $maskOffs, SEEK_SET;
          my $mask = unpack 'v', _rd($fp, 2);
          $maskOffs += 2; $maskSize -= 2;
          die "Out of mask data at $x, $y" if $maskSize < 0;

          for (my $j = 0; $j < 4; $j ++) {
            for (my $i = 0; $i < 4; $i ++) {
              $output[$y + $j][$x + $i] = $pixels[$mask & 1];
              $mask >>= 1;
            }
          }
        } elsif ($cmd == 2) {
# four-color block
          seek $fp, $source + $pixelOffs, SEEK_SET;
          my @pixels = unpack 'C4', _rd($fp, 4);
          $pixelOffs += 4; $pixelSize -= 4;
          die "Out of pixel data at $x, $y" if $pixelSize < 0;

# 2-bit mask determines whether to use color A, B, C or D
          seek $fp, $source + $maskOffs, SEEK_SET;
          my $mask = unpack 'V', _rd($fp, 4);
          $maskOffs += 4; $maskSize -= 4;
          die "Out of mask data at $x, $y" if $maskSize < 0;

          for (my $j = 0; $j < 4; $j ++) {
            for (my $i = 0; $i < 4; $i ++) {
              $output[$y + $j][$x + $i] = $pixels[$mask & 3];
              $mask >>= 2;
            }
          }
        } elsif ($cmd == 3) {
# raw-color read but only if not a deltaFrame
# For EGA pictures: Pixels are read starting from a new byte
#maskReader.resetNibbleSwitch();
# Yes, it reads from maskReader here
          seek $fp, $source + $maskOffs, SEEK_SET;
          for (my $j = 0; $j < 4; $j ++) {
            for (my $i = 0; $i < 4; $i ++) {
              $output[$y + $j][$x + $i] = ord(_rd($fp, 1));
            }
          }
          $maskOffs += 16;
        }
# Destination advances 4pix
        $x += 4;
      }
    }
  }

  say "reached EOF: cmdOffs = $cmdOffs, cmdSize = $cmdSize, pixelOffs = $pixelOffs, pixelSize = $pixelSize, maskOffs = $maskOffs";

  # DUMP TO DISK
  if ($palette) {
    open(my $out, '>', 'out/' . $filename . '.ppm') or die "Can't open output $filename.ppm: $!";
    binmode($out);
    say $out "P6";
    say $out "$w $h";
    say $out "255";
    for (my $y = 0; $y < $h; $y ++) {
      for (my $x = 0; $x < $w; $x ++) {
        print $out substr($palette, 3 * ($output[$y][$x] || 0), 3);
      }
    }
  } else {
    # again, this is not correct (should be using a palette from a different image) - see above
    open(my $out, '>', 'out/' . $filename . '.pgm') or die "Can't open output $filename.pgm: $!";
    binmode($out);
    say $out "P5";
    say $out "$w $h";
    say $out "255";
    for (my $y = 0; $y < $h; $y ++) {
      for (my $x = 0; $x < $w; $x ++) {
        print $out chr($output[$y][$x]);
      }
    }
  }
}
