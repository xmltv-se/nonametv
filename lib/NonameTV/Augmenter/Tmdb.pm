package NonameTV::Augmenter::Tmdb;

use strict;
use warnings;

use Data::Dumper;
use Encode;
use utf8;
use WWW::TheMovieDB::Search;

use NonameTV qw/AddCategory norm ParseXml/;
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

#    my $cachefile = $conf->{ContentCachePath} . '/' . $self->{Type} . '/tvdb.db';
#    my $bannerdir = $conf->{ContentCachePath} . '/' . $self->{Type} . '/banner';

    $self->{themoviedb} = new WWW::TheMovieDB::Search;
    $self->{themoviedb}->key( $self->{ApiKey} );
    $self->{themoviedb}->lang( $self->{Language} );

    # slow down to avoid rate limiting
    $self->{Slow} = 1;

    return $self;
}


sub FillCredits( $$$$$ ) {
  my( $self, $resultref, $credit, $doc, $job )=@_;

  my @nodes = $doc->findnodes( '/OpenSearchDescription/movies/movie/cast/person[@job=\'' . $job . '\']' );
  my @credits = ( );
  foreach my $node ( @nodes ) {
    my $name = norm($node->findvalue( './@name' ));
    if( $job eq 'Actor' ) {
      my $role = $node->findvalue( './@character' );
      if( $role ) {
        # skip roles like '-', but allow roles like G, M, Q (The Guru, James Bond)
        if( ( length( $role ) > 1 )||( $role =~ m|^[A-Z]$| ) ){
          $name .= ' (' . norm($role) . ')';
        } else {
          w( 'Unlikely role \'' . $role . '\' for actor. Fix it at ' . $resultref->{url} . '/edit?active_nav_item=cast' );
        }
      }
    }
    push( @credits, $name );
  }
  if( @credits ) {
    $resultref->{$credit} = join( ', ', @credits );
  }
}


