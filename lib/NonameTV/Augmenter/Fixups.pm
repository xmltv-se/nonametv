package NonameTV::Augmenter::Fixups;

use strict;
use warnings;

use Data::Dumper;
use Encode;
use utf8;

use NonameTV qw/norm/;
use NonameTV::Augmenter::Base;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/w d/;

use base 'NonameTV::Augmenter::Base';


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

#    print Dumper( $self );

#    defined( $self->{Language} ) or die "You must specify Language";

    # need config for main content cache path
    my $conf = ReadConfig( );

    return $self;
}

sub CopyProgramWithoutTransmission( $$ ){
  my( $resultref, $ce ) = @_;

  $resultref->{title} = $ce->{title};
  $resultref->{subtitle} = $ce->{subtitle};
  $resultref->{description} = $ce->{description};
  $resultref->{actors} = $ce->{actors};
  $resultref->{directors} = $ce->{directors};
  $resultref->{writers} = $ce->{writers};
  $resultref->{adapters} = $ce->{adapters};
  $resultref->{producers} = $ce->{producers};
  $resultref->{presenters} = $ce->{presenters};
  $resultref->{commentators} = $ce->{commentators};
  $resultref->{guests} = $ce->{guests};
  $resultref->{star_rating} = $ce->{star_rating};
  $resultref->{category} = $ce->{category};
  $resultref->{program_type} = $ce->{program_type};
  $resultref->{episode} = $ce->{episode};
  $resultref->{production_date} = $ce->{production_date};
  $resultref->{rating} = $ce->{rating};
}

