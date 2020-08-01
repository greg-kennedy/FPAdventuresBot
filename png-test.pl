#!/usr/bin/env perl
use strict;
use warnings;

use v5.014;

use Data::Dumper;

### A tool to detect duplicate or problem PNG images.
###  Recursively searches the folders for png images,
###  decodes them to flat BMP, then stores the shasum
###  in a hash along with dimensions.

### Solid-color frames are also detected and printed.

# fudge @INC
#use FindBin qw( $RealBin );
#use lib $RealBin;

use Image::PNG::Libpng qw(:all);
use Image::PNG::Const qw/PNG_TRANSFORM_EXPAND PNG_TRANSFORM_STRIP_ALPHA/;
use Digest::SHA qw(sha1_hex);

use File::Basename;

### Helper Functions
# Recursively read a directory and add results to an array.
sub rec_read_dir
{
  my $d = shift;

  my @files;

  opendir(my $dh, $d) || die "Can't open directory $d: $!\n";
  while (readdir $dh) {
    next if substr($_,0,1) eq '.';

    my $path = $d . '/' . $_;
    if (-d $path) {
      push @files, rec_read_dir($path);
    } elsif (-f $path) {
      if ($path =~ m/\.png$/) {
        push @files, $path;
      }
    }
  }
  closedir($dh);

  return @files;
}

# check args
if (scalar @ARGV != 1) { die "Usage: $0 /path/to/images" }

# Get complete list of files
my %contents;

my $peak_red = 0;
my $peak_green = 0;
my $peak_blue = 0;

my @files = rec_read_dir($ARGV[0]);

foreach my $file (@files) {
  print STDERR ". Testing $file...";

  # decode the image
  my $png = read_png_file($file, transforms => PNG_TRANSFORM_EXPAND | PNG_TRANSFORM_STRIP_ALPHA);

  if ( $png->get_channels() == 1 ) {
    say STDERR " Is grayscale, skipping.";
    say "echo $file # GRAYSCALE";
    next;
  }

  # get the rows
  my $rows = $png->get_rows ();

  # concatenated final file content
  my $content;

  # check for all pixels same as first
  my $pixels_differ = 0;
  my $hot_pixels = 0;
  my $black_pixels = 0;
  my $white_pixels = 0;

  my @first_pixel = unpack 'C3', $rows->[0];

  foreach my $row (@$rows) {
    # append rows together
    $content .= $row;

    # search for black frame, hot pixel, and peak RGB
    my @pixels = unpack 'C*', $row;

    while (@pixels) {
      my ($r, $g, $b) = splice @pixels, 0, 3;

      if ($r == 0 && $g == 0 && $b == 0) { $black_pixels ++ }
      elsif ($r == 255 && $g == 255 && $b == 255) { $white_pixels ++ }
      elsif ( ( $r == 0 || $r == 255) &&
              ( $g == 0 || $g == 255) &&
              ( $b == 0 || $b == 255) ) {
        $hot_pixels ++;
      } else
      {
        # only test pixel-difference for not-hot, not-black, not-white pixels.

        if ($first_pixel[0] != $r ||
            $first_pixel[1] != $g ||
            $first_pixel[2] != $b) {
          $pixels_differ = 1;

          if ($r > $peak_red) { $peak_red = $r }
          if ($g > $peak_green) { $peak_green = $g }
          if ($b > $peak_blue) { $peak_blue = $b }
        }
      }
    }
  }

  # black frame
  if (! $pixels_differ) {
    say STDERR "Solid frame!";
    say "rm $file";
    next;
  }

  # lots of black (transparent frame?)
  if ($black_pixels > 10000) {
    print STDERR " ($black_pixels black_pixels) ";
    say "echo $file # $black_pixels";
  }

  # checksum the data
  my $sha1 = sha1_hex($content);
  say STDERR $sha1;

  push @{$contents{$sha1}}, $file;
}

# output some stats
say STDERR "====================================";
say STDERR "Peak RGB values were ($peak_red, $peak_green, $peak_blue)";

# print all dupes
foreach my $sum (sort keys %contents) {
  if (scalar @{$contents{$sum}} > 1) {
    say "# SUM: $sum";
    my @dupes = sort @{$contents{$sum}};

    # build the "mv" string to keep one file
    my ($name,$path,$suffix) = fileparse($dupes[0],'\.png');

    my $final_filename = $path;
    $final_filename .= join('+', map { (fileparse($_, '\.png'))[0] } @dupes) . $suffix;

    # output the mv string
    say "mv $dupes[0] $final_filename";
    for (my $i = 1; $i < scalar @dupes; $i ++) {
      say "rm $dupes[$i]";
    }
    say "";
  }
}

