package NonameTV::Importer::NovaTV;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

use POSIX;
use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  # use augment
  #$self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( ( $file !~ /program/i and $file !~ /izmjena/i ) and $file !~ /\s*\.\s*doc$/ ) {
    progress( "NovaTV: $xmltvid: Skipping unknown file $file" );
    return;
  }

  progress( "NovaTV: $xmltvid: Processing $file" );

  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "NovaTV $file: Failed to parse" );
    return;
  }

  my @nodes = $doc->findnodes( '//span[@style="text-transform:uppercase"]/text()' );
  foreach my $node (@nodes) {
    my $str = $node->getData();
    $node->setData( uc( $str ) );
  }

  # Find all paragraphs.
  my $ns = $doc->find( "//div" );

  if( $ns->size() == 0 ) {
    error( "NovaTV $file: No divs found." ) ;
    return;
  }

  my $currdate = undef;
  my $nowyear = DateTime->today->year();
  my $date = undef;
  my @ces;
  my $targetshow;
  my $description;
  my $subtitle;
  my $directors;
  my $actors;
  my ( $originaltitle, $country, $productionyear, $genre );

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

#print ">$text\n";

    if( $text eq "" ) {
      # blank line
    }
    elsif( $text =~ /^PROGRAM NOVE TV za/i ) {
      #progress("NovaTV: $xmltvid: OK, this is the file with the schedules: $file");
    }
    elsif( isDate( $text ) ) { # the line with the date in format 'MONDAY 12.4.2017'

      $date = ParseDate( $text , $nowyear );

      if( defined $date ) {

        if( defined $currdate ){
          # save last day if we have it in memory
          FlushDayData( $chd, $dsh , @ces );
          $dsh->EndBatch( 1 )
        }

        my $batch_id = "${xmltvid}_" . $date->ymd();
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date->ymd("-") , "05:55" );
        $currdate = $date;

        progress("NovaTV: $xmltvid: Date is " . $date->ymd());
      }

      # empty last day array
      @ces = ();
      undef $targetshow;
      undef $description;
      undef $subtitle;
      undef $directors;
      undef $actors;
      undef $originaltitle;
      undef $country;
      undef $productionyear;
      undef $genre;
    }
    elsif( isShow( $text ) ) { # the line with the show in format '19.30 Show title, genre'

      my( $starttime, $title, $genre ) = ParseShow( $text , $date );

      $title =~ s/\((\d+)\)//;
      $title =~ s/(\d+)\-(\d+)\/(\d+)//;
      $title =~ s/(\d+)\-//;
      $title =~ s/(\d+)\/(\d+)//;
      $title =~ s/(\d+)\/ (\d+)//;

      my $ce = {
        channel_id   => $chd->{id},
      	start_time => $starttime->hms(":"),
      	title => norm($title),
      };

      # Subtitle is sometimes in title
      if( my ( $subtitle2 ) = (norm($title) =~ /(\(.*?)\)$/ ) )
      {
        $ce->{subtitle} = norm($subtitle2);
        $ce->{title} =~ s/(\(.*?)\)$//;
        $ce->{title} = norm($ce->{title});
      }

      # Genre is sometimes in title
      if($ce->{title} =~ / serija$/i) {
        $ce->{program_type} = "series";
        $ce->{title} =~ s/ serija$//;
      }

      # Genre
      if( $genre ){
        $genre =~ s/\((\d+)\)//;
        $genre =~ s/(\d+)\-//;
        $genre =~ s/(\d+)\/(\d+)//;
        $genre =~ s/(\d+)\/ (\d+)//;

        my($program_type, $category ) = $ds->LookupCat( 'NovaTV', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      # add the programme to the array
      # as we have to add description later
      push( @ces , $ce );

    }
    elsif( isCroUcase( $text ) ) { # the line with description title in format 'ALL IN CAPS'

      # if we have something in the description buffer
      # then this is for the last targetshow
      if( $targetshow and $description ){
        my ($episode, $season);
        my @sentences = (split_text( $description ), "");

        for( my $i2=0; $i2<scalar(@sentences); $i2++ )
        {
          if( ( $season, $episode ) = ($sentences[$i2] =~ /^(\d+)\. sez\., (\d+)\. ep\./ ) )
          {
            $targetshow->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
            $sentences[$i2] = "";
          } elsif( ( $episode ) = ($sentences[$i2] =~ /^(\d+)\. ep\./ ) )
          {
            $targetshow->{episode} = sprintf( ". %d .", $episode-1 );
            $sentences[$i2] = "";
          }

        }

        $targetshow->{description} = norm(join_text( @sentences ));

        $targetshow->{subtitle} = $subtitle if defined $subtitle;
        $targetshow->{directors} = $directors if defined $directors;
        $targetshow->{actors} = $actors if defined $actors;

        if(defined($originaltitle)) {
          $targetshow->{original_title} = norm($originaltitle) if $originaltitle !~ /,/;
          $targetshow->{production_date} = $productionyear."-01-01";
          #$targetshow->{program_type} = "movie";

          if(defined($directors)) {
            $targetshow->{program_type} = "movie";
          }
        }

        undef $description;
        undef $subtitle;
        undef $directors;
        undef $actors;
        undef $originaltitle;
        undef $country;
        undef $productionyear;
        undef $genre;
      }

      my $utext = utf8ucase( $text );

      # find if we have the show with that name
      foreach my $element (@ces) {

        my $utitle = utf8ucase( $element->{title} );

        if( $utext eq $utitle ){
          $targetshow = $element;
          last;
        }
      }
    }
    else {

      # if we know the target show then this is the description
      if( $targetshow ){

        # subtitle if present in the first description line
        if( $text =~ /^\(.*\)/ ){
          if( ( $originaltitle, $country, $productionyear, $genre ) = ($text =~ /^\((.*?)\), (.*?), (\d\d\d\d)., (.*?)/ ) )
          {

          } else {
            $subtitle = $text;
          }
        }

        # subtitle if present in one text line
        elsif( $text =~ s/^Redatelj: // ){
          $directors = $text;
          print("DIRECTORS: $text\n");
        }

        # actor if present in the one text line
        elsif( $text =~ s/^Glume: // ){
          $actors = $text;
        }

        else {
          $description .= $text;
        }

      } else {
        #error( "Ignoring $text" );
      }
    }
  }
  # save last day if we have it in memory
  FlushDayData( $chd, $dsh , @ces );

  $dsh->EndBatch( 1 );

  return;
}

