package NonameTV::Importer::Combiner;

=pod

Combine several channels into one. Read data from xmltv-files downloaded
via http.

Configuration:
  - day is either 'all' or '<one>'
    with lower case english two letter day names (mo, tu, we, th, fr, sa, su)
    or numbers with 1 being monday
    see http://search.cpan.org/dist/DateTime-Event-Recurrence/lib/DateTime/Event/Recurrence.pm
  - time is either '<hhmm>-<hhmm>' in local time (FIXME which one??) or left empty for all day aka '0000-0000' (in local time!)

Todo:
  - where to store the time zone of each schedule?
    grabber_info looks like the best place for it

Bugs:
  - a 12 hour nonstop program with a channel switch every hour doesn't work

=cut

use strict;
use warnings;


my %channel_data;

=pod

Barnkanalen och Kunskapskanalen sams�nder via DVB-T.
Vad jag vet �r det aldrig n�gra �verlapp, s� jag
inkluderar alla program p� b�da kanalerna.

=cut

$channel_data{ "svtb-svt24.svt.se" } =
  {
    "svtb.svt.se" =>
      [
        {
          day => 'all',
        },
      ],
    "svt24.svt.se" =>
      [
        {
          day => 'all',
        },
      ],
  };

=pod

Viasat Nature/Crime och Nickelodeon sams�nder hos SPA.

=cut

$channel_data{ "viasat-nature-nick.spa.se" } =
  {
    "nature.viasat.se" =>
      [
        {
          day => 'all',
	  time => '1800-0000',
        },
      ],
    "nickelodeon.se" =>
      [
        {
          day => 'all',
	  time => '0600-1800',
        },
      ],
  };

=pod

ZDFneo / KI.KA switch on ZDFmobil

=cut

$channel_data{ "neokika.zdfmobil.de" } =
  {
    "kika.de" =>
      [
        {
          day => 'all',
	  time => '0600-2100',
        },
      ],
    "neo.zdf.de" =>
      [
        {
          day => 'all',
	  time => '2100-0600',
        },
      ],
  };

=pod

TV4 Film and TV4 Fakta is airing in different times on Boxer
TV4 Film:  Friday 21:00 - Monday 08:00
TV4 Fakta: Monday 08:00 - Friday 21:00

=cut

$channel_data{ "tv4film.boxer.se" } =
  {
    "film.tv4.se" =>
	[
          {
             day => 'all',
             time => '1800-0600',
          }
	],
  };

=pod

C More Sport/SF-Kanalen

=cut

$channel_data{ "sport-sf.cmore.se" } =
  {
    "sf-kanalen.cmore.se" =>
	[
	  {
	     day => 'mo',
	     time => '0100-1800',
	  },
	  {
             day => 'tu',
             time => '0100-1800',
          },
          {
             day => 'we',
             time => '0100-1800',
          },
          {
             day => 'th',
             time => '0100-1800',
          },
          {
             day => 'fr',
             time => '0100-1800',
          },
          {
             day => 'sa',
             time => '0100-1200',
          },
          {
             day => 'su',
             time => '0100-1200',
          },
	],
   "sport.cmore.se" =>
	[
          {
             day => 'mo',
             time => '1800-0100',
          },
          {
             day => 'tu',
             time => '1800-0100',
          },
          {
             day => 'we',
             time => '1800-0100',
          },
          {
             day => 'th',
             time => '1800-0100',
          },
          {
             day => 'fr',
             time => '1800-0100',
          },
          {
             day => 'sa',
             time => '1200-0100',
          },
          {
             day => 'su',
             time => '1200-0100',
          },
        ],
    };

=pod

ARTE / EinsExtra on ARD national mux from HR

=cut

$channel_data{ "arteeinsextra.ard.de" } =
  {
    "arte.de" =>
      [
        {
          day => 1,
	  time => '0000-0300',
        },
        {
          day => 1,
	  time => '1400-0300',
        },
        {
          day => 2,
	  time => '1400-0300',
        },
        {
          day => 3,
	  time => '1400-0300',
        },
        {
          day => 4,
	  time => '1400-0300',
        },
        {
          day => 5,
	  time => '1400-0300',
        },
        {
          day => 'sa',
	  time => '0800-0000',
        },
        {
          day => 'su',
        },
      ],
    "eins-extra.ard.de" =>
      [
        {
          day => 'mo',
	  time => '0300-1400',
        },
        {
          day => 'tu',
	  time => '0300-1400',
        },
        {
          day => 'we',
	  time => '0300-1400',
        },
        {
          day => 'th',
	  time => '0300-1400',
        },
        {
          day => 'fr',
	  time => '0300-1400',
        },
        {
          day => 'sa',
	  time => '0300-0800',
        },
      ],
  };

