#!/usr/bin/env perl
use v5.014;
use warnings;

###
# A Twitter bot to post a gallery, one pic at a time, every N hours

# local path for the config files
use FindBin qw( $RealBin );

use Twitter::API;
use Twitter::API::Util 'timestamp_to_time';

use File::Basename 'fileparse';
use Scalar::Util 'blessed';

### Globals
my %mime_types = (
  '.jpg' => 'image/jpeg',
  '.png' => 'image/png',
);

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
      if ($path =~ m/\.(jpg|png)$/) {
        push @files, $path;
      }
    }
  }
  closedir($dh);

  return @files;
}

###############################################################
### CODE
###############################################################
# Go read the config file
my %config = do "$RealBin/config.pl"
  or die "Couldn't read config.pl: $! $@";

eval {
  # Connect to Twitter
  my $client = Twitter::API->new_with_traits(
    traits          => [ qw( NormalizeBooleans DecodeHtmlEntities RetryOnError ApiMethods ) ],
    consumer_key    => $config{consumer_key},
    consumer_secret => $config{consumer_secret},
    access_token    => $config{access_token},
    access_token_secret => $config{access_token_secret},
  );

  # get my timeline (keeping state in Twitter, tsk tsk)
  #  really just the most recent status please
  my $status = $client->user_timeline({ count => 1, trim_user => 1, exclude_replies => 1, include_rts => 0 })->[0];

  # what is the datestamp?
  print "\tLast updated at $status->{created_at}.\n";
  my $time_last_post = timestamp_to_time($status->{created_at});
  my $time_since_post = time - $time_last_post;
  if ($time_since_post < $config{time_between_posts})
  {
    print "\tNot posting: only $time_since_post seconds have passed (of $config{time_between_posts})\n";
    return;
  }

  # Pick an image to post.
  my @files = rec_read_dir("$RealBin/data");

  my $path = $files[int rand @files];

  # Retrieve info about image.
  my($filename, $dirs, $suffix) = fileparse($path, '\..{3}$');

  # Somewhere in this folder should be a corresponding .ctl file.
  my $control_file = $dirs . 'game.ctl';
  open (my $fh, '<:encoding(utf8)', $control_file) or die "Couldn't open control file '$control_file': $!";
  my $game_info = join ('', <$fh>);
  close $fh;

  ###
  # Optimize image first
  if ($suffix eq '.png') {
    `optipng -o7 -strip all -zm1-9 $path`;
  } elsif ($suffix eq '.jpg') {
    #`jpegtran -optimize -progressive -copy none $path`;
    say "JPEG, doing nothing";
  } else {
    die "Error: suffix $suffix is not supported (must be png or jpg)";
  }

  ###
  # READY TO POST!!
  # Upload media image
  my $upload_return_object = $client->upload_media( { media => [$path, $filename, "Content_Type => " . $mime_types{$suffix} ] } );

  # Compose tweet.
  my $post = $game_info . "ID: $filename";
  # Post!
  $client->update({status => $post, media_ids => $upload_return_object->{media_id}});
};

# error handling
if ( my $err = $@ ) {
  die $@ unless blessed $err && $err->isa('Net::Twitter::Lite::Error');

  warn "HTTP Response Code: ", $err->code, "\n",
       "HTTP Message......: ", $err->message, "\n",
       "Twitter error.....: ", $err->error, "\n";
}
