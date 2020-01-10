#!/usr/bin/env perl
#
=pod

=head1 NAME

create_pivotal_stories.pl - automatically create stories in AE2/Atlas Curation Pivotal Tracker.

=head1 SYNOPSIS

create_pivotal_stories.pl -n "Load human experiments" -d my_description_file.txt -l cttv,eurocan -a accessions_file.txt -t ArrayExpress -p nd8e2nfd9w0vi2

=head1 DESCRIPTION

This script is for automatic creation of stories in the AE2/Atlas Curation
Pivotal Tracker (https://www.pivotaltracker.com/n/projects/1223494). It reads a
file containing ArrayExpress accessions, and creates stories containing these
accessions in batches of eight per story. It also requires story name,
description, and a user's Pivotal API token. Optionally, it can also be passed
a comma-separated list of labels to add to each story.

=head1 OPTIONS

=over 2

=item -n --name

Required. A name for the story, in quotes if there are spaces in the name.

=item -d --description_file

Required. Name of a text file containing the text to be added to the start of
the description of every story created.

=item -a --accessions_file

Required. Name of a text file containing accessions, one per line.

=item -t --type

Required. Accession type i.e. the database the study accessions came from. Either ArrayExpress or ENA.

=item -p --pivotal_token

Required. Your Pivotal API token. Find yours on https://www.pivotaltracker.com/profile

=item -l --labels

Optional. Comma separated list of labels to be added to every story.

=item -i --ignore

Optional. Ignore that an experiment has already been curated. E.g. if some
re-curation is needed for a batch of experiments, use this flag.

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut

use strict;
use warnings;
use 5.10.0;

use Config::YAML;
use Data::Dumper;
use File::Spec;
use Getopt::Long;
use JSON::XS;
use JSON::Parse qw( parse_json );
use Log::Log4perl qw( :easy );
use Pod::Usage;

use Atlas::Common qw(
    create_atlas_site_config
);

$| = 1;

my $args = parse_args();

Log::Log4perl->easy_init(
    {
        level   => $args->{ "debug" } ? $DEBUG : $INFO,
        layout  => '%-5p - %m%n',
        file    => "STDOUT",
    }
);

my $logger = Log::Log4perl::get_logger;

my $atlasSiteConfig = create_atlas_site_config;

my $atlasProdDir = $ENV{ "ATLAS_PROD" };
unless( $atlasProdDir ) {
    $logger->logdie( "ATLAS_PROD environment variable is not defined. Cannot locate YAML file containing accessions of already-curated experiments." );
}

my $atlasCuratedAccsFile = File::Spec->catfile( $atlasProdDir, $atlasSiteConfig->get_atlas_curated_accessions_file );

# Ensure that we have write permission for the cache file.
unless( -w $atlasCuratedAccsFile ) {
    $logger->logdie( "Cannot write to $atlasCuratedAccsFile -- will not be able to record accessions added to Pivotal tickets." );
}

$logger->info( "Reading accessions of experiments that have already been submitted for curation from $atlasCuratedAccsFile..." );
my $atlasCuratedAccs = Config::YAML->new( config => $atlasCuratedAccsFile );
$logger->info( "Successfully read accessions." );

$logger->info( "Reading story description from ", $args->{ "story_description_file" }, " ..." );
my $storyDescriptionStart = read_story_description( $args->{ "story_description_file" } );
$logger->info( "Successfully read story description." );

my $accessions = {};

if( $args->{ "accession_type" } eq "ArrayExpress" ) {
    $logger->info( "Reading ArrayExpress accessions from ", $args->{ "accessions_file" }, " ..." );
    $accessions = read_arrayexpress_accessions( $args->{ "accessions_file" } );
    $logger->info( "Successfully read ArrayExpress accessions." );
}
elsif( $args->{ "accession_type" } eq "ENA" ) {
    $logger->info( "Reading ENA accessions from ", $args->{ "accessions_file" }, " ..." );
    $accessions = read_ena_accessions( $args->{ "accessions_file" } );
    $logger->info( "Successfully read ENA accessions." );
}

unless( $args->{ "ignore" } ) {
    # Remove accessions that have already been curated
    $accessions = remove_already_curated_accessions( $args->{ "accession_type" }, $accessions, $atlasCuratedAccs );
}

unless( keys %{ $accessions } ) {
    $logger->info( "All requested accessions have already been curated. Will not create any new Pivotal stories." );
    exit;
}

my $storyAttributes = {
    "name" => $args->{ "story_name" },
    "estimate" => 8,
    "story_type" => "feature",
};

# Add labels if there are any.
if( $args->{ "story_labels" } ) {
    my @labels = split ",", $args->{ "story_labels" };
    $storyAttributes->{ "labels" } = \@labels;
}


$logger->info( "Creating stories..." );

my @accsArray = keys %{ $accessions };

# Process accessions in batches of eight. This also handles the remainder if
# total number of accessions % 8.
while( my @storyAccessions = splice( @accsArray, 0, 8 ) ) {
    
    my $accString = join "\n", @storyAccessions;

    my $storyDesc = $storyDescriptionStart . "\n\n" . $accString;

    $storyAttributes->{ "description" } = $storyDesc;

    if( @storyAccessions == 4 ) { $storyAttributes->{ "estimate" } = 5; }
    
    create_story( $storyAttributes, $args->{ "pivotal_token" } );

    # If the story was created successfully, add the accessions to the cache
    # and write it. We write every time we create a new story. This is because,
    # if we have a large number of experiments to submit, it's more likely that
    # the process could die after having created some stories. If we only wrote
    # the cache to the YAML at the very end of the script run, if would be
    # harder to find out which accessions on our list had been submitted and
    # which hadn't.
    unless( $args->{ "ignore" } ) {
        add_accessions_to_cache( $args->{ "accession_type" }, \@storyAccessions, $atlasCuratedAccs );
    }
}


# Read the commandline arguments.
sub parse_args {

    my %args;

    my $want_help;

    GetOptions(
        "h|help"        => \$want_help,
        "n|name=s"      => \$args{ "story_name" },
        "l|labels=s"    => \$args{ "story_labels" },
        "d|description_file=s"    => \$args{ "story_description_file" },
        "a|accessions_file=s"     => \$args{ "accessions_file" },
        "t|type=s"                => \$args{ "accession_type" },
        "p|pivotal_token=s"       => \$args{ "pivotal_token" },
        "i|ignore"      => \$args{ "ignore" }
    );

    if( $want_help ) {
        pod2usage(
            -exitval    => 255,
            -output     => \*STDOUT,
            -verbose    => 1
        );
    }

    unless( 
        $args{ "story_name" } &&
        $args{ "story_description_file" } &&
        $args{ "accessions_file" } &&
        $args{ "accession_type" } &&
        $args{ "pivotal_token" }
    ) {
        pod2usage(
            -message    => "You must supply story name, file containing story description start, file containing ArrayExpress accessions, accession type and your Pivotal API token\n",
            -exitval    => 255,
            -output     => \*STDOUT,
            -verbose    => 1
        );
    }

    unless( $args{ "accession_type" } eq "ArrayExpress" || $args{ "accession_type" } eq "ENA" ) {
        pod2usage(
            -message    => "Accession type must be either ArrayExpress or ENA\n",
            -exitval    => 255,
            -output     => \*STDOUT,
            -verbose    => 1
        );
    }

    return \%args;
}


# Read in the description for each Pivotal story from the supplied file into a
# scalar.
sub read_story_description {

    my ( $storyDescriptionFile ) = @_;

    my $storyDescriptionStart;

    open( my $fh, "<", $storyDescriptionFile ) 
        or $logger->logdie( "Cannot open $storyDescriptionFile for reading: $!\n" );

    while( defined( my $line = <$fh> ) ) { $storyDescriptionStart .= $line; }

    unless( $storyDescriptionStart ) {
        $logger->logdie( "No story description found in $storyDescriptionFile." );
    }

    #return quotemeta( $storyDescriptionStart );
    return $storyDescriptionStart;
}


# Read the ArrayExpress accessions from the supplied file into a hash.
sub read_arrayexpress_accessions {

    my ( $aeAccsFile ) = @_;

    open( my $fh, "<", $aeAccsFile ) 
        or $logger->logdie( "Cannot open $aeAccsFile for reading: $!\n" );

    my $aeAccessions = {};

    while( defined( my $line = <$fh> ) ) {

        chomp $line;

        ( my $acc = $line ) =~ s/.*(E-\w{4}-\d+).*/$1/;

        unless( $acc ) { next; }

        $aeAccessions->{ $acc } = 1;
    }

    close $fh;

    unless( keys %{ $aeAccessions } ) {
        $logger->logdie( "No ArrayExpress accessions were found in $aeAccsFile" );
    }

    return $aeAccessions;
}

# Read ENA accessions from the supplied file into a hash.
sub read_ena_accessions {

    my ( $accsFile ) = @_;
    
    open( my $fh, "<", $accsFile )
        or $logger->logdie( "Cannot open $accsFile for reading: $!\n" );

    my $enaAccessions = {};

    while( defined( my $line = <$fh> ) ) {

        chomp $line;

        ( my $acc = $line ) =~ s/.*(\wRP\d+).*/$1/;

        unless( $acc ) { next; }

        $enaAccessions->{ $acc } = 1;
    }

    close $fh;

    unless( keys %{ $enaAccessions } ) {
        $logger->logdie( "No ENA accessions found in $accsFile" );
    }

    return $enaAccessions;
}


# Remove accessions that have already been submitted for curation from the list
# of accessions to be submitted.
sub remove_already_curated_accessions {

    my ( $accessionType, $accessions, $atlasCuratedAccs ) = @_;
    
    if( $accessionType eq "ArrayExpress" ) {
        my $aeAccsWithSRA = $atlasCuratedAccs->get_arrayexpress_accessions_with_sra;
        my $aeAccsNoSRA = $atlasCuratedAccs->get_arrayexpress_accessions_without_sra;

        my %aeAccsNoSRA_hash = map { $_ => 1 } @{ $aeAccsNoSRA };

        foreach my $aeAcc ( sort keys %{ $accessions } ) {
            
            # If the accession is already in the cache, it's already been curated.
            if( $aeAccsWithSRA->{ $aeAcc } || $aeAccsNoSRA_hash{ $aeAcc } ) {

                $logger->info( "$aeAcc has already been curated, not including it in Pivotal stories." );

                delete( $accessions->{ $aeAcc } );
            }
        }

        return $accessions;
    }
    elsif( $accessionType eq "ENA" ) {

        my $aeAccsWithSRA = $atlasCuratedAccs->get_arrayexpress_accessions_with_sra;
        my $sraAccsNoAE = $atlasCuratedAccs->get_sra_accessions_without_arrayexpress;

        my %sraAccsNoAE_hash = map { $_ => 1 } @{ $sraAccsNoAE };

        my %sraAccsWithAE = map { $_ => 1 } ( values %{ $aeAccsWithSRA } );

        foreach my $acc ( sort keys %{ $accessions } ) {

            if( $sraAccsNoAE_hash{ $acc } || $sraAccsWithAE{ $acc } ) {

                $logger->info( "$acc has already been curated, not including it in Pivotal stories." );

                delete( $accessions->{ $acc } );
            }
        }

        return $accessions;
    }
}


# Given a hash containing the story attributes (name, description, points,
# label(s)...) and a user's Pivotal API token, create new stories in Pivotal
# via API calls.
sub create_story {

    my ( $storyAttributes, $pivotalToken ) = @_;

    my $jsonConverter = JSON::XS->new->utf8;
    
    # Create JSON representing the story attributes.
    my $json = $jsonConverter->encode( $storyAttributes );

    # Construct the command for cURL.
    my $curlCommand = "curl -s -S -X POST -H \"X-TrackerToken: $pivotalToken\" -H \"Content-Type: application/json\" -d '$json' \"https://www.pivotaltracker.com/services/v5/projects/1223494/stories\"";

    # Run the cURL command and store the JSON response.
    my $respJSON = `$curlCommand`;

    # Parse the JSON response from Pivotal into a hash.
    my $resp = parse_json( $respJSON );

    # Get the URL of the newly created story.
    my $storyURL = $resp->{ "url" };

    # If we didn't get a story URL, fail.
    unless( $storyURL ) {
        
        $logger->error( "Could not create story. The following response was received from Pivotal:" );

        say Dumper( $resp );

        $logger->logdie( "Cannot continue." );
    }
    
    # Otherwise, log the URL of the new story.
    $logger->info( "Story created: $storyURL" );
}


# Add accessions of experiments that have been submitted for curation via a new
# Pivotal story to the cache and write the YAML file.
sub add_accessions_to_cache {

    my ( $accessionType, $storyAccessions, $atlasCuratedAccs ) = @_;
    
    if( $accessionType eq "ArrayExpress" ) {
        # Add them to list without SRA accessions, since we don't have SRA
        # accessions for these.
        my $aeAccsNoSRA = $atlasCuratedAccs->get_arrayexpress_accessions_without_sra;

        push @{ $aeAccsNoSRA }, @{ $storyAccessions };

        my @sortedAccs = sort @{ $aeAccsNoSRA };

        $atlasCuratedAccs->set_arrayexpress_accessions_without_sra( \@sortedAccs );
    }
    elsif( $accessionType eq "ENA" ) {
        # Add them to the cache.
        my $sraAccsNoAE = $atlasCuratedAccs->get_sra_accessions_without_arrayexpress;

        push @{ $sraAccsNoAE }, @{ $storyAccessions };

        my @sortedAccs = sort @{ $sraAccsNoAE };

        $atlasCuratedAccs->set_sra_accessions_without_arrayexpress( \@sortedAccs );
    }

    $atlasCuratedAccs->write;
}
