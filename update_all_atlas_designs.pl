#!/usr/bin/env perl
#

use strict;
use warnings;

use 5.10.0;

use Log::Log4perl qw( :easy );
use Atlas::Admin;

my $logger = Log::Log4perl::get_logger;

$logger->info( "Updating all experiment designs ..." );

Atlas::Admin -> new -> perform_operation("all", "update_design");

$logger->info( "All experiment designs updated successfully." );