sub AugmentProgram( $$$ ){
  my( $self, $ceref, $ruleref ) = @_;

  # empty hash to get all attributes to change
  my $resultref = {};
  # result string, empty/false for success, message/true for failure
  my $result = '';

  if( $ruleref->{matchby} eq 'setcategory' ) {
    $resultref->{'category'} = $ruleref->{remoteref};
  }elsif( $ruleref->{matchby} eq 'guestsubtitle' ) {
    if(defined($ceref->{guests}) and ($ceref->{guests} ne "")) {
        $resultref->{'subtitle'} = $ceref->{guests};
    } else {
        w("Fixups::guestsubtitle - Nothing provided in guests.")
    }
  }elsif( $ruleref->{matchby} eq 'setprogram_type' ) {
    $resultref->{'program_type'} = $ruleref->{remoteref};
  }elsif( $ruleref->{matchby} eq 'setprogram_type_no_ep' ) {
    # Sets proram type as remoteref and remove episode
    $resultref->{'program_type'} = $ruleref->{remoteref};
    $resultref->{'episode'}      = undef;
  }elsif( $ruleref->{matchby} eq 'setsubtitle' ) {
    $resultref->{'subtitle'} = $ruleref->{remoteref};
  }elsif( $ruleref->{matchby} eq 'splittitle' ) {
    my( $title, $episodetitle )=( $ceref->{title} =~ m|$ruleref->{title}| );
    $resultref->{'title'} = $title;
    $resultref->{'subtitle'} = $episodetitle;
    if( $ceref->{'subtitle'} ) {
      $resultref->{'subtitle'} .= " - " . $ceref->{'subtitle'};
    }
    $resultref->{program_type} = 'series';
  }elsif( $ruleref->{matchby} eq 'splittitlereverse' ) {
    my( $episodetitle, $title )=( $ceref->{title} =~ m|$ruleref->{title}| );
    $resultref->{'title'} = $title;
    $resultref->{'subtitle'} = $episodetitle;
    if( $ceref->{'subtitle'} ) {
      $resultref->{'description'} = $ceref->{'subtitle'};
      if( $ceref->{'description'} ){
        $resultref->{'description'} .= "\n" . $ceref->{'description'};
      }
    }
    $resultref->{program_type} = 'series';
  }elsif( $ruleref->{matchby} eq 'setseason' ) {
  	# Used like:
  	# title: Jersey Shoe 2
  	# remoteref: Jersey Shoe|2
    if(defined($ceref->{episode})) {
      my( $episode )=( $ceref->{episode} =~ m|\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*| );
    	my( $title, $season ) = split( /\|/, $ruleref->{remoteref} );
    	$resultref->{'title'} = $title;
    	$resultref->{episode} = ($season - 1) . ' . ' . $episode . ' .';
    }
  }elsif( $ruleref->{matchby} eq 'setseasonminuseps' ) {
  	# Used like:
  	# title: Jersey Shoe 2
  	# remoteref: Jersey Shoe|2|141
    # Removes 141 episodes from the main one
    if(defined($ceref->{episode})) {
      my( $episode )=( $ceref->{episode} =~ m|\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*| );
    	my( $title, $season, $minusepisodes ) = split( /\|/, $ruleref->{remoteref} );
    	$resultref->{'title'} = $title;
    	$resultref->{episode} = ($season - 1) . ' . ' . ($episode - $minusepisodes) . ' .';
    }
  }elsif( $ruleref->{matchby} eq 'splittitlereverse_type' ) {
  	# Used like:
  	# real title: Dox 5 år: Buss 174
    # title: ^.*(Dox 5 år):\s+(.*)$
  	# remoteref: movie

    my( $title, $episodetitle )=( $ceref->{title} =~ m|$ruleref->{title}| );
    $resultref->{'title'} = $episodetitle;
    $resultref->{program_type} = $ruleref->{remoteref};
  }elsif( $ruleref->{matchby} eq 'splitguesttitle' ) {
    # split the name of the guest from the title and put it into subtitle and guest
    my( $title, $episodetitle )=( $ceref->{title} =~ m|$ruleref->{title}| );
    $resultref->{'title'} = $title;
    $resultref->{'subtitle'} = $episodetitle;
    $resultref->{'guests'} = $episodetitle;
  }elsif( $ruleref->{matchby} eq 'splitstartitle' ) {
    # split the name of the starring actor from the title and put it into actors
    # set type to movie if unknown
    my( $actor, $title )=( $ceref->{title} =~ m|$ruleref->{title}| );
    $resultref->{'title'} = $title;
    $resultref->{'actors'} = join( ', ', $actor, $ceref->{actors} );
    if( $ceref->{program_type} eq '' ) {
      $resultref->{program_type} = 'movie';
    }
  }elsif( $ruleref->{matchby} eq 'replacetitle' ) {
    $resultref->{'title'} = $ruleref->{remoteref};
  }elsif( $ruleref->{matchby} eq 'replacetitleundef' ) {
    $resultref->{'title'} = $ruleref->{remoteref};
    $resultref->{$ruleref->{otherfield}} = undef if defined($ruleref->{otherfield}) and $ruleref->{otherfield} ne "";
  }elsif( $ruleref->{matchby} eq 'subtitle_to_title_type' && $ceref->{'subtitle'} && $ceref->{'subtitle'} ne "") {
    # Sets subtitle as the title and sets program type = remoteref
    $resultref->{'title'} = $ceref->{'subtitle'};
    $resultref->{'title'} =~ s/(\d+)\:(\d+)$//i; # Removed 2:2 in the ending
    $resultref->{'title'} = norm($resultref->{'title'});
    $resultref->{'subtitle'} = undef;
    $resultref->{'program_type'} = $ruleref->{remoteref};
  }elsif( $ruleref->{matchby} eq 'subtitle_to_title' && $ceref->{'subtitle'} && $ceref->{'subtitle'} ne "") {
    # Sets subtitle as the title and sets program type = series
    $resultref->{'title'} = norm($ceref->{'subtitle'});
    $resultref->{'subtitle'} = norm($ceref->{'title'});
    $resultref->{'program_type'} = "series";
  }elsif( $ruleref->{matchby} eq 'orgtitle_to_title' && $ceref->{'original_title'} && $ceref->{'original_title'} ne "") {
    # Sets orgtitle as the title and sets program type = series
    $resultref->{'title'} = norm($ceref->{'original_title'});
    $resultref->{'original_title'} = undef;
    $resultref->{'subtitle'} = norm($ceref->{'title'});
    $resultref->{'program_type'} = "series";
  }elsif( $ruleref->{matchby} eq 'replacesubtitle' ) {
    $resultref->{'subtitle'} = $ruleref->{remoteref};
  }elsif( $ruleref->{matchby} eq 'setdescassubtitle' ) {
    # When the sub is still in the description and you are sure a long description wont show up
    if(!defined($ceref->{'subtitle'}) or $ceref->{'subtitle'} eq "") {
      $resultref->{'subtitle'} = $ceref->{description};

      # Season in desc
      if($resultref->{subtitle} =~ /^(S.song|S.son|Sesong) (\d+)/) {
        my ( $ep_info, $st ) = ($resultref->{subtitle} =~ /(.*)\: (.*)/);
        if( defined( $st ) and $st ne "" )
        {
          $resultref->{subtitle} = $st;
        }

        my ($dummy1, $season_s, $dummy2, $episode_s) = ($ep_info =~ /^(S.song|S.son|Sesong) (\d+) \- (Episode|Episod) (\d+)/i);
        $resultref->{episode} = sprintf( "%d . %d .", $season_s-1, $episode_s-1 ) if defined($season_s) and defined($episode_s);
      }

      # Subtitle
      if($resultref->{subtitle} =~ /, The$/i) {
        $resultref->{subtitle} =~ s/, The$//i;
        $resultref->{subtitle} = "The " . $resultref->{subtitle};
      }
      if($resultref->{subtitle} =~ /, A$/i) {
        $resultref->{subtitle} =~ s/, A$//i;
        $resultref->{subtitle} = "A " . $resultref->{subtitle};
      }
      if($resultref->{subtitle} =~ /, An$/i) {
        $resultref->{subtitle} =~ s/, An$//i;
        $resultref->{subtitle} = "An " . $resultref->{subtitle};
      }
      $resultref->{subtitle} =~ s|Del\s+(\d+)$| ($1)|;
      $resultref->{subtitle} =~ s|Pt\.(\d+)$| ($1)|;
      $resultref->{subtitle} =~ s|Part (\d+)$| ($1)|;
      $resultref->{subtitle} =~ s|Part Ii$| (2)|;
      $resultref->{subtitle} =~ s|Part I$| (1)|;
      $resultref->{subtitle} =~ s|Pt(\d+)$| ($1)|;
      $resultref->{subtitle} =~ s|,\s+del\s+(\d+)$| ($1)|;
      $resultref->{subtitle} =~ s|\s+-\s+| |;
      $resultref->{subtitle} =~ s|\s+:\s+| |;

      $resultref->{'description'} = undef;
    }
  }elsif( $ruleref->{matchby} eq 'splitsubtitle' ) {
    if( $ruleref->{otherfield} eq 'subtitle' ){
      my( $episodetitle )=( $ceref->{subtitle} =~ m|$ruleref->{othervalue}| );
      $resultref->{'subtitle'} = $episodetitle;
    }else{
      w( "Fixups::splitsubtitle must have otherfield='subtitle' and the regexp in othervalue!" );
    }
  }elsif( $ruleref->{matchby} eq 'copylastdetails' ) {
    # We have a program without details (no description) and want to
    # copy all details (all but details related to the transmission, like aspect
    # and audio) from the last program with the same title/subtitle/episode
    # number on the same (or another) channel.
    #
    # Remoteref can be a xmltvid of another channel to copy from there, in this case
    # the search will be for the same or an earlier start time.
    #
    # If the programme to augment has a timestamp (UTC!) in previously-shown then
    # try a programme with that start time first.
    #
    # FIXME what about series that air in pairs of two episodes?
    #
    # FIXME what about programmes that have been augmented in between? (rewrite of episode number / typo fixes in episode title)
    #

    my $channel_id = $ceref->{channel_id};
    if(defined($ruleref->{remoteref})) {
      $channel_id = $ruleref->{remoteref};
    }

    my $matchdone = 0;
    if( !$matchdone && $ceref->{'title'} && $ceref->{subtitle} && $ceref->{subtitle} ne "" && $ceref->{episode} && !$ceref->{description} ){
      # try matching by title/subtitle/episode number first
      d( 'matching by title/subtitle/episode number' );
      my ( $res, $sth ) = $self->{datastore}->sa->Sql( "
          SELECT * from programs
          WHERE channel_id = ? and title = ? and subtitle = ? and episode = ? and description is not null
          ORDER BY timediff( ? , start_time ) asc, start_time asc, end_time desc
          LIMIT 1",
        [$channel_id, $ceref->{title}, $ceref->{subtitle}, $ceref->{episode}, $ceref->{start_time}] );
      my $ce;
      while( defined( my $ce = $sth->fetchrow_hashref() ) ) {
        CopyProgramWithoutTransmission( $resultref, $ce );
        $matchdone=1;
      }
    }
    if( !$matchdone && $ceref->{'title'} && $ceref->{episode} && !$ceref->{description} ){
      # try matching by title/episode number next
      d( 'matching by title/episode number' );
      my ( $res, $sth ) = $self->{datastore}->sa->Sql( "
          SELECT * from programs
          WHERE channel_id = ? and title = ? and episode = ? and description is not null
          ORDER BY timediff( ? , start_time ) asc, start_time asc, end_time desc
          LIMIT 1",
        [$channel_id, $ceref->{title}, $ceref->{episode}, $ceref->{start_time}] );
      my $ce;
      while( defined( my $ce = $sth->fetchrow_hashref() ) ) {
        CopyProgramWithoutTransmission( $resultref, $ce );
        $matchdone=1;
      }
    }

	if( !$matchdone && $ceref->{'title'} && $ceref->{subtitle} && !$ceref->{description} ){
      # try matching by title/subtitle next
      d( 'matching by title/subtitle' );
      my( $res, $sth ) = $self->{datastore}->sa->Sql( "
          SELECT * from programs
          WHERE channel_id = ? and title = ? and subtitle = ? and description is not null
          ORDER BY timediff( ? , start_time ) asc, start_time asc, end_time desc
          LIMIT 1",
        [$channel_id, $ceref->{title}, $ceref->{subtitle}, $ceref->{start_time}] );
      my $ce;
      while( defined( my $ce = $sth->fetchrow_hashref() ) ) {
        d( 'copying from ' . $ce->{start_time} . ' to ' . $ceref->{start_time} );
        CopyProgramWithoutTransmission( $resultref, $ce );
        $matchdone=1;
      }
    }
    if( !$matchdone && $ceref->{'title'} && !$ceref->{episode} && !$ceref->{subtitle} && !$ceref->{description} ){
      # try matching just by title number last and only if episode number and subtitle are empty!
      d( 'matching by title' );
      my( $res, $sth ) = $self->{datastore}->sa->Sql( "
          SELECT * from programs
          WHERE channel_id = ? and title = ? and description is not null
          ORDER BY abs( timediff( start_time, ? ) ) asc, start_time asc, end_time desc
          LIMIT 1",
        [$channel_id, $ceref->{title}, $ceref->{start_time}] );
      my $ce;
      if( defined( my $ce = $sth->fetchrow_hashref() ) ) {
        CopyProgramWithoutTransmission( $resultref, $ce );
      }
    }
  }elsif( $ruleref->{matchby} eq 'splitepisodenumtitle' ) {
    my( $episodenum, $episodetitle )=( $ceref->{$ruleref->{otherfield}} =~ m|$ruleref->{othervalue}| );
    $resultref->{'subtitle'} = $episodetitle;
    $resultref->{'episode'} = ' . ' . ($episodenum - 1) . ' . ';
    $resultref->{program_type} = 'series';
  }else{
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
    w( $result );
    $resultref = undef;
  }

  return( $resultref, $result );
}


1;
