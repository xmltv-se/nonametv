package NonameTV::Importer::ProSieben;

use strict;
use warnings;

=pod

Importer for data from ProSiebenSat.1 Media AG.
One file per channel and week downloaded from their site.

AGB:                  http://presse.prosieben.de/service/agb
format description:   http://struppi.tv/
VG Media EPG License: http://www.vgmedia.de/de/lizenzen/epg.html

=cut

use Data::Dumper;
use DateTime;
use XML::LibXML::XPathContext;

use NonameTV qw/AddCategory norm ParseXml/;
use NonameTV::Importer::BaseFile;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/d progress w error f/;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{KeepDesc} = 0;

  if (!defined $self->{HaveVGMediaLicense}) {
    warn( 'Extended event information (texts, pictures, audio and video sequences) is subject to a license sold by VG Media. Set HaveVGMediaLicense to yes or no.' );
    $self->{HaveVGMediaLicense} = 'no';
  }
  if ($self->{HaveVGMediaLicense} eq 'yes') {
    $self->{KeepDesc} = 1;
  }

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Stockholm" );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $cref=`cat \"$file\"`;

  $cref =~ s|
  ||g;

  $cref =~ s| xmlns:ns='http://struppi.tv/xsd/'||;
  $cref =~ s| xmlns:xsd='http://www.w3.org/2001/XMLSchema'||;

  $cref =~ s| generierungsdatum='[^']+'| generierungsdatum=''|;


  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($cref); };

  if (not defined ($doc)) {
    f ("$file: Failed to parse.");
    return 0;
  }

  my $xpc = XML::LibXML::XPathContext->new( );
  $xpc->registerNs( s => 'http://struppi.tv/xsd/' );

  my $programs = $xpc->findnodes( '//s:sendung', $doc );
  if( $programs->size() == 0 ) {
    f ("$file: No data found");
    return 0;
  }

  sub by_start {
    return $xpc->findvalue('s:termin/@start', $a) cmp $xpc->findvalue('s:termin/@start', $b);
  }

  my $currdate = "x";

  ## Fix for data falling off when on a new week (same date, removing old programmes for that date)
  my ($week, $year) = ($file =~ /PW(\d+)_(\d\d\d\d)/);

  if(!defined $year) {
      error( "$file: $chd->{xmltvid}: Failure to get year from filename" ) ;
      return;
  }

  my $batchid = $chd->{xmltvid} . "_" . $year . "-".$week;

  $dsh->StartBatch( $batchid , $chd->{id} );

  ## END

  foreach my $program (sort by_start $programs->get_nodelist) {
        $xpc->setContextNode( $program );
        my $start = $self->parseTimestamp( $xpc->findvalue( 's:termin/@start' ) );
        my $end = $self->parseTimestamp( $xpc->findvalue( 's:termin/@ende' ) );
        my $ce = ();
        $ce->{channel_id} = $chd->{id};

        $ce->{start_time} = $start->ymd("-") . " " . $start->hms(":");
        $ce->{end_time} = $end->ymd("-") . " " . $end->hms(":");

        if($start->ymd("-") ne $currdate ) {
          #$dsh->StartDate( $start->ymd("-") , "06:00" );
          $currdate = $start->ymd("-");
          progress("ProSieben: $chd->{xmltvid}: Date is: ".$start->ymd("-"));
        }

        $ce->{title} = norm($xpc->findvalue( 's:titel/@termintitel' ));

        my $title_org;
        $title_org = $xpc->findvalue( 's:titel/s:alias[@titelart="originaltitel"]/@aliastitel' );
        $ce->{original_title} = norm($title_org) if $ce->{title} ne norm($title_org) and norm($title_org) ne "";

        my $subtitle = $xpc->findvalue( 's:titel/s:alias[@titelart="originaluntertitel"]/@aliastitel' );
        if( !$subtitle ){
          $subtitle = $xpc->findvalue( 's:titel/s:alias[@titelart="untertitel"]/@aliastitel' );
        }
        if( $subtitle ){
          my $staffel;
          my $folge;
          if( ( $staffel, $folge ) = ($subtitle =~ m|^Staffel (\d+) Folge (\d+)$| ) ){
            $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
          } elsif( ( $folge ) = ($subtitle =~ m|^Folge (\d+)$| ) ){
            $ce->{episode} = '. ' . ($folge - 1) . ' .';
          } else {
            # unify style of two or more episodes in one programme
            $subtitle =~ s|\s*/\s*| / |g;
            # unify style of story arc
            $subtitle =~ s|[ ,-]+Teil (\d)+$| \($1\)|;
            $subtitle =~ s|[ ,-]+Part (\d)+$| \($1\)|;
            $ce->{subtitle} = norm( $subtitle );
          }
        }

        my $production_year = $xpc->findvalue( 's:produktion/s:produktionszeitraum/s:jahr/@von' );
        if( $production_year =~ m|^\d{4}$| ){
          $ce->{production_date} = $production_year . '-01-01';
        }

        my $genre = $xpc->findvalue( 's:infos/s:klassifizierung/@hauptgenre' );
        if( $genre ){
          my ( $program_type, $category ) = $self->{datastore}->LookupCat( "ProSieben_genre", $genre );
          AddCategory( $ce, $program_type, $category );
        }
        $genre = $xpc->findvalue( 's:infos/s:klassifizierung/@formatgruppe' );
        if( $genre ){
          my ( $program_type, $category ) = $self->{datastore}->LookupCat( "ProSieben_main", $genre );
          AddCategory( $ce, $program_type, $category );
        }

        #Descr
        my $desc = $xpc->findvalue( 's:text[@textart="Kurztext"]' );
        if( ! $desc) {
            $desc = $xpc->findvalue( 's:text[@textart="Beschreibung"]' );
        }
        if( ! $desc) {
            $desc = $xpc->findvalue( 's:text[@textart="Allgemein"]' );
        }

        ParseCredits( $ce, 'actors',     $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Darsteller"]/s:mitwirkendentyp/s:person/s:name' );
        ParseCredits( $ce, 'directors',  $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Regie"]/s:mitwirkendentyp/s:person/s:name' );
        ParseCredits( $ce, 'producers',  $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Produzent"]/s:mitwirkendentyp/s:person/s:name' );
        ParseCredits( $ce, 'writers',    $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Autor"]/s:mitwirkendentyp/s:person/s:name' );
        ParseCredits( $ce, 'writers',    $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Drehbuch"]/s:mitwirkendentyp/s:person/s:name' );
        ParseCredits( $ce, 'presenters', $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Moderation"]/s:mitwirkendentyp/s:person/s:name' );
        ParseCredits( $ce, 'guests',     $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Gast"]/s:mitwirkendentyp/s:person/s:name' );

        #print Dumper($ce);

        $ce->{description} = norm($desc) if $self->{KeepDesc} and $desc and $desc ne "";

        $ds->AddProgrammeRaw( $ce );

        progress("ProSieben: $chd->{xmltvid}: ".$ce->{start_time}." - ".$ce->{title});
  }

  $dsh->EndBatch( 1 );

  return 1;
}

sub parseTimestamp( $ ){
  my $self = shift;
  my ($timestamp, $date) = @_;

  #print ("date: $timestamp\n");

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($year, $month, $day, $hour, $minute, $second, $offset) = ($timestamp =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})([+-]\d{2}:\d{2}|)$/);
    if( !defined( $year )|| !defined( $hour ) ){
      w( "could not parse timestamp: $timestamp" );
    }
    if( $offset ){
      $offset =~ s|:||;
    } else {
      $offset = 'Europe/Berlin';
    }
    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      second    => $second,
      time_zone => $offset
    );
    $dt->set_time_zone( 'UTC' );

    return( $dt );

  } else {
    return undef;
  }
}

# call with sce, target field, sendung element, xpath expression
# e.g. ParseCredits( \%sce, 'actors', $sc, './programm//besetzung/darsteller' );
# e.g. ParseCredits( \%sce, 'writers', $sc, './programm//stab/person[funktion=buch]' );
sub ParseCredits
{
  my( $ce, $field, $root, $xpath) = @_;

  my @people;
  my $nodes = $root->findnodes( $xpath );
  foreach my $node ($nodes->get_nodelist) {
    my $person = $node->findvalue( '@vorname' )." ".$node->findvalue( '@name' );

    if( norm($person) ne '' ) {
      push( @people, split( '&', $person ) );
    }
  }

  foreach (@people) {
    $_ = norm( $_ );
  }

  AddCredits( $ce, $field, @people );
}


sub AddCredits
{
  my( $ce, $field, @people) = @_;

  if( scalar( @people ) > 0 ) {
    if( defined( $ce->{$field} ) ) {
      $ce->{$field} = join( ', ', $ce->{$field}, @people );
    } else {
      $ce->{$field} = join( ', ', @people );
    }
  }
}

1;