sub FillHash( $$$ ) {
  my( $self, $resultref, $movieId, $ceref )=@_;
 
  if( $self->{Slow} ) {
    sleep (1);
  }
  my $apiresult = $self->{themoviedb}->Movie_getInfo( $movieId );
  my $doc = ParseXml( \$apiresult );

  if (not defined ($doc)) {
    w( $self->{Type} . ' failed to parse result.' );
    return;
  }

  # FIXME shall we use the alternative name if that's what was in the guide???
  # on one hand the augmenters are here to unify various styles on the other
  # hand matching the other guides means less surprise for the users
  #<<<<<<< HEAD
  #
  # Change original_name to name if you want your specific language's movie name.
  #$resultref->{title} = norm( $doc->findvalue( '/OpenSearchDescription/movies/movie/original_name' ) );
  #$resultref->{original_title} = norm($ceref->{title});
  $resultref->{title} = norm( $doc->findvalue( '/OpenSearchDescription/movies/movie/name' ) );
  $resultref->{original_title} = norm( $doc->findvalue( '/OpenSearchDescription/movies/movie/original_name' ) );

  # TODO shall we add the tagline as subtitle? (for german movies the tv title is often made of the movie title plus tagline)
  $resultref->{subtitle} = undef;

  # is it a movie? (makes sense once we match by other attributes then program_type=movie :)
  my $type = $doc->findvalue( '/OpenSearchDescription/movies/movie/type' );
  if( $type eq 'movie' ) {
    $resultref->{program_type} = 'movie';
    
    # Remove subtitle
    $resultref->{subtitle} = undef;
  }

  my $votes = $doc->findvalue( '/OpenSearchDescription/movies/movie/votes' );
  if( $votes >= $self->{MinRatingCount} ){
    # ratings range from 0 to 10
    $resultref->{'star_rating'} = $doc->findvalue( '/OpenSearchDescription/movies/movie/rating' ) . ' / 10';
  }
  
  # MPAA - G, PG, PG-13, R, NC-17 - No rating is: NR or Unrated
  if(defined($doc->findvalue( '/OpenSearchDescription/movies/movie/certification' ) )) {
    my $rating = norm( $doc->findvalue( '/OpenSearchDescription/movies/movie/certification' ) );
    if( $rating ne '0' ) {
      $resultref->{rating} = $rating;
    }
  }
  
  # No description when adding? Add the description from themoviedb
  if((!defined ($ceref->{description}) or ($ceref->{description} eq "")) and !$self->{OnlyAugmentFacts}) {
    my $desc = norm( $doc->findvalue( '/OpenSearchDescription/movies/movie/overview' ) );
    if( $desc ne 'No overview found.' ) {
      $resultref->{description} = $desc;
    }
  }

  my @genres = $doc->findnodes( '/OpenSearchDescription/movies/movie/categories/category[@type="genre"]' );
  foreach my $node ( @genres ) {
    my $genre_id = $node->findvalue( './@id' );
    my ( $type, $categ ) = $self->{datastore}->LookupCat( "Tmdb_genre", $genre_id );
    AddCategory( $resultref, $type, $categ );
  }

  # TODO themoviedb does not store a year of production only the first screening, that should go to previosly-shown instead
  # $resultref->{production_date} = $doc->findvalue( '/OpenSearchDescription/movies/movie/released' );

  $resultref->{url} = $doc->findvalue( '/OpenSearchDescription/movies/movie/url' );
  $resultref->{extra_id} = $doc->findvalue( '/OpenSearchDescription/movies/movie/imdb_id' );
  $resultref->{extra_id_type} = "themoviedb";
	
  	$self->FillCredits( $resultref, 'actors', $doc, 'Actor');

#	  $self->FillCredits( $resultref, 'adapters', $doc, 'Actors');
#  	$self->FillCredits( $resultref, 'commentators', $doc, 'Actors');
  	$self->FillCredits( $resultref, 'directors', $doc, 'Director');
#  	$self->FillCredits( $resultref, 'guests', $doc, 'Actors');
#  	$self->FillCredits( $resultref, 'presenters', $doc, 'Actors');
  	$self->FillCredits( $resultref, 'producers', $doc, 'Producer');
  	
  	# Writers can be in multiple "jobs", ie: Author, Writer, Screenplay and more.
  	$self->FillCredits( $resultref, 'writers', $doc, 'Screenplay');

#  print STDERR Dumper( $apiresult );
}


