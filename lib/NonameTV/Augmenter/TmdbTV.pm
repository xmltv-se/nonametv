package NonameTV::Augmenter::TmdbTV;

use strict;
use warnings;

use Data::Dumper;
use Encode;
use utf8;
use TMDB;
use Text::LevenshteinXS qw(distance);

use NonameTV qw/AddCategory AddCountry norm ParseXml RemoveSpecialChars CleanSubtitle/;
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

    defined( $self->{ApiKey} )   or die "You must specify ApiKey";
    defined( $self->{Language} ) or die "You must specify Language";

    # only consider Ratings with 10 or more votes by default
    if( !defined( $self->{MinRatingCount} ) ){
      $self->{MinRatingCount} = 10;
    }

    # only copy the synopsis if you trust their rights clearance enough!
    if( !defined( $self->{OnlyAugmentFacts} ) ){
      $self->{OnlyAugmentFacts} = 0;
    }

    # need config for main content cache path
    my $conf = ReadConfig( );

    my $cachedir = $conf->{ContentCachePath} . '/' . $self->{Type};

    $self->{themoviedb} = TMDB->new(
        apikey => $self->{ApiKey},
        lang   => $self->{Language},
    );

    $self->{search} = $self->{themoviedb}->search(
        include_adult => 'false',  # Include adult results. 'true' or 'false'
    );

    return $self;
}


sub FillCast( $$$$$ ) {
  my( $self, $resultref, $credit, $series, $episode )=@_;

  my @credits = ( );
  if(defined($episode->{credits})) {
    foreach my $castmember ( @{ $episode->{credits}->{cast} } ){
      my $name = $castmember->{'name'};
      my $role = $castmember->{'character'};
      if( $role ) {
        # skip roles like '-', but allow roles like G, M, Q (The Guru, James Bond)
        if( ( length( $role ) > 1 )||( $role =~ m|^[A-Z]$| ) ){
          $name .= ' (' . $role . ')';
        } else {
          w( 'Unlikely role \'' . $role . '\' for actor. Fix it at ' . $resultref->{url} . '/edit?active_nav_item=cast' );
        }
      }
      push( @credits, $name );
    }
  }

  foreach my $guests ( @{ $episode->{guest_stars} } ){
    my $name = $guests->{'name'};
    my $role = $guests->{'character'};
    if( $role ) {
      # skip roles like '-', but allow roles like G, M, Q (The Guru, James Bond)
      if( ( length( $role ) > 1 )||( $role =~ m|^[A-Z]$| ) ){
        $name .= ' (' . $role . ')';
      } else {
        w( 'Unlikely role \'' . $role . '\' for actor. Fix it at ' . $resultref->{url} . '/edit?active_nav_item=cast' );
      }
    }
    push( @credits, $name );
  }

  if( @credits ) {
    $resultref->{$credit} = join( ';', @credits );
  }
}


sub FillCrew( $$$$$$ ) {
  my( $self, $resultref, $credit, $series, $episode, $job )=@_;

  my @credits = ( );
  foreach my $crewmember ( @{ $episode->{crew} } ){
    if( $crewmember->{'job'} eq $job ){
      my $name = $crewmember->{'name'};
      push( @credits, $name );
    }
  }
  if( @credits ) {
    $resultref->{$credit} = join( ';', @credits );
  }
}


