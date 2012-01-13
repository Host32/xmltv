# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: programme class
#
###############################################################################
#
# Setup
#
# VERSION: $Id: programme.pm,v 2.00 2011/03/10 21:20:11 stefanb2 Exp $
#
# INSERT FROM HERE ############################################################
package fi::programme;
use strict;
use warnings;
use Carp;
use POSIX qw(strftime);

# Import from internal modules
fi::common->import();

sub _trim {
  return unless defined($_[0]);
  $_[0] =~ s/^\s+//;
  $_[0] =~ s/\s+$//;
}

# Constructor
sub new {
  my($class, $channel, $language, $title, $start, $stop) = @_;
  _trim($title);
  croak "${class}::new called without valid title, start or stop"
    unless defined($channel) && defined($title) && (length($title) > 0) &&
           defined($start) && defined($stop);

  my $self = {
	      channel  => $channel,
	      language => $language,
	      title    => $title,
	      start    => $start,
	      stop     => $stop,
	     };

  return(bless($self, $class));
}

# instance methods
sub category {
  my($self, $category) = @_;
  _trim($category);
  $self->{category} = $category
    if defined($category) && length($category);
}
sub description {
  my($self, $description) = @_;
  _trim($description);
  $self->{description} = $description
    if defined($description) && length($description);
}
sub episode {
  my($self, $episode, $language) = @_;
  _trim($episode);
  if (defined($episode) && length($episode)) {
    $episode =~ s/\.$//;
    push(@{ $self->{episode} }, [$episode, $language]);
  }
}

sub language { $_[0]->{language} }

# Convert seconds since Epoch to XMLTV time stamp
#
# NOTE: We have to generate the time stamp using local time plus time zone as
#       some XMLTV users, e.g. mythtv in the default configuration, ignore the
#       XMLTV time zone value.
#
sub _epoch_to_xmltv_time($) {
  my($time) = @_;

  # Unfortunately strftime()'s %z is not portable...
  #
  # return(strftime("%Y%m%d%H%M00 %z", localtime($time));
  #
  # ...so we have to roll our own:
  #
  my @time = localtime($time); #               is_dst
  return(strftime("%Y%m%d%H%M00 +0", @time) . ($time[8] ? "3": "2") . "00");
}

# Configuration data
my %series_description;
my %series_title;
my @title_map;

sub dump {
  my($self, $writer) = @_;
  my $language    = $self->{language};
  my $title       = $self->{title};
  my $category    = $self->{category};
  my $description = $self->{description};
  my $subtitle    = $self->{episode};

  #
  # Programme post-processing
  #
  # Title mapping
  #
  foreach my $map (@title_map) {
    if ($map->($title)) {
      debug(3, "XMLTV title '$self->{title}' mapped to '$title'");
      last;
    }
  }

  #
  # Check 1: object already contains episode
  #
  my($left, $right);
  if (defined($subtitle)) {
    # nothing to be done
  }
  #
  # Check 2: title contains episode name
  #
  # If title contains a colon (:), check to see if the string on the left-hand
  # side of the colon has been defined as a series in the configuration file.
  # If it has, assume that the string on the left-hand side of the colon is
  # the name of the series and the string on the right-hand side is the name
  # of the episode.
  #
  # Example:
  #
  #   config: series title Prisma
  #   title:  Prisma: Totuus tappajadinosauruksista
  #
  # This will generate a program with
  #
  #   title:     Prisma
  #   sub-title: Totuus tappajadinosauruksista
  #
  elsif ((($left, $right) = ($title =~ /([^:]+):\s*(.*)/)) &&
	 (exists $series_title{$left})) {
    debug(3, "XMLTV series title '$left' episode '$right'");
    ($title, $subtitle) = ($left, $right);
  }
  #
  # Check 3: description contains episode name
  #
  # Check if the program has a description. If so, also check if the title
  # of the program has been defined as a series in the configuration. If it
  # has, assume that the first sentence (i.e. the text before the first
  # period, question mark or exclamation mark) marks the name of the episode.
  #
  # Example:
  #
  #   config:      series title Batman
  #   description: Pingviinin paluu. Amerikkalainen animaatiosarja....
  #
  # This will generate a program with
  #
  #   title:       Batman
  #   sub-title:   Pingviinin paluu.
  #   description: Amerikkalainen animaatiosarja....
  #
  elsif ((defined $description)               &&
	 (exists $series_description{$title}) &&
         (($left, $right) = ($description =~ /^\s*([^.!?]+[.!?])\s*(.*)/))) {
    # We only remove period from episode title, preserve others
    $left =~ s/\.$//;
    debug(3, "XMLTV series title '$title' episode '$left'");
    ($subtitle, $description) = ($left, $right);
  }

  # XMLTV programme desciptor (mandatory parts)
  my %xmltv = (
	       channel => $self->{channel},
	       start   => _epoch_to_xmltv_time($self->{start}),
	       stop    => _epoch_to_xmltv_time($self->{stop}),
	       title   => [[$title, $language]],
	      );
  debug(3, "XMLTV programme '$xmltv{channel}' '$xmltv{start} -> $xmltv{stop}' '$title'");

  # XMLTV programme descriptor (optional parts)
  if (defined($subtitle)) {
    $subtitle = [[$subtitle, $language]]
      unless ref($subtitle);
    $xmltv{'sub-title'} = $subtitle;
    debug(3, "XMLTV programme episode ($_->[1]): $_->[0]")
      foreach (@{ $xmltv{'sub-title'} });
  }
  if (defined($category) && length($category)) {
    $xmltv{category} = [[$category, $language]];
    debug(4, "XMLTV programme category: $category");
  }
  if (defined($description) && length($description)) {
    $xmltv{desc} = [[$description, $language]];
    debug(4, "XMLTV programme description: $description");
  }

  $writer->write_programme(\%xmltv);
}

# class methods
# Parse config line
sub parseConfigLine {
  my($class, $line) = @_;

  # Extract words
  my($command, $keyword, $param) = split(' ', $line, 3);

  if ($command eq "series") {
    if ($keyword eq "description") {
      $series_description{$param}++;
    } elsif ($keyword eq "title") {
      $series_title{$param}++;
    } else {
      # Unknown series configuration
      return;
    }
  } elsif (($command eq "title") &&
	   ($keyword eq "map")   &&
	   # Accept "title" and 'title' for each parameter
	   (my(undef, $from, undef, $to) =
	    ($param =~ /^([\'\"])([^\1]+)\1\s+([\'\"])([^\3]+)\3/))) {
    debug(3, "title mapping from '$from' to '$to'");
    $from = qr/^\Q$from\E/;
    push(@title_map, sub { $_[0] =~ s/$from/$to/ });
  } else {
    # Unknown command
    return;
  }

  return(1);
}

# Fix overlapping programmes
sub fixOverlaps {
  my($class, $list) = @_;

  # No need to cleanup empty/one-entry lists
  return unless defined($list) && (@{ $list } >= 2);

  my $current = $list->[0];
  foreach my $next (@{ $list }[1..$#{ $list }]) {

    # Does next programme start before current one ends?
    if ($current->{stop} > $next->{start}) {
      debug(3, "Fixing overlapping programme '$current->{title}' $current->{stop} -> $next->{start}.");
      $current->{stop} = $next->{start};
    }

    # Next programme
    $current = $next;
  }
}

# That's all folks
1;