#!/usr/bin/env perl
use strict;
use warnings;

use v5.014;

use autodie;

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

# recursively read an IFF block
#  return the results as an element or hash or w/e
sub _rec_iff
{
  my ($fp, $depth) = @_;

  my $return;

  # read RIFF chunk
  my ($type, $size) = _iff_meta($fp);
  printf("%08x: %s%s (size=%d) ", tell($fp), ' ' x $depth, $type, $size);
  if ($type eq 'ADDM') {
    # some kind of directory map?
    my $flags1 = unpack 'l<', _rd($fp, 4);
    my $flags2 = unpack 'l<', _rd($fp, 4);
    my $count = unpack 'V', _rd($fp, 4);

    printf(" flags=%d %d count=%d\n", $flags1, $flags2, $count);
    for my $i (0 .. $count - 1) {
      $return->[$i] = _rec_iff($fp, $depth + 1);
    }
  }
  elsif ($type eq 'ADDL') {
    # some kind of directory entry?
    my $flags1 = unpack 'l<', _rd($fp, 4);
    my $flags2 = unpack 'l<', _rd($fp, 4);
    my $count = unpack 'V', _rd($fp, 4);

    printf(" flags=%d %d count=%d\n", $flags1, $flags2, $count);

    for my $i (0 .. $count - 1) {
      $return->[$i] = _rec_iff($fp, $depth + 1);
    }
    #$return = _rec_iff($fp, $depth + 1);
  } elsif ($type eq 'ADVI') {
    # integer
    $return = unpack('l<', _rd($fp, 4));
    printf(" value=%d\n", $return);
  } elsif ($type eq 'ADVF') {
    # double
    $return = unpack('d', _rd($fp, 8));
    printf(" value=%lf\n", $return);
  } elsif ($type eq 'ADVS') {
    # it's a string
    my $length = unpack('V', _rd($fp, 4));
    $return = _rd($fp, $length);
    if ($length % 2) {
      my $padding = ord(_rd($fp, 1));
      warn "Padding ($padding) not 0" unless $padding == 0;
    }
    printf(" value='%s'\n", $return);
  } elsif ($type eq 'NDVE') {
    # this is a file directory entry
    my $file_offset = unpack('V', _rd($fp, 4));
    my $file_size = unpack('V', _rd($fp, 4));
    my $length = unpack('V', _rd($fp, 4));
    my $file_name = _rd($fp, $length);
    if ($length % 2) {
      my $padding = ord(_rd($fp, 1));
      warn "Padding ($padding) not 0" unless $padding == 0;
    }
    printf(" file='%s' (offset=%d, size=%d)\n", $file_name, $file_offset, $file_size);
    $return = { type => 'FILE', offset => $file_offset, size => $file_size, name => $file_name };

    # HACK: we will seek to the ADFI in file here, output it, then jump back here
    my $curr_offset = tell($fp);
    seek($fp, $file_offset, SEEK_SET);

    open my $fpo, '>:raw', $file_name;
    print $fpo _rd($fp, $file_size);
    close $fpo;

    seek($fp, $curr_offset, SEEK_SET);

  } elsif ($type eq 'ADFI') {
    # this is a raw file block, just skip it
    printf(" size=%d - FILE ENTRY\n", $size);
    $return = tell($fp);
    seek($fp, $size, SEEK_CUR);
  } else {
    # block of data
    printf(" size=%d - UNKNOWN\n", $size);
    $return = _rd($fp, $size);
  }

  return $return;
}

####
####
####
die "Usage: $0 <filename>" unless scalar @ARGV == 1;

my $file_size = -s $ARGV[0];
open (my $fp, '<:raw', $ARGV[0]) or die "Couldn't open file $ARGV[0]: $!";

# read RIFF header / filesize
my $riff_size = _iff_meta($fp, 'RIFF');
warn "File size $file_size != expect. $riff_size + 8" unless ($file_size == $riff_size + 8);
my $riff_type = _rd($fp, 4);
warn "Riff_type '$riff_type' != expect. riff_type ADBM" unless ($riff_type eq 'ADBM');

my @assets;
while (! eof($fp)) {
  push @assets, _rec_iff($fp, 0);
}

# We have collected all Assets into one large array data structure
#  Walk the data structure and output FILE information