sub FillHash( $$$$ ) {
  my( $self, $resultref, $series, $episode, $ceref )=@_;

  ########## SERIES INFO

  # Fix when name is not using the original name correctly.
  if(lc($ceref->{title}) eq lc($series->info->{name})) {
    $resultref->{title} = $series->info->{name};
  }

  # Org title
  if( defined( $series->info->{original_name} ) and (lc($ceref->{title}) ne lc($series->info->{original_name})) ){
    $resultref->{original_title} = norm( $series->info->{original_name} );
  }

  # Genres
  if( exists( $series->info->{genres} ) ){
    my @genres = @{ $series->info->{genres} };
    my @cats;
    foreach my $node ( @genres ) {
      my $genre_id = $node->{id};
      my ( $type, $categ ) = $self->{datastore}->LookupCat( "Tmdb_genre", $genre_id );
      push @cats, $categ if defined $categ;
    }
    my $cat = join "/", @cats;
    AddCategory( $resultref, "series", $cat );
  }

  # Origin country
  if( exists( $series->info->{production_countries} ) ){
    my @countries;
    my @production_countries = @{ $series->info->{production_countries} };
    foreach my $node2 ( @production_countries ) {
      my $c_id = $node2->{iso_3166_1};
      #my ( $country ) = $self->{datastore}->LookupCountry( "Tmdb_country", $c_id );
      push @countries, $c_id if defined $c_id;
    }
    my $country2 = join "/", @countries;
    AddCountry( $resultref, $country2 );
  }

  # YOU HAVE GUESTS in $episodes->guest_stars
  # CREW IN $EPISODES->crew

  ############ EPISODE

  if( $episode->{air_date} ) {
    $resultref->{production_date} = $episode->{air_date};
  }

  # Find total number of episodes in a season
  my $total_eps = undef;
  foreach my $seasons ( @{ $series->info->{seasons} } ){
    next if ((!defined($seasons->{season_number}) or !defined($episode->{season_number})) or ($seasons->{season_number} != $episode->{season_number}));

    $total_eps = $seasons->{episode_count};
  }


  # Subtitle / Episode num
  if( $episode->{season_number} == 0 ){
    # it's a special
    $resultref->{episode} = undef;
    $resultref->{subtitle} = norm( "Special - ".$episode->{name} );
  }else{
    if(defined($total_eps)) {
      $resultref->{episode} = sprintf( "%d . %d/%d . ", $episode->{season_number}-1, $episode->{episode_number}-1, $total_eps );
    } else {
      $resultref->{episode} = sprintf( "%d . %d . ", $episode->{season_number}-1, $episode->{episode_number}-1 );
    }


    # use episode title
    #print Dumper($episode);
    $resultref->{subtitle} = norm( $episode->{name} ) if(norm( $episode->{name} ) ne "" and (!defined($ceref->{subtitle}) or $ceref->{subtitle} eq ""));
  }

  # Ratings
  if( defined( $episode->{vote_count} ) ){
    my $votes = $episode->{vote_count};
    if( $votes >= $self->{MinRatingCount} ){
      # ratings range from 0 to 10
      $resultref->{'star_rating'} = $episode->{vote_average} . ' / 10';
    }
  }

  ############ Add actors etc

  $self->FillCast( $resultref, 'actors', $series, $episode );

  $self->FillCrew( $resultref, 'directors', $series, $episode, 'Director');
  $self->FillCrew( $resultref, 'producers', $series, $episode, 'Producer');
  $self->FillCrew( $resultref, 'writers', $series, $episode, 'Screenplay');
  $self->FillCrew( $resultref, 'writers', $series, $episode, 'Writer');


  ############ EXTERNAL LINKS

  $resultref->{url} = sprintf(
    'https://www.themoviedb.org/tv/%d/season/%d/episode/%d',
    $series->info->{id}, $episode->{season_number}, $episode->{episode_number}
  );
  $resultref->{extra_id} = $series->info->{ id };
  $resultref->{extra_id_type} = "themoviedb";
}


