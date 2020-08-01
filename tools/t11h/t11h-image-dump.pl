#!/usr/bin/env perl
use strict;
use warnings;

use v5.010;

use Carp qw(confess);
use Fcntl qw(:seek);

### DUMPER FOR "THE 11TH HOUR" IMAGE FILES
# Greg Kennedy 2018
# Written from a spec at
#  http://wiki.xentax.com/index.php/The_11th_Hour_GJD
#  http://wiki.xentax.com/index.php/The_11th_Hour_ROL

# Usage: ./dump.pl GJD.GJD DIR.RL MEDIAPATH

####
# helper: safe read
#  params: fp, length
sub _rd
{
  my $bytes_read = read $_[0], my $buffer, $_[1];
  confess "Short read on file: expected $_[1] but got $bytes_read: $!" unless $bytes_read == $_[1];
  return $buffer;
}

##### MAIN SCRIPT BEGINS HERE
die "Usage: $0 GJD.GJD DIR.RL MEDIAPATH" unless scalar @ARGV == 3;

# Master struct of all resource names / locations
my @res;

# GJD is a list of File Name -> File ID Number, very simple
say "Opening $ARGV[0]...";
open (my $gjd, '<', $ARGV[0]) or die "Can't open $ARGV[0]: $!";
while (my $line = <$gjd>) {
  chomp $line;
  my ($name, $id) = split / /, $line;

  say "  -> $id: $name";

  $res[$id]{filename} = $name;
}
close($gjd);

# RL is the Resource Listing, it has a binary format and gets us contents of each gjd
say "Opening $ARGV[1]...";
open (my $rl, '<', $ARGV[1]) or die "Can't open $ARGV[1]: $!";
binmode ($rl);
while (!eof $rl) {
  # read res listing entry
  my $entry = _rd($rl, 32);
  my ($unknown, $offset, $length, $id, $filename) = unpack 'VVVvZ12', $entry;

  say "  $res[$id]{filename}/$filename: offset $offset, length $length";

  push @{$res[$id]{contents}}, [$filename, $offset, $length];
}
close($rl);

# trawl through every file in the media listing and retrieve everything from it
mkdir 'out';
for (my $id = 0; $id < scalar @res; $id ++)
{
  # th_music.gjd causes issues in extract, skip it
  next if ($res[$id]{filename} eq 'th_music.gjd');

  # make output folder
  mkdir ('out/' . $res[$id]{filename});

  say "Opening $ARGV[2]/$res[$id]{filename}...";
  open (my $media, '<', $ARGV[2] . '/' . $res[$id]{filename}) or die "Can't open $ARGV[2]/$res[$id]{filename}: $!";
  binmode($media);

  # get all resources
  foreach my $index (@{$res[$id]{contents}}) {
    my ($filename, $offset, $length) = @$index;

    say " . Parsing $filename (off: $offset, len: $length)...";
    # seek to the offset
    if (tell $media != $offset) {
      say " . Seeking from " . tell($media) . " to offset $offset.";
      seek $media, $offset, SEEK_SET;
    }

    # sometimes there is >1 jpg per roq/rol, so this id splits them
    my $jpg_id = 0;

    while ($length > 0) {
      # read the rol header
      my $rol_header = _rd($media, 8);
      $length -= 8;

      # time to parse ROL
      my ($type, $identifier, $data_size, $block_param) = unpack('CCVv', $rol_header);
      #say "  - TYPE $type, id $identifier, size $data_size";

      if ($type == 0x84) {
        #say " - - BLOCK HEADER";
      } elsif ($type == 0x01) {
        my $rol_data = _rd($media, $data_size);
        $length -= $data_size;
        my ($w, $h, $u1, $u2) = unpack('vvvv', $rol_data);
        #say " - - IMAGE METADATA: $w x $h";
      } elsif ($type == 0x12) {
        my $output_filename = 'out/' . $res[$id]{filename} . '/' . $filename . '.' . $jpg_id . '.jpg';
        open (my $fpo, '>', $output_filename) or die "can't open output file $output_filename: $!";
        binmode($fpo);
        print $fpo _rd($media, $data_size);
        $length -= $data_size;
        close($fpo);
        say " - - JPEG image $filename.$jpg_id.jpg";
        $jpg_id ++;
      } else {
        # seek over the length
        #say " - - OTHER";
        seek $media, $data_size, SEEK_CUR;
        $length -= $data_size;
      }
    }
  }

  close($media);
}

