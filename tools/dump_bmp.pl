#!/usr/bin/env perl
use strict;
use warnings;

use autodie;

# Tool to search a file for possible BMP images and dump them.
my $filesize = -s $ARGV[0];

open my $fp, '<:raw', $ARGV[0];
my $buffer;
read $fp, $buffer, $filesize;
close $fp;

my $p = index($buffer, 'BM');

while ($p >= 0) {
  my $size = unpack('V', substr($buffer, $p+2, 4));

  if ($p + $size <= $filesize) {
    print STDERR "Dumping BMP from $ARGV[0] offset $p length $size\n";
    open my $fpo, '>:raw', $ARGV[0] . '.' . $p . '.bmp';
    print $fpo substr($buffer, $p, $size);
    close $fpo;
  }

  $p = index($buffer, 'BM', $p + 2);
}