sub AugmentProgram( $$$ ){
  my( $self, $ceref, $ruleref ) = @_;

  # empty hash to get all attributes to change
  my $resultref = {};
  # result string, empty/false for success, message/true for failure
  my $result = '';
  my $matchby = undef;

  # episodeabs
  my( $episodeabs );

  # It guesses what it needs
  if( $ruleref->{matchby} eq 'guess' ) {
    # Subtitles, no episode
    if(defined($ceref->{subtitle}) && !defined($ceref->{episode})) {
    	# Match it by subtitle
    	$matchby = "episodetitle";
    } elsif(!defined($ceref->{subtitle}) && defined($ceref->{episode})) {
    	# The opposite, match it by episode
    	$matchby = "episodeseason";
    } elsif(defined($ceref->{subtitle}) && defined($ceref->{episode})) {
        # Check if it has season otherwise title.
        my( $season, $episode )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );
        if( (defined $episode) and (defined $season) ){
            $matchby = "episodeseason";
        } else {
            $matchby = "episodetitle";
        }
    } else {
    	# Match it by seriesname (only change series name) here later on maybe?
    	return( undef, 'couldn\'t guess the right matchby, sorry.' );
    }
  } elsif( $ruleref->{matchby} eq 'episodeabsnoseason') {
    # WARNING: DONT USE THIS IF YOU ARENT SURE ITS ACTUALLY EPISODEABS, AS YOU ARE FUCKING EVERYTHING UP
    #my ($seasonxabs);
    #( $seasonxabs, $episodeabs )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );

    $matchby = 'episodeabs';
  } elsif( $ruleref->{matchby} eq 'absorepsea' ) {
    if(!defined($ceref->{episode}) and defined($ceref->{subtitle})) {
      $matchby = 'episodetitle';
    }
    # Season?
    elsif(defined($ceref->{episode}) and $ceref->{episode} =~ /^\s*(\d+)\s*\.\s*(\d+)\s*/) {
      my( $seasonss, $episodess )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );

      # Check if the episode number is above the count of eps on that season
      my $serie = $self->find_series($ceref, $ruleref);
      my $epcount = 0;

      return( undef, 'couldn\'t guess the right matchby, sorry.' ) if !defined $serie;

      # check seasons
      foreach my $seasons ( @{ $serie->info->{seasons} } ){
        next if($seasons->{season_number} == 0);  # Skip specials

        # Seasons before the wanted season..
        if($seasons->{season_number} != ($seasonss + 1)) {
          if($epcount < $seasons->{episode_count}) {
            $epcount = $seasons->{episode_count};
          }

          next;
        }

        # is the episode number within the episode count or more?
        if(($episodess + 1) > $seasons->{episode_count}) {
          # Its more but check if its less than the past episode counts
          if(($episodess + 1) < $epcount) {
            if($ceref->{subtitle}) {
              print("$ceref->{title} - match by episodetitle (epcount: $epcount, number: $episodess, season: $seasonss)\n");
              $matchby = 'episodetitle';
            } else {
              print("$ceref->{title} - match by nothing (epcount: $epcount, number: $episodess, season: $seasonss)\n");
              $matchby = "nothing";
            }

          } else {
            print("$ceref->{title} - match by episodeabs (epcount: $epcount, number: $episodess, season: $seasonss)\n");
            $matchby = 'episodeabs';
            $episodeabs = $episodess;
          }

        } else {
          $matchby = 'episodeseason';
        }

      }

    } else {
      # Right now it just defaults to episode abs if it doesn't have a season number
      #( $episodeabs )=( $ceref->{episode} =~ m|\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );
      $matchby = 'nothing';
    }
  } else {
    $matchby = $ruleref->{matchby};
  }

  return( undef, 'matchby was undefined?' ) if !defined($matchby);

  # Match bys
  if( $ceref->{url} && $ceref->{url} =~ m|^https://www\.themoviedb\.org/tv/\d+| ) {
    $result = "programme is already linked to themoviedb.org, ignoring";
    $resultref = undef;
  } elsif( $matchby eq 'episodeabs' ) {
    # match by absolute episode number from program hash. USE WITH CAUTION, NOT EVERYONE AGREES ON ANY ORDER!!!

    if( defined $ceref->{episode} ){
      if( not defined $episodeabs ){
        ( $episodeabs )=( $ceref->{episode} =~ m|^\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );
      }

      # Found!
      if( defined $episodeabs ){
        $episodeabs += 1;

        my $series = $self->find_series($ceref, $ruleref);

        # Matched?
        if( (defined $series)){
          # Calculate episode absolutes
          my $old_totaleps = 0;
          my $new_totaleps = 0;
          my $episode = undef;
          my $season = undef;

          #print Dumper($series, $series->info);

          foreach my $seasons ( @{ $series->info->{seasons} } ){
            next if($seasons->{season_number} == 0);
            $new_totaleps = $old_totaleps + $seasons->{episode_count};

            # Check if the episode num is in range
            if(($old_totaleps < $episodeabs) and ($new_totaleps >= $episodeabs)) {
              $season = $seasons->{season_number};

              # Dont subtract if season is 1
              if($seasons->{season_number} == 1) {
                $episode = $episodeabs;
              } else {
                $episode = $episodeabs-$old_totaleps;
              }

              # Dbeug
              if($episode == 0) {
                #print Dumper($episodeabs, $season, $episode, $new_totaleps);
                w("got episode num zero, duno why. look into this.");
                $episode = undef;
              }


              $old_totaleps = $new_totaleps;

              # last in foreach
              last;
            } else {
              $old_totaleps = $new_totaleps;
            }
          }

          # Nothing found
          if(!defined($episode)) {
            w( "no episode with absolute number " . $episodeabs . " found for '" . $ceref->{title} . "'" );
          } else {
            #print $series->info->{name};
            my $episode2 = $series->episode($season, $episode, {"append_to_response" => "credits"});

            # Fil?
          	if( defined( $episode2 ) and !defined( $episode2->{status_code} ) ) {
            	$self->FillHash( $resultref, $series, $episode2, $ceref );
          	} else {
            	w( "no episode " . $episode . " of season " . $season . " found for '" . $ceref->{title} . "'" );
          	}
          }

        }

      }

    }

  } elsif( $matchby eq 'episodeseason' ) {
    # Find episode by season and episode.

    if( defined $ceref->{episode} ){
      my( $season, $episode )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );

      # It had episode and season!
      if( (defined $episode) and (defined $season) ){
        $episode += 1;
        $season += 1;

        my $series = $self->find_series($ceref, $ruleref);

        # Matched?
        if( (defined $series)){
          # match episode
          if(($season ne "") and ($episode ne "")) {
            #print $series->info->{name};
            my $episode2 = $series->episode($season, $episode, {"append_to_response" => "credits"});

            # Fil?
          	if( defined( $episode2 ) and !defined( $episode2->{status_code} ) ) {
            	$self->FillHash( $resultref, $series, $episode2, $ceref );
          	} else {
            	w( "no episode " . $episode . " of season " . $season . " found for '" . $ceref->{title} . "'" );
          	}
          }

        }

      }

    }

  } elsif( $matchby eq 'episodeyear' ) {
    # Find episode by season and episode.

    if( defined $ceref->{episode} ){
      my( $year, $episode )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );

      # It had episode and season!
      if( (defined $episode) and (defined $year) and $year > 1800 ){
        $episode += 1;
        $year += 1;

        my $series = $self->find_series($ceref, $ruleref);

        # Matched?
        if( (defined $series) and ($year ne "") and ($episode ne "")){
          # Check if the year matches
          my $season = undef;
          foreach my $seasons ( @{ $series->info->{seasons} } ){
            # Next if these shits fucks up
            next if($seasons->{season_number} == 0);
            next if(!defined($seasons->{air_date}) or $seasons->{air_date} == "");

            # Get air year
            my( $season_year ) = ($seasons->{air_date} =~ /^(\d\d\d\d)/);
            next if(!defined($season_year) or $year != $season_year);

            # Season!
            $season = $seasons->{season_number};
            w( "matched (year: $year) " . $episode . " of season " . $season . " found for '" . $ceref->{title} . "'" );
          }

          # Not Matched
          if(!defined($season)) {
            w( "no season found for year " . $season . " for '" . $ceref->{title} . "'" );
          } else {
            # Matched!
            my $episode2 = $series->episode($season, $episode, {"append_to_response" => "credits"});

            # Fil?
            if( defined( $episode2 ) and !defined( $episode2->{status_code} ) ) {
              $self->FillHash( $resultref, $series, $episode2, $ceref );
            } else {
              w( "no episode " . $episode . " of season " . $season . " found for '" . $ceref->{title} . "'" );
            }

          }


        }

      }
    }
  } elsif( $matchby eq 'episodetitle' ) {
    ## You need to fetch first the show,
    ## then the season one by one to get the titles.

    if( defined($ceref->{subtitle}) or defined($ceref->{original_subtitle}) ){

      my $series = $self->find_series($ceref, $ruleref);

      # Match shit
      if( (defined $series) ){
        # Check if the year matches
        my $season = undef;
        my $episode = undef;

        # Find by episode title
        my $eps = $self->find_episode_by_name($ceref, $ruleref, $series);
        if(defined($eps)) {
          $season = $eps->{season_number};
          $episode = $eps->{episode_number};
        }

        # match
        if(defined($season)) {
          # Matched!
          my $episode2 = $series->episode($season, $episode, {"append_to_response" => "credits"});

          # Fil?
          if( defined( $episode2 ) and !defined( $episode2->{status_code} ) ) {
            $self->FillHash( $resultref, $series, $episode2, $ceref );
          } else {
            if(defined($ceref->{subtitle})) {
              w( "episode not found by title nor org subtitle: " . $ceref->{title} . " - \"" . $ceref->{subtitle} . "\"" );
            }

            if(defined($ceref->{original_subtitle})) {
              w( "episode not found by title nor org subtitle: " . $ceref->{title} . " - \"" . $ceref->{original_subtitle} . "\"" );
            }
          }
        } else {
          w( "episode not found by title nor org subtitle: " . $ceref->{title} );
        }

      }
    }
  } elsif( $matchby eq 'episodeid' ) {
    $result = "TMDB doesnt provide an API CALL with episode ids.";
  } else {
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
  }


  return( $resultref, $result );
}

