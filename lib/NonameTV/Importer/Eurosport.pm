package NonameTV::Importer::Eurosport;

use strict;
use warnings;

=pod

Import data from xml-files that we download via FTP.

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/f/;

use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  defined( $self->{FtpRoot} ) or die "You must specify FtpRoot";
  defined( $self->{Filename} ) or die "You must specify Filename";

  my $conf = ReadConfig();

  return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  # Note: HTTP::Cache::Transparent caches the file and only downloads
  # it if it has changed. This works since LWP interprets the
  # if-modified-since header and handles it locally.

  my $dir = $chd->{grabber_info};
  my $url = $self->{FtpRoot} . $dir . '/' . $self->{Filename};

  return( $url, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $xmltvid=$chd->{xmltvid};

  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) ) {
    f "Failed to parse";
    return 0;
  }

  # Find all paragraphs.
  my $ns = $doc->find( "//BroadcastDate_GMT" );

  if( $ns->size() == 0 ) {
    f "No BroadcastDates found";
    return 0;
  }

  foreach my $sched_date ($ns->get_nodelist) {
    my( $date ) = norm( $sched_date->findvalue( '@Day' ) );
    my $dt = create_dt( $date );

    my $ns2 = $sched_date->find('Emission');
    foreach my $emission ($ns2->get_nodelist) {
      my $start_time = $emission->findvalue( 'StartTimeGMT' );
      my $end_time = $emission->findvalue( 'EndTimeGMT' );

      my $start_dt = create_time( $dt, $start_time );
      my $end_dt = create_time( $dt, $end_time );

      if( $end_dt < $start_dt ) {
        $end_dt->add( days => 1 );
      }

      my $title2 = norm( $emission->findvalue( 'Title' ) );
      my $desc = norm( $emission->findvalue( 'Feature' ) );
      my $hd = norm( $emission->findvalue( 'HD' ) );
      my $image = norm( $emission->findvalue( 'ImageHD' ) );
      my $bc_type = norm( $emission->findvalue( 'BroadcastType' ) );
      my $sport = norm( $emission->findvalue( 'Sport' ) );

      my $title = ($title2 || ucfirst(lc($sport)));

      my $ce = {
        channel_id => $channel_id,
        start_time => $start_dt->ymd('-') . ' ' . $start_dt->hms(':'),
        end_time   => $end_dt->ymd('-') . ' ' . $end_dt->hms(':'),
        title => $title,
        description => $desc,
      };

      # Extra
      my $extra = {};
      $extra->{descriptions} = [];
      $extra->{qualifiers} = [];
      $extra->{images} = [];

      $ce->{quality} = "HDTV" if $hd eq "Yes";

      # Images
      if(defined($image) and $image ne "") {
        push @{$extra->{images}}, { url => $image, source => "Eurosport" };
      }

      if(defined($bc_type) and ($bc_type eq "DIREKT" or $bc_type eq "LIVE" or $bc_type eq "Jälkilähetys" or $bc_type eq "NA ŻYWO")) {
        $ce->{live} = 1;
        push @{$extra->{qualifiers}}, "live";
      } else {
        $ce->{live} = 0;
      }


      if(defined($bc_type) and ($bc_type eq "Repris" or $bc_type eq "Genudsendelse" or $bc_type eq "Replay" or $bc_type eq "Uusinta" or $bc_type eq "Reprise" or $bc_type eq "Powtórka")) {
        $ce->{new} = 0;
        push @{$extra->{qualifiers}}, "repeat";
      }


      # Sport
      if( defined($sport) and $sport ne "" ) {
  			my($program_type, $category ) = $ds->LookupCat( 'Eurosport', $sport );
  			AddCategory( $ce, "sports", $category );
  		}

      $ce->{extra} = $extra;

      $ds->AddProgramme( $ce );

    }
  }

  return 1;
}

sub create_dt {
  my( $text ) = @_;

  my($day, $month, $year ) = split( "/", $text );

  return DateTime->new( year => $year,
                        month => $month,
                        day => $day,
                        time_zone => "GMT" );
}

sub create_time {
  my( $dt, $time ) = @_;

  my $result = $dt->clone();

  my( $hour, $minute ) = split(':', $time );

  $result->set( hour => $hour,
                minute => $minute,
                );

  return $result;
}
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