sub AugmentProgram( $$$ ){
  my( $self, $ceref, $ruleref ) = @_;

  # empty hash to get all attributes to change
  my $resultref = {};
  # result string, empty/false for success, message/true for failure
  my $result = '';

  if( $ceref->{url} && $ceref->{url} =~ m|^http://www\.themoviedb\.org/movie/\d+$| ) {
    $result = "programme is already linked to themoviedb.org, ignoring";
    $resultref = undef;
  } elsif( $ruleref->{matchby} eq 'movieid' ) {
    $self->FillHash( $resultref, $ruleref->{remoteref}, $ceref );
    
  } elsif( $ruleref->{matchby} eq 'title' ) {
    # year and directors
    if( !$ceref->{production_date} && !$ceref->{directors}){
      return( undef,  "Year and directors unknown, not searching at themoviedb.org!" );
    }

	$ruleref->{matchby} = "titleonly";
	
  } elsif( $ruleref->{matchby} eq 'titleonlyyear' ) {
    # year and directors
    if( !$ceref->{production_date} ){
      return( undef,  "Year unknown, not searching at themoviedb.org!" );
    }

	$ruleref->{matchby} = "titleonly";

  } elsif( $ruleref->{matchby} eq 'titleonly' ) {
    # search by title and year (if present)
    my $searchTerm = $ceref->{title};

    # filter characters that confuse the search api
    # FIXME check again now that we encode umlauts & co.
    $searchTerm =~ s|[-#\?\N{U+00BF}\(\)]||g;

    if( $self->{Slow} ) {
      sleep (1);
    }
    # TODO fix upstream instead of working around here
    my $apiresult = $self->{themoviedb}->Movie_search( encode( 'utf-8', $searchTerm ) );

    if( !$apiresult ) {
      return( undef, $self->{Type} . ' empty result xml, bug upstream site to fix it.' );
    }

    my $doc = ParseXml( \$apiresult );

    if (not defined ($doc)) {
      return( undef, $self->{Type} . ' failed to parse result.' );
    }

    # The data really looks like this...
    my $ns = $doc->find ('/OpenSearchDescription/opensearch:totalResults');
    if( $ns->size() == 0 ) {
      return( undef,  "No valid search result returned" );
    }

    my $numResult = $doc->findvalue( '/OpenSearchDescription/opensearch:totalResults' );
    if( $numResult < 1 ){
      return( undef,  "No matching movie found when searching for: " . $searchTerm );
#    }elsif( $numResult > 1 ){
#      return( undef,  "More then one matching movie found when searching for: " . $searchTerm );
    }else{
#      print STDERR Dumper( $apiresult );

      my @candidates;
      # filter out movies more then 2 years before/after if we know the year
      if ( $ceref->{production_date} ) {
        my( $produced )=( $ceref->{production_date} =~ m|^(\d{4})\-\d+\-\d+$| );
        @candidates = $doc->findnodes( '/OpenSearchDescription/movies/movie' );
        foreach my $candidate ( @candidates ) {
          # verify that production and release year are close
          my $released = $candidate->findvalue( './released' );
          $released =~ s|^(\d{4})\-\d+\-\d+$|$1|;
          if( !$released ){
            $candidate->unbindNode();
            my $url = $candidate->findvalue( 'url' );
            w( "year of release not on record, removing candidate. Add it at $url." );
          } elsif( abs( $released - $produced ) > 2 ){
            $candidate->unbindNode();
            d( "year of production '$produced' to far away from year of release '$released', removing candidate" );
          }
        }
      }

      # if we have multiple candidate movies strip out all without a matching director
      @candidates = $doc->findnodes( '/OpenSearchDescription/movies/movie' );
      if( ( @candidates > 1 ) and ( $ceref->{directors} ) ){
        my @directors = split( /, /, $ceref->{directors} );
        my $director = $directors[0];
        
        # Remover - You need so the whole importer feed doesn't crash. (remove ')
        $director =~ s/'//g;
        
        foreach my $candidate ( @candidates ) {
          # we have to fetch the remaining candidates to peek at the directors
          my $movieId = $candidate->findvalue( 'id' );
          if( $self->{Slow} ) {
            sleep (1);
          }
          my $apiresult = $self->{themoviedb}->Movie_getInfo( $movieId );
          my $doc2 = ParseXml( \$apiresult );

          if (not defined ($doc2)) {
            w( $self->{Type} . ' failed to parse result.' );
            last;
          }

          # FIXME case insensitive match helps with names like "Guillermo del Toro"
          my @nodes = $doc2->findnodes( '/OpenSearchDescription/movies/movie/cast/person[@job=\'Director\' and @name=\'' . $director . '\']' );
          if( @nodes != 1 ){
            $candidate->unbindNode();
            d( "director '$director' not found, removing candidate" );
          }
        }
      }

      @candidates = $doc->findnodes( '/OpenSearchDescription/movies/movie' );
      if( @candidates != 1 ){
        d( 'search did not return a single best hit, ignoring' );
      } else {
        my $movieId = $doc->findvalue( '/OpenSearchDescription/movies/movie/id' );
        my $movieLanguage = $doc->findvalue( '/OpenSearchDescription/movies/movie/language' );
        my $movieTranslated = $doc->findvalue( '/OpenSearchDescription/movies/movie/translated' );

        $self->FillHash( $resultref, $movieId, $ceref );
      }
    }
  }else{
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
    $resultref = undef;
  }

  return( $resultref, $result );
}


1;