# Find series
sub find_series($$$ ) {
  my( $self, $ceref, $ruleref )=@_;

  my $series;
  my @candidates;
  my @results;
  my @ids = ();
  my @keep = ();
  my $candidate;

  # It have an series id, so you don't need to search
  if( defined( $ruleref->{remoteref} ) ) {
    return $self->{themoviedb}->tv( id => $ruleref->{remoteref} );
  } elsif(defined($ceref->{extra_id_type}) and $ceref->{extra_id_type} eq "thetvdb") {
    @results = @{$self->{search}->find(
        id     => $ceref->{extra_id},
        source => 'tvdb_id'
    )->{tv_results}};
    my $resultnum = @results;

    # Results?
    if( $resultnum > 0 ) {
      return $self->{themoviedb}->tv( id => $results[0]->{id} );
    } else {
      w( "no series found with tvdb_id " . $ceref->{extra_id} . " - \"" . $ceref->{title} . "\"" );
    }
  } elsif(defined($ceref->{extra_id_type}) and $ceref->{extra_id_type} eq "imdb") {
    @results = @{$self->{search}->find(
        id     => $ceref->{extra_id},
        source => 'imdb_id'
    )->{tv_results}};
    my $resultnum = @results;

    # Results?
    if( $resultnum > 0 ) {
      return $self->{themoviedb}->tv( id => $results[0]->{id} );
    } else {
      w( "no series found with imdb_id " . $ceref->{extra_id} . " - \"" . $ceref->{title} . "\"" );
    }
  } else {
    @candidates = $self->{search}->tv( $ceref->{title} );
    foreach my $c ( @candidates ){
      if( defined( $c->{id} ) ) {
        push( @ids, $c->{id} );
      }
    }


    # No data? Try the original title
    if(defined $ceref->{original_title} and $ceref->{original_title} ne "" and $ceref->{original_title} ne $ceref->{title}) {
      my @org_candidates = $self->{search}->tv( $ceref->{original_title} );

      foreach my $c2 ( @org_candidates ){
        # It can't be added already
        if ( !(grep $_ eq $c2->{id}, @ids) ) {
          push( @candidates, $c2 );
        }
      }
    }

    # no results?
    my $numResult = @candidates;

    if( $numResult < 1 ){
      return undef;
    }

    # Check actors
    if( scalar(@candidates) >= 1 and ( $ceref->{actors} ) ){
      my @actors = split( /;/, $ceref->{actors} );
      my $match = 0;

      # loop over all remaining movies
      while( @candidates ) {
        my $candidate = shift( @candidates );

        if( defined( $candidate->{id} ) ) {
          # we have to fetch the remaining candidates to peek at the directors
          my $tvid = $candidate->{id};
          my $movie = $self->{themoviedb}->tv( id => $tvid );

          my @names = ( );
          foreach my $cast ( $movie->cast ) {
            my $person = $self->{themoviedb}->person( id => $cast->{id} );

            if( defined( $person ) ){
              if( defined( $person->aka() ) ){
                if( defined( $person->aka()->[0] ) ){
                  # FIXME actually aka() should simply return an array
                  my $aliases = $person->aka()->[0];
                  if( defined( $aliases ) ){
                    @names =  ( @names, @{ $aliases } );
                  }else{
                    my $url = 'http://www.themoviedb.org/person/' . $cast->{id};
                    w( "something is fishy with this persons aliases, see $url." );
                  }
                  push( @names, $person->name );
                }else{
                  my $url = 'http://www.themoviedb.org/person/' . $cast->{id};
                w( "got a person but could not get the aliases (with [0]), see $url." );
                }
              }else{
                my $url = 'http://www.themoviedb.org/person/' . $cast->{id};
                w( "got a person but could not get the aliases, see $url." );
              }
            }else{
              my $url = 'http://www.themoviedb.org/person/' . $cast->{id};
              w( "got a reference to a person but could not get the person, see $url." );
            }
          }

          my $matches = 0;
          if( @names == 0 ){
            my $url = 'http://www.themoviedb.org/tv/' . $candidate->{ id };
            w( "actors not on record, removing candidate. Add it at $url." );
          } else {
            foreach my $a ( @actors ) {
              foreach my $b ( @names ) {
                $a =~ s/(\.|\,)//;
                $b =~ s/(\.|\,)//;
                $a =~ s/ \(.*?\)//;
                $b =~ s/ \(.*?\)//;

                if( lc norm( $a ) eq lc norm( $b ) ) {
                  $matches += 1;
                }
              }
            }
          }

          if( $matches == 0 ){
            d( "actors '" . $ceref->{actors} ."' not found, removing candidate" );
          } else {
            push( @keep, $candidate );
          }
        }else{
          w( "got a tv result without id as candidate! " . Dumper( $candidate ) );
        }
      }

      @candidates = @keep;
      @keep = ();
    }

    # need to be the correct country if available
    if( $ceref->{country} and $ceref->{country} ne "" ) {
      my( @countries ) = split("/", $ceref->{country});

      while( @candidates ) {
        $candidate = shift( @candidates );
        next if(scalar(@{$candidate->{origin_country}}) < 1);

        foreach my $contri (@countries) {
          # Matched!
          if ( grep $_ eq $contri, @{$candidate->{origin_country}} ) {
            push( @keep, $candidate );
            last;
          }
        }
      }

      @candidates = @keep;
      @keep = ();
    }

    # need to be the correct year if available
    if( scalar(@candidates) > 1 and $ceref->{production_date} and $ceref->{production_date} ne "" ) {
      my( $produced )=( $ceref->{production_date} =~ m|^(\d{4})\-\d+\-\d+$| );
      while( @candidates ) {
        $candidate = shift( @candidates );

        # verify that production and release year are close
        my $released = $candidate->{ first_air_date };
        $released =~ s|^(\d{4})\-\d+\-\d+$|$1|;

        # released
        if( !$released ){
          my $url = 'http://www.themoviedb.org/tv/' . $candidate->{ id };
          w( "year of release not on record, removing candidate. Add it at $url." );
        } elsif( $released >= ($produced+2) ){
          # Sometimes the produced year is actually the produced year.
          d( "first aired of the series '$released' is later than the produced '$produced'" );
        } else {
          push( @keep, $candidate );
        }

      }

      @candidates = @keep;
      @keep = ();
    }

    # Still more than x amount in array then try to get the correct show based on title or org title
    if(scalar(@candidates) > 1) {
      while( @candidates ) {
        $candidate = shift( @candidates );

        # So shit doesn't get added TWICE
        my $match2 = 0;

        # Title matched?
        if(distance( lc(RemoveSpecialChars($ceref->{title})), lc(RemoveSpecialChars($candidate->{name})) ) <= 2) {
          push( @keep, $candidate );
          $match2 = 1;
        }

        if(!$match2 and distance( lc(RemoveSpecialChars($ceref->{title})), lc(RemoveSpecialChars($candidate->{original_name})) ) <= 2) {
          push( @keep, $candidate );
          $match2 = 1;
        }

        if(!$match2 and defined($ceref->{original_title}) and distance( lc(RemoveSpecialChars($ceref->{original_title})), lc(RemoveSpecialChars($candidate->{name})) ) <= 2) {
          push( @keep, $candidate );
          $match2 = 1;
        }

        if(!$match2 and defined($ceref->{original_title}) and distance( lc(RemoveSpecialChars($ceref->{original_title})), lc(RemoveSpecialChars($candidate->{original_name})) ) <= 2) {
          push( @keep, $candidate );
          $match2 = 1;
        }
      }

      @candidates = @keep;
      @keep = ();
    }

    # Still more than one result?
    # Check more strictly on the first year
    if(scalar(@candidates) > 1 and $ceref->{production_date} and $ceref->{production_date} ne "") {
      my( $produced )=( $ceref->{production_date} =~ m|^(\d{4})\-\d+\-\d+$| );
      while( @candidates ) {
        $candidate = shift( @candidates );

        # verify that production and release year are close
        my $released2 = $candidate->{ first_air_date };
        $released2 =~ s|^(\d{4})\-\d+\-\d+$|$1|;

        # released
        if( !$released2 ){
          my $url = 'http://www.themoviedb.org/tv/' . $candidate->{ id };
          w( "year of release not on record, removing candidate. Add it at $url." );
        } elsif( abs( $released2 - $produced ) > 2 ){
          # Sometimes the produced year is actually the produced year.
          d( "year of production '$produced' to far away from year of first aired '$released2', removing candidate" );
        } else {
          push( @keep, $candidate );
        }

      }

      @candidates = @keep;
      @keep = ();
    }

    # Matches
    if( ( @candidates == 0 ) || ( @candidates > 1 ) ){
      my $warning = 'search for "' . $ceref->{title} . '"';
      if( $ceref->{production_date} ){
        $warning .= ' from ' . $ceref->{production_date} . '';
      }
      if( $ceref->{countries} ){
        $warning .= ' in "' . $ceref->{countries} . '"';
      }
      if( @candidates == 0 ) {
        $warning .= ' did not return any good hit, ignoring';
      } else {
        $warning .= ' did not return a single best hit, ignoring';
      }
      w( $warning );
    } else {
      return $self->{themoviedb}->tv( id => $candidates[0]->{id} );
    }

  }

  return undef;
}

