#!/usr/bin/env perl
use strict;
use warnings;

use v5.010;

### DUMPER FOR "THE 7TH GUEST" VDX IMAGE FILES
# Greg Kennedy 2018
# Written from a spec at
#  http://wiki.xentax.com/index.php/The_7th_Guest_VDX

# Usage: ./dump.pl <FILE, without RL or GJD extension>

####
# helper: safe read
#  params: fp, length
sub _rd
{
  my $bytes_read = read $_[0], my $buffer, $_[1];
  die "Short read on file: expected $_[1] but got $bytes_read: $!" unless $bytes_read == $_[1];
  return $buffer;
}

# lzss decompression
#  given a size, and a reference to a data block,
#  and some deke params (len_bits / mask)
#  return u_data (uncompressed data block)
sub lzss {
  my ($data_ref, $data_size, $len_mask, $len_bits) = @_;

  my $u_data;
  my $ptr = 0;

  while ($ptr < $data_size) {
    my $flagByte = ord(substr($$data_ref, $ptr, 1)); $ptr ++;
    for (my $i = 0; $i < 8 && $ptr < $data_size; $i ++) {
      if ($flagByte & 1) {
        # 1-byte flat copy
        $u_data .= substr($$data_ref, $ptr, 1); $ptr ++;
      } else {
        # lookback copy
        my $c_param = unpack 'v', substr($$data_ref, $ptr, 2); $ptr += 2;
        # c_param == 0 indicates "end of file"
        last if $c_param == 0;

        # determine copy-length and offset
        my $copy_len = ($c_param & $len_mask) + 3;
        my $offset = $c_param >> $len_bits;

        # copy n bytes, one at a time, from offset back in decoded data
        for (my $j = 0; $j < $copy_len; $j ++) {
          $u_data .= substr($u_data, -$offset, 1);
        }
      }
      $flagByte >>= 1;
    }
  }

  return $u_data;
}

####
# helper: decode an image
#  params: file pointer
#  returns: width, height, bitdepth (8), 768-bytes Palette,
#    image[w][h] reference (paletted)
sub decode_image
{
  my $dh = shift;

  # time to composite an image
  my ($w, $h, $depth) = unpack 'vvv', _rd($dh, 6);
  $w *= 4; $h *= 4;
  say " - - - Dimensions: $w x $h, $depth bpp";

  # retrieve palette
  my $palette = _rd($dh, 768);

  # Unpack blocks
  my @image;
  for (my $y = 0; $y < $h; $y += 4) {
    for (my $x = 0; $x < $w; $x += 4) {
      my ($color1, $color0, $map) = unpack 'CCv', _rd($dh, 4);

      my $flag = 0x8000;
      for (my $j = 0; $j < 4; $j ++) {
        for (my $i = 0; $i < 4; $i ++) {
          if ($flag & $map) {
            $image[$y + $j][$x + $i] = $color1;
          } else {
            $image[$y + $j][$x + $i] = $color0;
          }
          $flag >>= 1;
        }
      }
    }
  }

  return ($w, $h, $depth, $palette, \@image);
}

##### MAIN SCRIPT BEGINS HERE
die "Usage: $0 BASENAME" unless scalar @ARGV == 1;

my $basename = $ARGV[0];
open (my $rl, '<', $basename . '.RL') or die "Can't open $basename.RL: $!";
binmode($rl);

open (my $gjd, '<', $basename . '.GJD') or die "Can't open $basename.GJD: $!";
binmode($gjd);

# make output folder
mkdir $basename;

while (!eof $rl)
{
  # read resource listing entry
  my $rl_entry = _rd($rl, 20);
  my ($filename, $gjd_offset, $gjd_length) = unpack 'Z12VV', $rl_entry;

  say "$filename: offset $gjd_offset, length $gjd_length";

  # seek to the offset
  if (tell $gjd != $gjd_offset) {
    say " . Seeking from " . tell($gjd) . " to offset $gjd_offset.";
    seek $gjd, $gjd_offset, 0;
  }
  # read the vdx header
  my $vdx_header = _rd($gjd, 8);
  $gjd_length -= 8;

  # time to parse VDX
  my $vdx_id = unpack 'v', substr($vdx_header, 0, 2);;
  if ($vdx_id != 0x9267) {
    # The XMI.GJD file contains things that are definitely not VDX files.
    #  Probably RIFF X-MIDI soundtrack or something.
    say " * ERROR: vdx unknown ID $vdx_id";
    next;
  }

  while ($gjd_length > 0) {
    # read gjd header
    my $chunk_header = _rd($gjd, 8);
    $gjd_length -= 8;

    my ($type, $data_size, $len_mask, $len_bits) = unpack 'CxVCC', $chunk_header;
    say " - Data block: type $type, size $data_size, mask / bits = 0x" . sprintf('%02x',$len_mask) . " / $len_bits";

    # parse up the data block
    if ($type == 0x20) {
      say " - - Type 0x20: IMAGE DATA";

      my ($w, $h, $depth, $palette, $image);

      # decode image based on type
      if ($len_mask == 0 && $len_bits == 0) {
        say " - - - Is uncompressed.";

        # retrieve data block
        #$data = _rd($gjd, $data_size);
        #$gjd_length -= $data_size;
        ($w, $h, $depth, $palette, $image) = decode_image($gjd);
        $gjd_length -= $data_size;

      } else {
        say " - - - Is COMPRESSED :(";
        my $c_data = _rd($gjd, $data_size);
        $gjd_length -= $data_size;

        my $data = lzss(\$c_data, $data_size, $len_mask, $len_bits);

        # set up a data handle
        open my $dh, "<", \$data;
        # go get the image
        ($w, $h, $depth, $palette, $image) = decode_image($dh);
        close($dh);
      }

      # Dump PPM
      # Ready to store file
      die "Error: output file exists" if (-f $basename . '/' . $filename . '.ppm');
      open (my $out, '>', $basename . '/' . $filename . '.ppm') or die "Couldn't open $basename/$filename.pbm for write: $!";
      binmode($out);
      say $out "P6";
      say $out "$w $h";
      say $out 255;
      for (my $y = 0; $y < $h; $y ++) {
        for (my $x = 0; $x < $w; $x ++) {
          print $out substr($palette, 3 * $image->[$y][$x], 3);
        }
      }
    } elsif ($type == 0x00 || $type == 0x25 || $type == 0x80) {
      say " - - Type $type: skipping...";
      seek ($gjd, $data_size, 1);
      $gjd_length -= $data_size;
    } else {
      die "Unknown block type $type.";
    }
  }

  # should be terminating 0xFF on each record
  my $terminator = ord _rd($gjd, 1);
  die "Expected terminator 255 but got $terminator instead" unless $terminator == 0xFF;
}
