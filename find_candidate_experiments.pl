#!/usr/bin/env perl
#

=head1 NAME

find_candidate_experiments.pl - Search ArrayExpress for candidates to add to Expression Atlas.

=head1 DESCRIPTION

This script searches ArrayExpress for experiments that are candidates to be
added to Expression Atlas. It must be passed an "analysis type" (differential
or baseline) to assess suitability for, and a species to search for in
experiments. It is intended to be run on an "ad hoc" basis. It creates a report
containing accessions of experiments it has deemed worthy of further
investigation by a curator, and others that it decided are not candidates.

=head1 SYNOPSIS

find_candidate_experiments.pl --type baseline --species "Zea mays"

find_candidate_experiments.pl -t differential -s "Tetraodon nigroviridis" -a atlas_array_designs.txt

find_candidate_experiments.pl -t differential -d "Homo sapiens" -p "disease,organism part"

=head1 OPTIONS

=over 2

=item -t --type

Required. Type of analysis to assess suitability for. Must be one of "baseline" or "differential".

=item -o --outfile

Required. Filename for results of search.

=item -s --species

Optional. Latin name of species to search for, e.g. "Homo sapiens".

=item -p --properties

Optional. Specify property name(s) (Characteristics and or Factor Values) to
search for. If specifying more than one, separate with commas and no spaces.
Put multi-word properties in quotes.

=item -h --help

Optional. Print a helpful message.

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas.ebi.ac.uk>

=cut

use strict;
use warnings;

use Pod::Usage;
use Atlas::ExptFinder::Baseline;
use Atlas::ExptFinder::Differential;
use Log::Log4perl qw( :easy );
use Getopt::Long;
use Config::YAML;

$| = 1;

# Get command line arguments.
my $args = parse_args();

# Start a logger.
Log::Log4perl->easy_init (
    {
        level   => $INFO,
        layout  => '%-5p - %m%n',
        file    => "STDOUT",
    }
);
my $logger = Log::Log4perl::get_logger;

# Variable for new searcher.
my $searcher;

# Create the appropriate type of searcher.
if( $args->{ "analysis_type" } eq "baseline" ) {
	$searcher = Atlas::ExptFinder::Baseline->new();
}
elsif( $args->{ "analysis_type" } eq "differential" ) {

	$searcher = Atlas::ExptFinder::Differential->new( );
}
else {
	my $message = "Unknown analysis type: " . $args->{ "analysis_type" };

	$logger->logdie(
		$message
	);
}

# Do the search.
$logger->info( 
    "Searching ArrayExpress for " 
	. $args->{ "analysis_type" }
    . " candidates."
);

if( $args->{ "species" } ) {

    my @splitSpecies = split ",", $args->{ "species" };

    my $speciesString = "\"" . join( "\" or \"", @splitSpecies ) . "\"";

    $logger->info(
        "Limiting search to experiments with species matching $speciesString."
    );

    $searcher->set_species_list( \@splitSpecies );
}

if( $args->{ "properties" } ) {
    
    my @splitProperties = split ",", $args->{ "properties" };

    my $propertyString = "\"" . join( "\" or \"", @splitProperties ) . "\"";

    $logger->info(
        "Limiting search to experiments with properties matching $propertyString.",
    );

    $searcher->set_user_properties( \@splitProperties );
}

# Search for candidates.
$searcher->find_candidates;

# Write the candidates (if any) to a file.
$searcher->write_candidates_to_file( $args->{ "outfile" } );

# end
#####


sub parse_args {

	my %args;

	my $want_help;

	# Possible analysis types.
	my @allowed_analysis_types = qw(
		baseline
		differential
	);

	GetOptions(
		"h|help"	        => \$want_help,
		"t|type=s"	        => \$args{ "analysis_type" },
		"s|species=s"	    => \$args{ "species" },
        "p|properties=s"    => \$args{ "properties" },
        #    "o|outfile=s"       => \$args{ "outfile" }
	);

	if( $want_help ) {
		pod2usage(
			-exitval => 255,
			-output => \*STDOUT,
			-verbose => 1
		);
	}

	# We must have an analysis type to assess suitability for AND a species to
	# search for.
	unless( $args{ "analysis_type" } ) {
		pod2usage(
			-message => "You must specify an analysis type.\n",
			-exitval => 255,
			-output => \*STDOUT,
			-verbose => 1
		);
	}

	# Check that the analysis type is one of the allowed ones.
	unless( grep $_ eq $args{ "analysis_type" }, @allowed_analysis_types ) {
		pod2usage(
			-message => "\"" . $args{ "analysis_type" } ."\" is not an allowed analysis type.\n",
			-exitval => 255,
			-output => \*STDOUT,
			-verbose => 1
		);
	}
    
	return \%args;
}