=pod

Nickelodeon Germany / Comedy Central. The share the same channel and do not overlap.

=cut

$channel_data{ "nickcc.mtvnetworks.de" } =
  {
    "nick.de" =>
      [
        {
          day => 'all',
        },
      ],
    "comedycentral.de" =>
      [
        {
          day => 'all',
        },
      ],
  };

$channel_data{ "ch.nickcc.mtvnetworks.de" } =
  {
    "nick.ch" =>
      [
        {
          day => 'all',
        },
      ],
    "comedycentral.ch" =>
      [
        {
          day => 'all',
        },
      ],
  };

=pod

NRK3 and NRK Super TV shares the same slot so the programmes dont overlap.

=cut

$channel_data{ "nrk3super.nrk.no" } =
  {
    "nrk3.nrk.no" =>
      [
        {
          day => 'all',
        },
      ],
    "supertv.nrk.no" =>
      [
        {
          day => 'all',
        },
      ],
  };


=pod

RBB Berlin

=cut

$channel_data{ "berl.rbb-online.de" } =
  {
    "rbb.rbb-online.de" =>
      [
        {
          day => 'all',
        },
      ],
    "rbbberl.rbb-online.de" =>
      [
        {
          day => 'all',
        },
      ],
  };

=pod

Nickelodeon DK 05:00-21:00, MTV Hits 21:00-05:00

=cut

$channel_data{ "nickdk-mtvhits.sat.viasat.dk" } =
  {
    "nickelodeon.dk" =>
      [
        {
          day => 'all',
          time => '0500-2100',
        },
      ],
    "hits.mtv.se" =>
      [
        {
          day => 'all',
          time => '2100-0500',
        },
      ],
  };

=pod

Nickelodeon NO 05:00-21:00, VH1 Classic 21:00-05:00

=cut

$channel_data{ "nickno-vh1classic.sat.viasat.no" } =
  {
    "nickelodeon.no" =>
      [
        {
          day => 'all',
          time => '0500-2100',
        },
      ],
    "classic.vh1.se" =>
      [
        {
          day => 'all',
          time => '2100-0500',
        },
      ],
  };

=pod

Disney Junior SE 06:00-19:00, Viasat Film Drama 19:00-06:00

=cut

$channel_data{ "disneyjuniorse-viasatfilmdramase.tvtogo.viasat.se" } =
  {
    "junior.disney.se" =>
      [
        {
          day => 'all',
          time => '0600-1900',
        },
      ],
    "drama.film.viasat.se" =>
      [
        {
          day => 'all',
          time => '1900-0600',
        },
      ],
  };

=pod

  Viasat Nature 06:00-00:00 - Playboy 00:00-05:00

=cut

$channel_data{ "nature-playboy.sat.viasat.se" } =
  {
    "nature-crime.viasat.se" =>
      [
        {
          day => 'all',
          time => '0600-0000',
        },
      ],
    "europe.playboytv.com" =>
      [
        {
          day => 'all',
          time => '0000-0500',
        },
      ],
  };

=pod

Nick Jr 06:00-18:00, VH1 18:00-06:00

=cut

$channel_data{ "nickjrse-vh1se.sat.viasat.se" } =
  {
    "nickjr.se" =>
      [
        {
          day => 'all',
          time => '0600-2000',
        },
      ],
    "vh1.se" =>
      [
        {
          day => 'all',
          time => '2000-0600',
        },
      ],
  };

=pod

CN 06:00-21:00, Disney XD 06:00-18:00.﻿

=cut

