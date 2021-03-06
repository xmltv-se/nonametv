package NonameTV::Importer::KBSWorld;

use strict;
use warnings;

=pod

Importer for data from KBS World (http://kbsworld.kbs.co.kr/).
One file per week downloaded from their site.

Format is "Excel". It's mostly just XLSX so it's XML.

=cut

use Data::Dumper;
use DateTime;
use XML::LibXML;
use HTML::Laundry;

use NonameTV qw/AddCategory MyPost norm normUtf8 ParseXml/;
use NonameTV::Importer::BaseWeekly;
use NonameTV::Log qw/d progress w error f/;
use NonameTV::DataStore::Helper;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Asia/Seoul"  );
  $self->{datastorehelper} = $dsh;

  # Use augmenter, and get teh fabulous shit
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub first_day_of_week
{
  my ($year, $week) = @_;

  # Week 1 is defined as the one containing January 4:
  DateTime
    ->new( year => $year, month => 1, day => 4 )
    ->add( weeks => ($week - 1) )
    ->truncate( to => 'week' );
} # end first_day_of_week

sub FetchDataFromSite {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  my $datefirst = first_day_of_week( $year, $week )->add( days => 0 )->ymd('-'); # monday
  my $datelast  = first_day_of_week( $year, $week )->add( days => 6 )->ymd('-'); # sunday

  my ( $content, $code ) = MyPost( "http://211.233.93.86/schedule/down_schedule_.php", { 'wlang' => 'e', 'down_time_add' => '0', 'start_date' => $datefirst, 'end_date' => $datelast } );

  open(my $fh, '>', '/home/jnylen/content/contentcache/KBSWorld/notcleaned.html');
  print $fh $content;
  close $fh;

  my $l = HTML::Laundry->new();
  $l->add_acceptable_element(['tr', 'td', 'table', 'tbody'], { empty => 1 });
  $content =  $l->clean( $content );

  open($fh, '>', '/home/jnylen/content/contentcache/KBSWorld/cleaned.html');
  print $fh $content;
  close $fh;

  return ($content, undef);
}

sub ImportContent {
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  # Clean it up
  $$cref =~ s/<style>(.*)<\/style>//gi;
  $$cref =~ s/<col width="(.*?)">//g;
  $$cref =~ s/<br style='(.*?)'>/\n/g;
  $$cref =~ s/&nbsp;//gi;
  $$cref =~ s/&#39;/'/g;
  $$cref =~ s/&#65533;//g;
  $$cref =~ s/ & / &amp; /g;
  $$cref =~ s/<The Return of Superman>/The Return of Superman/gi;
  $$cref =~ s/<The Human Condition - Urban Farmer>/The Human Condition - Urban Farmer/gi;
  $$cref =~ s/<The Wonders of Korea>/The Wonders of Korea/gi;
  $$cref =~ s/<2015 K-POP WORLD FESTIVAL IN CHANGWON>/2015 K-POP WORLD FESTIVAL IN CHANGWON/gi;

  my $data = '<?xml version="1.0" encoding="utf-8"?>';
  $data .= $$cref;

  #open (MYFILE, '>>data.xml'); print MYFILE $data; close (MYFILE);

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($data); };

  if( not defined( $doc ) ) {
    f "Not well-formed xml";
    return 0;
  }

  my $ns = $doc->find( "//tbody/tr" );

  if( $ns->size() == 0 ) {
    f "No Rows found";
    return 0;
  }

  my $currdate = "x";

  # Programmes
  foreach my $row ($ns->get_nodelist) {


    my $date = $self->ParseDate(norm( $row->findvalue( "td[0]" ) ));
    my $time = norm( $row->findvalue( "td[1]" ) );
    my $duration = norm( $row->findvalue( "td[2]" ) );
    my $title = norm( $row->findvalue( "td[3]" ) );
    my $genre = norm( $row->findvalue( "td[5]" ) );
    my $episode = norm( $row->findvalue( "td[7]" ) );
    my $desc = norm( $row->findvalue( "td[8]" ) );

    if($date ne $currdate ) {
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("KBSWorld: Date is: $date");
    }

    my $ce = {
      channel_id => $chd->{id},
      title => norm($title),
      start_time => $time,
      description => norm($desc),
    };

    # Reason to defaulting to season 1 is that korean dramas 99% of all cases
    # only have 1 season. Variety shows goes by the prodnumber so hits up to episode 570.

    my $season = 1;

    # Try to fetch the season from the title
    if($title =~ /Season (\d+)/i and $title ne "Let's Go! Dream Team Season 2") {
        ($season) = ($title =~ /Season (\d+)/i);
        $ce->{title} =~ s/Season (\d+)//i;
        $ce->{title} = norm($ce->{title});
        $ce->{title} =~ s/-$//;
        $ce->{title} = norm($ce->{title});
    }

    if( $episode ne "" )
    {
      $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
    }

    # LIVE?
    if($title =~ /\[LIVE\]/i) {
        $ce->{title} =~ s/\[LIVE\]//i;
        $ce->{title} = norm($ce->{title});

        $ce->{live} = "1";
    } else {
        $ce->{live} = "0";
    }

    progress( "KBSWorld: $chd->{xmltvid}: $time - $ce->{title}" );
    $dsh->AddProgramme( $ce );

  }

  #$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  return undef if( ! $text );
print "ParseDate >$text<\n";

  my( $day , $month , $year, $monthname );

  if( $text =~ /^\d\d\/\d\d\/\d\d$/ ){
    ( $day , $month , $year ) = ( $text =~ /^(\d\d)\/(\d\d)\/(\d\d)$/ );
  } elsif( $text =~ /^(\d+)-(\S+)-(\d+)$/ ){ # Format: "30-Nov-10"
    ( $day , $monthname , $year ) = ( $text =~ /^(\d+)-(\S+)-(\d+)$/ );
    $month = MonthNumber( $monthname, "en" );
  } elsif( $text =~ /^\d\d\d\d\d\d\d\d$/ ) {
    ( $year, $month, $day ) = ( $text =~ /^(\d\d\d\d)(\d\d)(\d\d)$/ );
  } else {
    return undef;
  }

  $year += 2000 if $year lt 100;

  my $date = DateTime->new( year   => $year,
                            month  => $month,
                            day    => $day,
                            hour   => 0,
                            minute => 0,
                            second => 0,
                            nanosecond => 0,
                            time_zone => 'Europe/Paris',
  );

  return $date->ymd("-");
}

1;
