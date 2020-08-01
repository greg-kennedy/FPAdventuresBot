#!/usr/bin/env perl
use strict;
use warnings;

use v5.014;

use Fcntl qw( :seek );

####
# helper: Unpack bytestream that was RLE-packed
#  params: input stream array
sub _rle_unpack
{
  my @out;

  while (@_) {
    my $byte = shift @_;
    # unsure if 0x80 is repeat or not, but it never actually appears in the data
    if ($byte > 0x80) {
      my $repeat_count = 257 - $byte;
      my $byte = shift @_;
      for (my $q = 0; $q < $repeat_count; $q ++) {
        push @out, $byte;
      }
    } else {
      my $repeat_count = 1 + $byte;
      for (my $q = 0; $q < $repeat_count; $q ++) {
        push @out, shift @_;
      }
    }
  }

  return @out;
}

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
open (my $fp, '<:raw', $ARGV[0]) or die "Couldn't open file $ARGV[0]: $!";

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
  say "... Advancing to FLEX offset.";
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
    warn "Not at expected point in file.";
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

  # FLEX header info
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
  my $u = unpack 'v', _rd($fp, 2);
  my $w = unpack 'v', _rd($fp, 2);
  my $h = unpack 'v', _rd($fp, 2);

#next unless ($w > 600 && $h > 390);

  say "  FILENAME: $filename";
  say "  WIDTH: $w";
  say "  HEIGHT: $h";
  say "  Line Size: $lineSize";
  say "  Unknown: $u";
  say "  Flags: cmd=$cmdFlags pixel=$pixelFlags mask=$maskFlags";
  printf("  Offsets: source=0x%08x cmd=0x%08x pixel=0x%08x mask=0x%08x\n", $source, $cmdOffs, $pixelOffs, $maskOffs);

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



####
# IMAGE DECOMPRESSION
#  Decompression is handled as a series of 2-bit commands, stored in a "command line" of length $lineSize.

  # output image
  my @output;

  seek $fp, $source + $cmdOffs, SEEK_SET;
  my $cmdSize = $pixelOffs - $cmdOffs;
  my @cmdBuf = unpack('C*', _rd($fp, $cmdSize));
  if ($cmdFlags == 0) {
    say "Command set is uncompressed";
  } elsif ($cmdFlags == 1) {
    say "Command set is RLE compressed";
    @cmdBuf = _rle_unpack(@cmdBuf);
  } else {
    say "Unknown command set $cmdFlags";
    next;
  }

  seek $fp, $source + $pixelOffs, SEEK_SET;
  my $pixelSize = $maskOffs - $pixelOffs;
  my @pixelBuf = unpack('C*', _rd($fp, $pixelSize));
  if ($pixelFlags == 0) {
    say "Pixel set is uncompressed";
  } elsif ($pixelFlags == 1) {
    say "Pixel set is RLE compressed";
    @pixelBuf = _rle_unpack(@pixelBuf);
  } else {
    say "Unknown pixel set $pixelFlags";
    next;
  }

  seek $fp, $source + $maskOffs, SEEK_SET;
  my $maskSize = ($length - 62) - $maskOffs;
  my @maskBuf = unpack('C*', _rd($fp, $maskSize));
  if ($maskFlags == 0) {
    say "Mask set is uncompressed";
  } elsif ($maskFlags == 1) {
    say "Mask set is RLE compressed";
    @maskBuf = _rle_unpack(@maskBuf);
  } else {
    say "Unknown mask set $maskFlags";
    next;
  }

  # sanity
  say "cmdSize = $cmdSize, pixelSize = $pixelSize, maskSize = $maskSize";

  # Parse one image row at a time
  #  read whole command buffer
  #  do one line at a time
  for (my $y = 0; $y < $h; $y += 4)
  {
   # Parse the line of commands, one byte at a time.
    my $x = 0;
    for (my $line = 0; $line < $lineSize; $line ++) {

      # get command byte
      my $bits = shift @cmdBuf;

    # Parse each 2-bit command.
      for (my $curCmd = 0; $curCmd < 4 && $x < $w; $curCmd++) {
        my $cmd = $bits & 3;
        $bits >>= 2;

  #say "  x=$x y=$y cmd=$cmd";

        if ($cmd == 0) {
  # solid-color block
          my $pixel = shift @pixelBuf;

          for (my $j = 0; $j < 4; $j ++) {
            for (my $i = 0; $i < 4; $i ++) {
              $output[$y + $j][$x + $i] = $pixel;
            }
          }
        } elsif ($cmd == 1) {
  # two-color block
          my @pixels = (shift @pixelBuf, shift @pixelBuf);

  # bit mask determines whether to use color A or B
          for (my $h = 0; $h < 2; $h ++) {
            my $mask = shift @maskBuf;
            for (my $j = 0; $j < 2; $j ++) {
              for (my $i = 0; $i < 4; $i ++) {
                $output[$y + $j + 2 * $h][$x + $i] = $pixels[$mask & 1];
                $mask >>= 1;
              }
            }
          }
        } elsif ($cmd == 2) {
  # four-color block
          my @pixels = (shift @pixelBuf, shift @pixelBuf, shift @pixelBuf, shift @pixelBuf);

  # 2-bit mask determines whether to use color A, B, C or D
          for (my $j = 0; $j < 4; $j ++) {
            my $mask = shift @maskBuf;
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
          for (my $j = 0; $j < 4; $j ++) {
            for (my $i = 0; $i < 4; $i ++) {
              $output[$y + $j][$x + $i] = shift @maskBuf;
            }
          }
        }
  # Destination advances 4pix
        $x += 4;
      }
    }
  }
  say "reached EOF: cmdSize = " . scalar(@cmdBuf) . ", pixelSize = " . scalar(@pixelBuf) . ", maskSize = " . scalar(@maskBuf);

  # DUMP TO DISK
  if ($palette) {
    open(my $out, '>', 'out/' . $filename . '.ppm') or die "Can't open output $filename.ppm: $!";
    binmode($out);
    say $out "P6";
    say $out "$w $h";
    say $out "255";
    for (my $y = 0; $y < $h; $y ++) {
      for (my $x = 0; $x < $w; $x ++) {
        print $out substr($palette, 3 * $output[$y][$x], 3);
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
