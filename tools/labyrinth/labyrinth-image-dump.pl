#!/usr/bin/env perl
use strict;
use warnings;
use autodie;

use Fcntl qw( SEEK_SET );

use constant DUMP_PPM => 1;
use constant DUMP_WAV => 0;

sub r {
  my $c = read $_[0], my $b, $_[1];
  die "Short read on input: expected $_[1], got $c" unless $c == $_[1];
  return $b;
}

sub iff {
  my ($signature, $size) = unpack 'VV', r($_[0], 8);
  # read the block too and return it
  return ($signature, r($_[0], $size));
}

print STDERR "== $ARGV[0] ==\n";

open my $fp, '<:raw', $ARGV[0];

# check filetype and magic number
my ($filetype, $filemagic) = unpack 'VV', r($fp, 8);
die "Not a DIFF file" unless $filetype == 0x46464944;
die "Incorrect MAGIC" unless $filemagic == 1219009121;

# Reads a IFF "block"
my ($headerSig, $header) = iff($fp);
die "Expected block type 0, got $headerSig" unless $headerSig == 0;
# parse header info
my ($version, $width, $height, $depth, $fps, $buffSize, $machine, $flags) = unpack 'vvvCCVvV', $header;

# print some info
print STDERR join(',', $version, $width, $height, $depth, $fps, $buffSize, $machine, $flags) . "\n";

# loop and parse all blocks
my $palette;
my $buffer = '';
my $blockNum = 0;
while (! eof($fp)) {
  # Reads a IFF "block"
  my ($blockSig, $block) = iff($fp);
  $blockNum ++;

  my $needsDump;

  if ($blockSig == 8) {
    # palette block
    print STDERR " . $blockNum: Palette (" . length($block) . ")\n";

    #  palettes are 6 bits per color (VGA standard) so must be
    #  expanded to 8 bits here.
    $palette = join('', map { chr( ($_ << 2) | ($_ >> 4) ) } (unpack 'C*', $block));
  } elsif ($blockSig == 10) {
    # raw read and append to buffer
    print STDERR " . $blockNum: Raw read buffer (" . length($block) . ")\n";
    $buffer .= $block;
    $needsDump = 1;
  } elsif ($blockSig == 11) {
    # RLE read and append to buffer
    print STDERR " . $blockNum: RLE Read buffer (" . length($block) . ")\n";

    my ($unpackSize, @b) = unpack('VC*', $block);
    #print STDERR "    (size=$unpackSize)\n";
    while (@b) {
      my $mark = shift @b;
      if ($mark == 127) {
        # EOF marker
        @b = ();
      } elsif ($mark < 127) {
        # Copy N bytes
        while ($mark) {
          $buffer .= chr(shift @b);
          $mark --;
        }
      } else {
        # Repet byte N times
        my $value = chr(shift @b);
        $buffer .= ($value x (256 - $mark));
      }
    }
    $needsDump = 1;
  } elsif ($blockSig == 12) {
    # "Vertical" RLE read
    print STDERR " . $blockNum: Vertical RLE Read buffer (" . length($block) . ")\n";
    die "Vertical RLE unsupported";
  } elsif ($blockSig == 20) {
    # Call UnDiff on the data here
    print STDERR " . $blockNum: UnDIFF (" . length($block) . ")\n";
    die "UnDIFF unsupported";
  } elsif ($blockSig == 21) {
    # Call UnDiff on the data here
    print STDERR " . $blockNum: UnDIFF 2 (" . length($block) . ")\n";
    die "UnDIFF unsupported";
  } elsif ($blockSig == 25 || $blockSig == 26) {
    # No-op (frame advance?)
    print STDERR " . $blockNum: NO-OP (" . length($block) . ")\n";
  } elsif ($blockSig == 30 || $blockSig == 31) {
    # Play embedded sound effect.
    print STDERR " . $blockNum: Play Sound (" . length($block) . ")\n";

    if (DUMP_WAV) {
      my ($u, $sampleRate, $u2) = unpack('Vvv', substr($block, 0, 8));
      print STDERR "    => $u, $sampleRate, $u2\n";
  
      # dump WAV file of the sample
      open my $fpo, '>:raw', "$ARGV[0].$blockNum.wav";
      print $fpo pack('NVNNVvvVVvvNV', 0x52494646, 36 + length($block) - 8, 0x57415645,
        0x666d7420, 16, 1, 1, $sampleRate, $sampleRate, 1, 8,
        0x64617461, length($block) - 8) . substr($block, 8);
    }
  } elsif ($blockSig == 65535) {
    # EoF
    print STDERR " . $blockNum: EOF Marker (" . length($block) . ")\n";
  } else {
    warn " ! $blockNum: Unknown block sig $blockSig (" . length($block) . ")";
  }

  if ($needsDump) {
    if ($width * $height != length($buffer)) {
#      warn "W H mismatch ($width * $height == " . ($width * $height) . ", != " . length($buffer) . ")";
      next;
    }

    if (DUMP_PPM) {
      open my $fpo, '>:raw', "$ARGV[0].ppm";
      print $fpo "P6\n$width $height\n255\n";
      map { print $fpo substr($palette, 3 * ord($_), 3) } split //, $buffer;
    }
    exit;
  }
}
