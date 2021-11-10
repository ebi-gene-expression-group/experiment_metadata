#!/usr/bin/env perl
#

use strict;
use warnings;
use 5.10.0;

use Atlas::AtlasConfig::Reader qw( parseAtlasConfig );

my $xmlFilename = shift;
my $experimentConfig = parseAtlasConfig( $xmlFilename );
my $experimentType = $experimentConfig->get_atlas_experiment_type;

print $experimentType;
