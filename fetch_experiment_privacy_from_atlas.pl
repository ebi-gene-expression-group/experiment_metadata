#!/usr/bin/env perl

use strict;
use warnings;

use 5.10.0;

use Atlas::AtlasAdmin;

my $api = Atlas::AtlasAdmin->new;

my %privates = $api->fetch_property_for_list("isPrivate");

while ( my ($accession, $isPrivate) = each %privates ) {
    say $accession, "\t", $isPrivate ? "true" : "false";
}
