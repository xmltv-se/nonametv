package NonameTV::Importer::ZDFinfo_http;

use strict;
use warnings;

=pod

Importer for data from ZDFinfo. 
One file per channel and week downloaded from their site.
The downloaded file is in xml-format.
Same format as DreiSat.

=cut

use DateTime;

use NonameTV::Log qw/d progress w error/;

use NonameTV::Importer::ZDF;

use base 'NonameTV::Importer::ZDF';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{ZDFProgrammdienstStation} = '22';

    w( 'The importer ZDFinfo_http is deprecated, consider moving your channels over to importer ZDF, ' .
       'but don\'t forget to adjust channel ids so you don\'t lose your augmenter rules. ' .
       'grabbber_info for ZDFinfo is \"22\".' );

    return $self;
}

1;