$channel_data{ "boomerang.boxer.se" } =
  {
    "boomerangtv.se" =>
      [
        {
          day => 'all',
          time => '0600-2100',
        },
      ]
  };

  $channel_data{ "disneyxd.boxer.se" } =
  {
    "xd.disneychannel.se" =>
      [
        {
          day => 'all',
          time => '0600-1800',
        },
      ]
  };

  $channel_data{ "livehdhitshd.cmore.boxer.se" } =
    {
      "livehd.cmore.se" =>
        [
          {
            day => 'mo',
            time => '0000-0700',
          },
          {
            day => 'mo',
            time => '1630-0000',
          },

          {
            day => 'tu',
            time => '0000-0030',
          },
          {
            day => 'tu',
            time => '1630-0000',
          },

          {
            day => 'we',
            time => '0000-0030',
          },
          {
            day => 'we',
            time => '1630-0000',
          },

          {
            day => 'th',
            time => '0000-0030',
          },
          {
            day => 'th',
            time => '1630-0000',
          },

          {
            day => 'fr',
            time => '0000-0030',
          },

          {
            day => 'sa',
            time => '0700-0000',
          },

          {
            day => 'su',
            time => '0000-0000',
          },
        ],
        "hitshd.cmore.se" =>
          [
            {
              day => 'mo',
              time => '0700-1630',
            },
            {
              day => 'tu',
              time => '0030-1630',
            },
            {
              day => 'we',
              time => '0030-1630',
            },
            {
              day => 'th',
              time => '0030-1630',
            },
            {
              day => 'fr',
              time => '0030-0000',
            },
            {
              day => 'sa',
              time => '0000-0700',
            },

          ]
    };

use DateTime;
use DateTime::Event::Recurrence;

use NonameTV::Importer::BaseDaily;

use NonameTV::Log qw/d p w/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{MaxDays} = 32 unless defined $self->{MaxDays};
    $self->{MaxDaysShort} = 2 unless defined $self->{MaxDaysShort};

    if( defined( $self->{UrlRoot} ) ) {
      w( 'UrlRoot is deprecated as we read directly from our database now.' );
    }

    $self->{OptionSpec} = [ qw/force-update verbose+ quiet+ short-grab/ ];
    $self->{OptionDefaults} = {
      'force-update' => 0,
      'verbose'      => 0,
      'quiet'        => 0,
      'short-grab'   => 0,
    };


    return $self;
}