sub FlushDayData {
  my ( $chd, $dsh , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {
        progress("NovaTV: $chd->{xmltvid}: $element->{start_time} - $element->{title}");
        $dsh->AddProgramme( $element );
      }
    }
}

sub isDate {
  my ( $text ) = @_;

  if(
    ( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja|nejelja)\,*\s*\d+\s*\.\s*\d+\s*\.\s*\d+\s*\.\s*$/i )
    or
    ( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja|nejelja)\,*\s*\d+\s*\.\s*\d+\s*\.\s*$/i )
    or
    ( $text =~ /^\d+\s*\.\s*\d+\s*\.\d+\s*\.\s*(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja|nejelja)$/i )
  ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text, $year ) = @_;

  my( $day, $month, $yr );
  if( $text =~ /\d+\s*\.\s*\d+\s*\.\s*\d+\s*\.\s*/ ){
    ( $day, $month, $yr ) = ($text =~ /(\d+)\s*\.\s*(\d+)\s*\.\s*(\d+)/);
  } elsif( $text =~ /\d+\s*\.\s*\d+\s*\.\s*/ ){
    ( $day, $month ) = ($text =~ /(\d+)\s*\.\s*(\d+)/);
  } elsif( $text =~ /\d+\s*\.\s*\d+\s*\.\d+\s*\.\s*\S+/ ){
    ( $day, $month, $yr ) = ($text =~ /(\d+)\s*\.\s*(\d+)\s*\.(\d+)\s*\.\s*\S+/);
  }

  $year = $yr if $yr;
  $year+= 2000 if $year< 100;

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
  );

  return $dt;
}

sub isShow {
  my ( $text ) = @_;

  if(
    ( $text =~ /^\d+\.\d+\s+/ )
    or
    ( $text =~ /^\d+\:\d+\s+/ )
  ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text, $date ) = @_;
  my( $title, $genre );

  my( $hour, $min, $string );

  if( $text =~ /^\d+\.\d+\s*/ ){
    ( $hour, $min, $string ) = ($text =~ /(\d+)\.(\d+)\s*(.*)/);
  } elsif( $text =~ /^\d+\:\d+\s*/ ){
    ( $hour, $min, $string ) = ($text =~ /(\d+)\:(\d+)\s*(.*)/);
  }

  if( $string =~ /,/ ){
    ( $title, $genre ) = $string =~ m/(.*, )(.*)$/;
    if( $title ){
      $title =~ s/, $//;
    }
  }
  else
  {
    $title = $string;
  }

  my $sdt = $date->clone()->add( hours => $hour , minutes => $min );

  return( $sdt , $title , $genre );
}

sub utf8ucase {
  my( $str ) = @_;
  my $newstr = $str;

  $newstr =~ s/\xC4\x8D/\xC4\x8C/;	# tvrdo c
  $newstr =~ s/\xC4\x87/\xC4\x86/;	# meko c
  $newstr =~ s/\xC4\x91/\xC4\x90/;      # d
  $newstr =~ s/\xC5\xA1/\xC5\xA0/;      # s
  $newstr =~ s/\xC5\xBE/\xC5\xBD/;      # z

  $newstr = uc($newstr);

  return( $newstr );
}

sub isCroUcase {
  my( $str ) = @_;

  if( $str =~ /[[:lower:]]/ ){
    return 0;
  }

  return 1;
}

sub split_text
{
  my( $t ) = @_;

  return () if not defined( $t );

  # Remove any trailing whitespace
  $t =~ s/\s*$//;

  # Replace strange dots.
  $t =~ tr/\x2e/./;

  # We might have introduced some errors above. Fix them.
  $t =~ s/([\?\!])\./$1/g;

  # Replace ... with ::.
  $t =~ s/\.{3,}/::./g;

  # Lines ending with a comma is not the end of a sentence
  #  $t =~ s/,\s*\n+\s*/, /g;

  # newlines have already been removed by norm()
  # Replace newlines followed by a capital with space and make sure that there
  # is a dot to mark the end of the sentence.
  #  $t =~ s/([\!\?])\s*\n+\s*([A-Z���])/$1 $2/g;
  #  $t =~ s/\.*\s*\n+\s*([A-Z���])/. $1/g;

  # Turn all whitespace into pure spaces and compress multiple whitespace
  # to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Mark sentences ending with '.', '!', or '?' for split, but preserve the
  # ".!?".
  $t =~ s/([\.\!\?])\s+([\(A-Z���])/$1;;$2/g;

  my @sent = grep( /\S\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    # Make sure that the last sentence ends in a proper way.
    $sent[-1] =~ s/\s+$//;
    $sent[-1] .= "."
    unless $sent[-1] =~ /[\.\!\?]$/;
  }

  return @sent;
}

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( " ", grep( /\S/, @_ ) );
  $t =~ s/::/../g;

  return $t;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
