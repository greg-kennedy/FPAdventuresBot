#!/usr/bin/env perl
use strict;
use warnings;

use autodie;

open my $fp, '<:raw', $ARGV[0];
read $fp, my $buffer, -s $ARGV[0];
close $fp;

my $p = 0;

my $first_item = unpack('V', substr($buffer, 0, 4));
print "First item at $first_item (" . ($first_item / 4) . " items)\n";

my @o = unpack 'V*', substr($buffer, 0, $first_item);
push @o, -s $ARGV[0];

foreach my $i (0 .. $#o - 1) {
  my $offset = $o[$i];
  my $size = $o[$i+1] - $offset;

  print "$i: Dumping $size from $offset...";

  # attempt to determine type
  my $ext;
  if (substr($buffer, $offset, 2) eq "\xFF\xD8") {
    $ext = 'jpg';
  } elsif (substr($buffer, $offset, 2) eq "\0\0") {
    $ext = 'tga';
  } elsif (substr($buffer, $offset, 4) eq "RIFF") {
    # TODO: this could be a .wav or a .mp3, should check the contained type
    $ext = 'wav';
  } else {
    $ext = 'bin';
  }
  print " $ext\n";
  open my $fpo, '>:raw', $ARGV[0] . '.' . $i . '.' . $offset . '.' . $ext;
  print $fpo substr($buffer, $offset, $size);
  close $fpo;
}