# Find episode by name
sub find_episode_by_name($$$$ ) {
  my( $self, $ceref, $ruleref, $series )=@_;

  my($season, $episode, $subtitle, $org_subtitle);

  # Subtitles
  if(defined $ceref->{subtitle}) {
    $subtitle = lc(RemoveSpecialChars(CleanSubtitle($ceref->{subtitle})));
  }
  if(defined $ceref->{original_subtitle}) {
    $org_subtitle = lc(RemoveSpecialChars(CleanSubtitle($ceref->{original_subtitle})));
  }

  # Each season check for eps
  my $hitcount = 0;
  my $hit;
  foreach my $seasons ( @{ $series->info->{seasons} } ){
    my $episodes = $series->season($seasons->{season_number});

    # Each episode
    foreach my $eps ( @{ $episodes->{episodes} } ){
      next if(!defined($eps->{name}) or $eps->{name} eq "");
      my $epsname = lc(RemoveSpecialChars(CleanSubtitle($eps->{name})));

      # Match eps name
      if( defined($subtitle) and distance( $epsname, $subtitle ) <= 2 ){
 				$hitcount ++;
 				$hit = $eps;
        next;
 			}

      # Match eps name
      if( defined($org_subtitle) and distance( $epsname, $org_subtitle ) <= 2 ){
 				$hitcount ++;
 				$hit = $eps;
        next;
 			}

    }
  }

  # Return season and episode if found
  if( $hitcount == 1){
    return( $hit );
  } else {
    return undef;
  }
}

1;