sub Import
{
  my $self = shift;
  my( $p ) = @_;

  NonameTV::Log::SetVerbosity( $p->{verbose}, $p->{quiet} );

  my $maxdays = $p->{'short-grab'} ? $self->{MaxDaysShort} : $self->{MaxDays};

  my $ds = $self->{datastore};

  foreach my $data (@{$self->ListChannels()} ) {
    if( not exists( $channel_data{$data->{xmltvid} } ) )
    {
      die "Unknown channel '$data->{xmltvid}'";
    }

    if( $p->{'force-update'} and not $p->{'short-grab'} )
    {
      # Delete all data for this channel.
      my $deleted = $ds->ClearChannel( $data->{id} );
      p( "Deleted $deleted records for $data->{xmltvid}" );
    }

    my $start_dt = DateTime->today->subtract( days => 1 );

    my @source_channels = ();
    foreach my $chan (keys %{$channel_data{$data->{xmltvid}}})
    {
        push (@source_channels, '\'' . $chan . '\'');
    }
    my $source_xmltvids = join (', ', @source_channels);

    for( my $days = 0; $days <= $maxdays; $days++ )
    {
      my $dt = $start_dt->clone;
      $dt=$dt->add( days => $days );

      my $batch_id = $data->{xmltvid} . "_" . $dt->ymd('-');

      my $gotcontent = 0;
      my %prog;

      my ($res, $sth) = $ds->sa->Sql (
                      'SELECT MAX(b.last_update) AS last_update
                       FROM batches b, programs p, channels c
                       WHERE c.xmltvid IN (' .
                      $source_xmltvids .
                      ') AND c.id = p.channel_id
                       AND p.start_time >= ?
                       AND p.start_time < ?
                       AND p.batch_id=b.id;',
                      [$dt->datetime(), $dt->clone()->add (days => 1)->datetime()]);

      if (!$res) {
        die $sth->errstr;
      }
      my $source_last_update;
      my $row = $sth->fetchrow_hashref;
      if (defined ($row)) {
        $source_last_update = $row->{'last_update'};
      }
      my $row2 = $sth->fetchrow_hashref;
      $sth->finish();
      if (!defined ($source_last_update)) {
        $source_last_update = 0;
      }

      my $target_last_update = $ds->sa->Lookup ('batches', {'name' => $batch_id}, 'last_update');
      if (!defined ($target_last_update)) {
        $target_last_update = 0;
      }

      if ($source_last_update < $target_last_update) {
        p ('Source data last changed ' . $source_last_update . ' and target data last changed ' . $target_last_update . " => nothing to do, continuing.\n");
        next;
      } else {
        p ('Source data last changed ' . $source_last_update . ' and target data last changed ' . $target_last_update . " => generating target batch.\n");
      }

      foreach my $chan (keys %{$channel_data{$data->{xmltvid}}})
      {
        my $curr_batch = $chan . "_" . $dt->ymd('-');
        my $content = $ds->ParsePrograms( $curr_batch );

        $prog{$chan} = $content;
        $gotcontent = 1 if $content;
      }

      if( $gotcontent )
      {
        p( "$batch_id: Processing data" );

        my $progs = $self->BuildDay( $batch_id, \%prog,
                                     $channel_data{$data->{xmltvid}}, $data );
      }
      else
      {
        w( "$batch_id: Failed to fetch data" );
      }
    }
  }
}

sub BuildDay
{
  my $self = shift;
  my( $batch_id, $prog, $sched, $chd ) = @_;

  my $ds =$self->{datastore};

  my @progs;

  my( $channel, $date ) = split( /_/, $batch_id );

  $ds->StartBatch( $batch_id );

  my $date_dt = date2dt( $date );

  foreach my $subch (keys %{$sched})
  {
    # build spanset of schedule times
    my $sspan = DateTime::SpanSet->empty_set ();

    foreach my $span (@{$sched->{$subch}}) {
      my $weekly;
      if (($span->{day}) && ($span->{day} ne 'all')) {
        d( 'handling specific days schedule' );
        $weekly = DateTime::Event::Recurrence->weekly (
          days => $span->{day},
        );
      } else {
        # progress ("handling all days schedule");
        $weekly = DateTime::Event::Recurrence->daily;
      }

      my $iter = $weekly->iterator (
        start => $date_dt->clone->add (days => -1),
        end => $date_dt->clone->add (days => 1)
      );
      while ( my $date_dt = $iter->next ) {
        # progress ("adding schedules for $date_dt to spanset");
        my $sstart_dt;
        my $sstop_dt;

        if( defined( $span->{time} ) ) {
          my( $sstart, $sstop ) = split( /-/, $span->{time} );

	  $sstart_dt = changetime( $date_dt, $sstart );
	  $sstop_dt = changetime( $date_dt, $sstop );
	  if( $sstop_dt lt $sstart_dt ) {
	    $sstop_dt->add( days => 1 );
          }
        } else {
	  $sstart_dt = changetime( $date_dt, '0000' );
	  $sstop_dt = $sstart_dt->clone->add ( days=> 1);
        }

        # progress ("span from $sstart_dt until $sstop_dt");

        $sspan = $sspan->union (
          DateTime::SpanSet->from_spans (
            spans => [DateTime::Span->from_datetimes (
              start => $sstart_dt,
              before => $sstop_dt
            )]
          )
        );
      }
    }

    $sspan->set_time_zone ("Europe/Berlin");
    $sspan->set_time_zone ("UTC");

    # now that we have a spanset containing all spans
    # that should be included it gets easy

    foreach my $e (@{$prog->{$subch}}) {
      # programme span
      my $pspan = DateTime::Span->from_datetimes (
        start => $e->{start_dt},
        before => $e->{stop_dt}
      );
      $pspan->set_time_zone ("UTC");

      # continue with next programme if there is no match
      next if (!$sspan->intersects ($pspan));

      # copy programme
      my %e2 = %{$e};
      # always update the time
      my $ptspan = $sspan->intersection( $pspan );
      $e2{start_dt} = $ptspan->min;
      $e2{stop_dt} = $ptspan->max;

      # partial programme
      if (!$sspan->contains ($pspan)) {
        $e2{title} = "(P) " . $e2{title};
      }

      $e2{start_time} = $e2{start_dt}->ymd('-') . " " . $e2{start_dt}->hms(':');
      delete $e2{start_dt};
      $e2{end_time} = $e2{stop_dt}->ymd('-') . " " . $e2{stop_dt}->hms(':');
      delete $e2{stop_dt};
      d ("match $e2{title} at $e2{start_time} or " . $pspan->min);

      $e2{channel_id} = $chd->{id};

      $ds->AddProgrammeRaw( \%e2 );
    }
  }
  $ds->EndBatch( 1 );
}

sub FetchDataFromSite
{
  return( '', undef );
}

sub date2dt {
  my( $date ) = @_;

  my( $year, $month, $day ) = split( '-', $date );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          );
}

sub changetime {
  my( $dt, $time ) = @_;

  my( $hour, $minute ) = ($time =~ m/(\d+)(\d\d)/);

  my $dt2 = $dt->clone();

  $dt2->set( hour => $hour,
	    minute => $minute );

  return $dt2;
}

1;
