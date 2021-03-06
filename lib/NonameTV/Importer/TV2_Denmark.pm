package NonameTV::Importer::TV2_Denmark;

use strict;
use warnings;
use Try::Tiny;

=pod

Importer for data from TV2 Denmark,
(You should change the filestore at the bottom)

=cut

use DateTime;
use XML::LibXML;
use Roman;
use Data::Dumper;

use NonameTV qw/MyGet norm ParseDescCatSwe AddCategory FixProgrammeData FixSubtitle CleanSubtitle/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    $self->{MinWeeks} = 0;
    $self->{MaxWeeks} = 3;

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Copenhagen" );
    #$dsh->{DETECT_SEGMENTS} = 1;
    $self->{datastorehelper} = $dsh;

    # use augment
    $self->{datastore}->{augment} = 1;


    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);

  my ( $year , $week ) = ( $date =~ /(\d+)-(\d+)$/ );
  my ($yearweek) = sprintf( "%04d-%02d", $year, $week );

  my $url = $self->{UrlRoot} . '?category=all&day=all&format=xml&how=xml&content=all&update=&updateswitch=0'
    . '&week=' . $yearweek
    . '&channel=' . $chd->{grabber_info};

  return( $url, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( $date2 ) = ($batch_id =~ /_(.*)$/);
  my( $xmltvid ) = ($batch_id =~ /(.*)_/);
  my $currdate = "x";

  my $xml = XML::LibXML->new;
  my $doc;

  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse: $@" );
    return 0;
  }

  # XPC
  my $xpc = XML::LibXML::XPathContext->new( );
  my $ns = $xpc->findnodes( './/programs/program', $doc );
  if( $ns->size() == 0 ) {
    error ("TV2 Denmark: $chd->{xmltvid}: No data found");
    return 0;
  }

  # Sort by start
  sub by_start {
    return $xpc->findvalue('time', $a) cmp $xpc->findvalue('time', $b);
  }

  foreach my $pgm (sort by_start $ns->get_nodelist) {
    $xpc->setContextNode( $pgm );
    my $start;

    try {
      $start  = ParseDateTime($pgm->findvalue( 'time' ));
    }
    catch { print("error: $_"); next; };

    next if(!defined($start));

  	my $date  = $start->ymd("-");
    my $title = $pgm->findvalue( 'title' );
    $title =~ s/\((\d+):(\d+)\)//g if $title;
    $title =~ s/\((\d+)\)//g if $title;
    $title =~ s/, direkte$//g if $title;
    $title =~ s/\(m\)//g if $title;

    my $genre = $pgm->findvalue( 'category' );
    my $cast  = $pgm->findvalue( 'cast' );
    my $year  = $pgm->findvalue( 'year' );
    my $episode  = $pgm->findvalue( 'episode' );
    my ( $original_title , $season ) = ( $pgm->findvalue( 'original_title' ) =~ /^(.*)- .r (\d+)/ );

    if(!defined($original_title)) {
        $original_title = norm($pgm->findvalue( 'original_title' ));
    }

    ## Batch
  	if($date ne $currdate ) {
  		if( $currdate ne "x" ) {
  			#$ds->EndBatch( 1 );
  		}

  		#my $batchid = $chd->{xmltvid} . "_" . $date;
  		#$dsh->StartBatch( $batchid );
  		#$dsh->StartDate( $date, "00:00" );
  		$currdate = $date;

  		progress("TV2: Date is: $date");
  	}

    my $ce = {
        channel_id => $chd->{id},
        title => norm(FixSubtitle($title)),
        start_time => $start,
    };

    # Extra
    my $extra = {};
    $extra->{descriptions} = [];
    $extra->{qualifiers} = [];
    $extra->{images} = [];

    if(defined($pgm->findvalue( 'original_title' )) and $genre ne "Film"){
      # Season
  	  if(defined($episode) and $episode ne "" and defined($season) and $season ne "") {
  	        $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
  	  }
  	}

    # Sometimes in title
  	if($ce->{title} =~ /- .r (\d+)$/) {
  	    my ( $season2 ) = ( $ce->{title} =~ /- .r (\d+)/ );

  	    $ce->{title} =~ s/- .r (\d+)$//i;
  	    $ce->{title} = norm($ce->{title});

        if(defined($episode) and $episode ne "" and defined($season2) and $season2 ne "") {
            $ce->{episode} = sprintf( "%d . %d .", $season2-1, $episode-1 );
        }
  	}

    # Desc
    if(defined($pgm->findvalue( 'description' )) and norm($pgm->findvalue( 'description' )) ne "") {
    	$ce->{description} = norm($pgm->findvalue( 'description' ));
    }

    # Subtitle
    if(defined($pgm->findvalue( 'original_episode_title' ))) {
    	if(norm($pgm->findvalue( 'original_episode_title' )) ne "") {
    	  my $subtitle = norm($pgm->findvalue( 'original_episode_title' ));
        $ce->{subtitle} = norm(CleanSubtitle(FixSubtitle($subtitle)));
        $ce->{subtitle} =~ s/\:(\d+)\)$/\)/i;
      }
    }

    # Genre
    if( $genre ){
  			my($program_type, $category ) = $ds->LookupCat( 'TV2Denmark', $genre );
  			AddCategory( $ce, $program_type, $category );
  	}

    # Year
  	if( defined( $year ) and ($year =~ /(\d\d\d\d)/) ) {
      if(!defined($ce->{episode}) and defined($episode) and $episode ne "") {
        $ce->{episode} = sprintf( "%d . %d .", $1-1, $episode-1 );
      }
  		$ce->{production_date} = "$1-01-01";
  	}

    ### Actors and Directors
    my( $producer ) = (norm($cast) =~ /Producere:\s*(.*)/i );
	  if( $producer ) {
	     $cast =~ s/Producere:\s*(.*)//i;
		  $ce->{producers} = norm(parse_person_list( $producer ));
	  }
    my( $dumperinoerino, $creators ) = (norm($cast) =~ /(Serieskabere|Serieskaber):\s*(.*)$/i );
	  if( $creators ) {
	     $cast =~ s/(Serieskabere|Serieskaber):\s*(.*)//i;
		  $ce->{producers} = norm(parse_person_list( $creators ));
	  }

    my( $writers ) = (norm($cast) =~ /Manuskript:\s*(.*)\.$/ );
    if( $writers ) {
        $cast =~ s/Manuskript:\s*(.*)//i;
        $writers =~ s/, baseret(.*)//i;
        $writers =~ s/\((.*)//;
        $ce->{writers} = norm(parse_person_list( $writers ));
    }

    my( $directors ) = (norm($cast) =~ /Instruktion:\s*(.*)/i );
	  if( $directors ) {
	     $cast =~ s/Instruktion:\s*(.*)//i;
		   $ce->{directors} = norm(parse_person_list( $directors ));
	  }

    my( $directorandwriter ) = (norm($cast) =~ /Instruktion\s+og\s+manuskript:\s*(.*)/i );
	  if( $directorandwriter ) {
	    $cast =~ s/Instruktion\s+og\s+manuskript:\s*(.*)//i;
		  $ce->{directors} = norm(parse_person_list( $directorandwriter ));
		  $ce->{writers} = norm(parse_person_list( $directorandwriter ));
	  }

    my( $actors1 ) = (norm($cast) =~ /Desuden\s+medvirker:\s*(.*)$/i );
    if( $actors1 ) {
        $cast =~ s/Desuden\s+medvirker:\s*(.*)//i;
        #$ce->{actors} = norm(parse_person_list( $actors1 )); # Probably want to include these in actors later on they have a DOT as a ,
    }

    my( $programkoder ) = (norm($cast) =~ /Programkoder:\s*(.*)$/i );
    if( $programkoder ) {
        $cast =~ s/Programkoder:\s*(.*)//i;
    }

    my( $actors2 ) = (norm($cast) =~ /Vært:\s*(.*)\.$/ );
    if( $actors2 ) {
        $cast =~ s/Vært:\s*(.*)//i;
        $ce->{presenters} = norm(parse_person_list( $actors2 ));
    }

    my( $actors3 ) = (norm($cast) =~ /Medvirkende:\s*(.*)\.$/ );
    if( $actors3 ) {

        $ce->{actors} = norm(parse_person_list( $actors3 ));
    }

    ### End

    if( !defined($ce->{episode}) and defined($episode) and $episode ne "" )
    {
      $ce->{episode} = sprintf( ". %d .", $episode-1 );
    }

    $ce->{original_title} = FixSubtitle(norm($original_title)) if defined($original_title) and $ce->{title} ne norm($original_title) and norm($original_title) ne "";

    ## Images
    my $images = $pgm->find( "./images/image" );

    # Each
    foreach my $ic ($images->get_nodelist)
    {
        push @{$extra->{images}}, { url => $ic->findvalue( 'url' ), title => $ic->findvalue( 'caption' ), copyright => $ic->findvalue( 'byline' ), source => "TV2 Denmark" };
    }

    # Rerun
    my $new  = $pgm->findvalue( 'new' );
    if($new){
      $ce->{new} = 1;
      push @{$extra->{qualifiers}}, "new";
    } else {
      $ce->{new} = 0;
      push @{$extra->{qualifiers}}, "repeat";
    }

    $ce->{extra} = $extra;

    # End of transmission
    if($ce->{title} eq "Godnat") {
      $ce->{title} = "end-of-transmission";
    }

    # Subtitles
    $ce->{subtitle} =~ s|\s+del\s+(\d+)$| ($1)| if(defined($ce->{subtitle}));

    progress( "TV2: $chd->{xmltvid}: $start - ".norm($ce->{title}) );

    delete $ce->{directors} if defined $ce->{directors} and $ce->{directors} =~ /^\(/; # Failure to parse
    $ds->AddProgramme( $ce );
  }

  #$ds->EndBatch( 1 );

  # Success
  return 1;
}


sub parse_person_list
{
  my( $str ) = @_;

  $str =~ s/\bog\b/,/;
  $str =~ s/ og / , /;
  $str =~ s/\bsamt\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  my @pers;
  foreach my $p (@persons)
  {
    my ($role, $dummperinerno, $actor) = ($p =~ /(.*)(:|;)(.*)/i);

    if(defined($actor)) {
        # Probably a actorname in a different order
        if(norm($actor) =~ /^(Dr\.|Professor)/i) {
            my $role1 = $role;
            $role = $actor;
            $actor = $role1;
        }
        $actor =~ s/\.$//i;
        $actor =~ s/^\.//i;
        $role =~ s/^\.//i;
        $role =~ s/\.$//i;

        my $actorandrole = norm($actor) . " (".norm($role).")";
        push @pers, $actorandrole;
    } else {
        $p =~ s/\.$//i;
        $p =~ s/^\.//i;
        push @pers, norm($p);
    }
  }

  #print Dumper(@pers);

  return join( ";", grep( /\S/, @pers ) );
}

# The start and end-times are in the format 2007-12-31T01:00:00
# and are expressed in the local timezone.
sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) =
      ($str =~ /^(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    second => $second,
    time_zone => "Europe/Copenhagen"
  );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;
