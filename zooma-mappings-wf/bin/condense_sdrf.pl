#!/usr/bin/env perl
#
=pod

=head1 NAME

condense_sdrf.pl - get the characteristics and factors from an experiment and list them.

=head1 SYNOPSIS

condense_sdrf.pl -e E-MTAB-2512

=head1 DESCRIPTION

This script takes an ArrayExpress experiment accession and parses the SDRF file
from the load directory to extract the characteristic and factor values, which
it writes to a file called <experiment accession>-condensed-sdrf.tsv

=head1 OPTIONS

=over 2

=item -b --bioreps

Optional. Include IDs for biological replicates, based on the "Comment[
technical replicate group ]" column (if any).

=item -d --debug

Optional. Print de-bugging messages. WARNING -- this creates a lot of output.

=item -e --experiment

Required. ArrayExpress experiment accession of experiment.

=item -fi --fileInput

Optional. Provide an IDF file explicitly, rather than inferring it from the identifier.

=item -f --factors

Optional. Path to Factors XML config (e.g. E-MTAB-1829-factors.xml)

=item -i --idf

Optional. Copy IDF file from ArrayExpress load directory to output directory.

=item -s --copySDRF

Optional. Copy SDRF file from the IDF determined location to the output directory.

=item -o --outdir

Optional. Destination directory for output file(s). Will use current working
directory if not supplied.

=item -m --mergeTechReplicates

Optional. Flag to merge technical replicates in the final output, using the unmodified biosamples (no t appended to technical replicates).

=item -sc --singlecell

Optional. Single cell experiments specific

=item -z --zooma

Optional. Map terms to ontology using Zooma.

=item -x --zoomaExclusions

Optional. Path to a zooma exclusions file.

=item -h --help

Optional. Print this help message.

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut


use strict;
use warnings;
use 5.10.0;

use Getopt::Long;
use Pod::Usage;
use Cwd qw();
use File::Spec;
use Log::Log4perl qw( :easy );
use Config::YAML;
use File::Spec;
use IO::Handle;
use Bio::MAGETAB::Util::Reader;
use Atlas::Assay;
use Atlas::AtlasAssayFactory;
use Atlas::Common qw(
    make_ae_idf_path
    create_atlas_site_config
    make_idf_path
    get_idfFile_path
    get_singlecell_idfFile_path
);
use Atlas::ZoomaClient;
use Atlas::ZoomaClient::MappingResult;
use Atlas::AtlasConfig::Reader qw( parseAtlasFactors );
use File::Basename;
use File::Spec;
use Data::Dumper;

$| = 1;

binmode STDOUT, ":utf8";

# Absolute directory path to the file storage
my $abs_path = dirname(File::Spec->rel2abs(__FILE__));
my $args = parse_args();

# Initialise logger.
Log::Log4perl->easy_init (
    {
        level   => $args->{ "debug" } ? $DEBUG : $INFO,
        layout  => '%-5p - %m%n',
        file    => "STDOUT",
    }
);
my $logger = Log::Log4perl::get_logger;
my $expAcc = $args->{ "experiment_accession" };

# Log about some of the options received.
$logger->info("Detected -z option, mapping terms to ontology using Zooma.") if( $args->{ "zooma" } );
$logger->info("Detected -i option, importing IDF file from ArrayExpress load directory.") if( $args->{ "idf" } );
$logger->info("Detected -b option, adding IDs for biological replicates if available.") if( $args->{ "bioreps" } );
$logger->info("Debugging ON.") if( $args->{ "debug" } );
$logger->info("Detected -sc single cell option. Will import IDF from single cell load directory.") if( $args->{ "single_cell" } );
$logger->info("Detected -m option, merging technical replicates, using the unmodified biosamples (no t appended to technical replicates).") if ($args->{"mergeTechReplicates"});


my $idfFile;
# Import IDF path required if not specified.

if( $args->{ "fileInput" } ) {
    $idfFile = $args->{ "fileInput" };
    die "Supplied IDF file $idfFile does not exist." unless -e $idfFile;
}
else {
    if( $args->{ "single_cell" } ) {
      $idfFile = get_singlecell_idfFile_path( $expAcc );
    }
    else {
      $idfFile = get_idfFile_path( $expAcc );
    }
}

# Import IDF if required.
if( $args->{ "idf" } ) {
    copy_idf_from_ae( $args, $idfFile );
}

$logger->info( "Reading MAGETAB from $idfFile ..." );
# Read MAGE-TAB.
my $reader = Bio::MAGETAB::Util::Reader->new( {
        idf                 => $idfFile,
        relaxed_parser      => 1,
        ignore_datafiles    => 1
    });

my ($investigation, $magetab) = $reader->parse;
$logger->info( "Successfully read MAGETAB." );

if( $args->{ "copySDRF" } ) {
    copy_sdrf_to_output_dir($investigation, $args->{ "output_directory" }, $idfFile);
}

$logger->info( "Merging technical replicates if available.") if( $args->{ "mergeTechReplicates" } );
my $atlasAssays = create_all_atlas_assays( $magetab, $args->{ "mergeTechReplicates" } );
$logger->debug( Dumper( $atlasAssays ) );

# If we have a baseline Atlas experiment, and have been passed the factors XML
# filename as an argument, read it and re-arrange the assay factors if
# necessary.
if( $args->{ "factors_file" } ) {
    $logger->debug(
        "Ensuring assay factors match those found in ",
        $args->{ "factors_file" }
    );
    $atlasAssays = check_factors( $atlasAssays, $args->{ "factors_file" } );
}

# Go through assays and collect the unique property type-value pairs.
$logger->info( "Collecting all properties and their values from MAGE-TAB..." );
my $allPropertiesAssays = get_all_properties_for_assays( $atlasAssays );
$logger->info( "Successfully collected all properties and values." );

# Hash to save automatic ontology mappings for property type-value pairs.
# Only populated if we were passed the -z option.
my $automaticMappings = {};
if( $args->{ "zooma" } ) {
    $automaticMappings = run_zooma_mapping( $args, $allPropertiesAssays );
}

# Write the condensed SDRF.
# Create the filename.
my $outputFilename = File::Spec->catfile( $args->{ "output_directory" }, $expAcc . ".condensed-sdrf.tsv" );

# Open the output file for writing.
open( my $fh, ">:encoding(UTF-8)", $outputFilename ) or die( "ERROR - Cannot open $outputFilename for writing: $!\n" );
$logger->info( "Condensing SDRF to $outputFilename ..." );

# Go through the assays and write their annotations to the file.
foreach my $assayName ( sort keys %{ $atlasAssays } ) {
    my $atlasAssay = $atlasAssays->{ $assayName };
    my $characteristicsLines = _make_assay_lines(
        $expAcc,
        $atlasAssay,
        $atlasAssay->get_characteristics,
        "characteristic",
        $automaticMappings,
        $args->{ "bioreps" }
    );
    foreach my $line ( @{ $characteristicsLines } ) {
        say $fh $line;
    }
    if( $atlasAssay->has_factors ) {
        my $factorLines = _make_assay_lines(
            $expAcc,
            $atlasAssay,
            $atlasAssay->get_factors,
            "factor",
            $automaticMappings,
            $args->{ "bioreps" }
        );
        foreach my $line ( @{ $factorLines } ) {
            say $fh $line;
        }
    }
}

close $fh;
$logger->info( "Successfully condensed SDRF." );


# Subroutines

# Get commandline arguments.
sub parse_args {
    my %args;
    my $want_help;
    GetOptions(
        "h|help"            => \$want_help,
        "e|experiment=s"    => \$args{ "experiment_accession" },
        "o|outdir=s"        => \$args{ "output_directory" },
        "z|zooma"           => \$args{ "zooma" },
        "x|zoomaExclusions=s" => \$args{ "zooma_exclusions_path" },
        "i|idf"             => \$args{ "idf" },
        "s|copySDRF"        => \$args{"copySDRF"},
        "f|factors=s"       => \$args{ "factors_file" },
        "b|bioreps"         => \$args{ "bioreps" },
        "d|debug"           => \$args{ "debug" },
        "sc|singlecell"     => \$args{ "single_cell" },
        "fi|fileInput=s"      => \$args{ "fileInput" },
        "m|mergeTechReplicates" => \$args{ "mergeTechReplicates" }
    );
    unless( $args{ "experiment_accession" } ) {
        pod2usage(
            -message => "You must specify an experiment accession.\n",
            -exitval => 255,
            -output => \*STDOUT,
            -verbose => 1,
        );
    }
    unless( $args{ "experiment_accession" } =~ /^E-\w{4}-\d+$/ ) {
        pod2usage(
            -message => "\"" . $args{ "experiment_accession" } . "\" does not look like an ArrayExpress experiment accession.\n",
            -exitval => 255,
            -output => \*STDOUT,
            -verbose => 1,
        );
    }
    unless($args{ "output_directory" }) {
        print "WARN  - No output directory specified, will write output files in ", Cwd::cwd(), "\n";
        $args{ "output_directory" } = Cwd::cwd();
    }
    unless($args{ "zooma_exclusions_path" }) {
        my $defaultExclusionsFile="$abs_path/../supporting_files/zooma_exclusions.yml";
        print "Using default exclusions file path of $defaultExclusionsFile\n";
        $args{ "zooma_exclusions_path" } = $defaultExclusionsFile ;
    }

    # If one was specified, check that it's writable and die if not.
    unless(-w $args{ "output_directory" }) {
        pod2usage(
            -message => $args{ "output_directory" }. " is not writable or does not exist.\n",
            -exitval => 255,
            -output => \*STDOUT,
            -verbose => 1,
        );
    }
    return \%args;
}


# Copy the IDF from from the ArrayExpress load directory into the target output
# directory.
sub copy_idf_from_ae {
    my ( $args, $idfFile ) = @_;
    $logger->info( "Copying IDF from $idfFile ..." );
    my $outputDir = $args->{ "output_directory" };
    `cp $idfFile $outputDir`;
    unless( $? ) {
        $logger->info( "Successfully copied IDF." );
    }
    else {
        $logger->logdie( "Could not copy IDF: $!" );
    }
}

sub copy_sdrf_to_output_dir {
    my ( $investigation, $output_dir, $idf_abs_path ) = @_;
    foreach my $sdrf ( @{ $investigation->get_sdrfs() } ) {
        my $filename = $sdrf->get_uri()->file();
        if( !File::Spec->file_name_is_absolute( $filename ) ) {
            # append IDF path
            my $dir = dirname($idf_abs_path);
            $filename = File::Spec->catfile( $dir, $filename );
        } 
        `cp $filename $output_dir`;
        unless( $? ) {
            $logger->info( "Successfully copied SDRF." );
        }
        else {
            $logger->logdie( "Could not copy SDRF: $!" );
        }
    }
}

sub create_all_atlas_assays {
    my ( $magetab, $mergeTechReplicates ) = @_;
    # Create a relaxed AtlasAssayFactory.
    my $atlasAssayFactory = Atlas::AtlasAssayFactory->new( strict => 0 );
    # Empty array for Atlas::Assay objects.
    my $allAtlasAssays = {};
    foreach my $magetabAssay ( $magetab->get_assays ) {
        my $doNotModifyTechRepGroup = $mergeTechReplicates ? 1 : 0;
        my $atlasAssays = $atlasAssayFactory->create_atlas_assays( $magetabAssay, $doNotModifyTechRepGroup );
        # As long as we got something back from the AtlasAssayFactory, add it
        # to the array.
        if( $atlasAssays ) {
            foreach my $atlasAssay ( @{ $atlasAssays } ) {
              # If merging technical replicates flag is set and the assay has
              # technical replicates set, then merge entries based on the technical replicate group.
              if( $mergeTechReplicates && $atlasAssay->has_technical_replicate_group() ) {
                $atlasAssay->set_name($atlasAssay->get_technical_replicate_group())
              }
              $allAtlasAssays->{ $atlasAssay->get_name } = $atlasAssay;
            }
        }
    }

    # If we got any assays, return them.
    if( keys %{ $allAtlasAssays } ) {
        return $allAtlasAssays;
    }
    # Otherwise, die because we can't do anything without any assays.
    else {
        $logger->logdie(
            "No suitable assays found in SDRF."
        );
    }
}


# Check assay factors against those in factors XML file, and adjust as
# necessary.
sub check_factors {
    my ( $atlasAssays, $factorsFilename ) = @_;
    $logger->info(
        "Checking factors against factors XML config: ",
        $factorsFilename,
        " ..."
    );

    # Read in the factors config.
    my $factorsConfig = parseAtlasFactors( $factorsFilename );
    my $configFactorTypes = {};
    # If there are menu filter factor types (i.e. multi-factor experiments),
    # can just use these as the factor types, as all types required should be
    # in here.
    if( $factorsConfig->has_menu_filter_factor_types ) {
        foreach my $type ( @{ $factorsConfig->get_menu_filter_factor_types } ) {
            $configFactorTypes->{ $type } = 1;
        }
    }
    # If not, get the default query factor type (single-factor experiment).
    else {
        $configFactorTypes->{ $factorsConfig->get_default_query_factor_type } = 1;
    }

    # Go through the assays, check that the factors match those from the
    # factors XML. If not, change them so that they do, and replace the assay
    # with the new version.

    # Make a copy of the hash of config factor types to use to check that all the
    # types in the factors config are somewhere in the SDRF (Factors or
    # Characteristics). Once a property type is seen once in the assays from
    # the SDRF, it is deleted from this hash. If, after the following loop has
    # completed, there are any property types left in this hash, we know that
    # those types were not seen in the SDRF and hence something is not right
    # with the factors config.
    my %typesNotInSDRF = %{ $configFactorTypes };
    foreach my $assayName ( sort keys %{ $atlasAssays } ) {
        my $assay = $atlasAssays->{ $assayName };
        my $assayFactors = $assay->get_factors;
        foreach my $assayFactorType ( keys %{ $assayFactors } ) {
            # Create a version of the assay factor type for matching to the
            # factors XML config. Use upper case and replace spaces with
            # underscores, so it matches the format found in the factors XML
            # config.
            ( my $assayFactorType4match = $assayFactorType ) =~ s/\s/_/g;
            $assayFactorType4match = uc( $assayFactorType4match );

            # If this factor is not in the config factors, remove it from the
            # assay factors hash.
            unless( $configFactorTypes->{ $assayFactorType4match } ) {
                # Log that we are doing this.
                $logger->debug(
                    "SDRF Factor type \"",
                    $assayFactorType,
                    "\" not matched in Factors XML config. Will not include it in condensed SDRF."
                );
                delete $assayFactors->{ $assayFactorType };
            }
        }

        # Now we may have removed some things from the assay factors hash, or
        # maybe not. This may now be an empty hash.
        # Go through the config factors and check if there are any factors
        # there that are not in the assay factors. If there are, these
        # properties should be listed as characteristics, so copy the property
        # from the assay characteristics into the factors.
        foreach my $configFactorType ( sort keys %{ $configFactorTypes } ) {
            my $matchingAssayFactor = _get_matching_property_type( $assayFactors, $configFactorType );
            unless( $matchingAssayFactor ) {
                $logger->debug(
                    "Factor type matching \"",
                    $configFactorType,
                    "\" found in Factors XML config but not SDRF Factors. Adding it to condensed SDRF from Characteristics."
                );
                # Try to get this property from the characteristics, and add it
                # to the factors.
                my $assayCharacteristics = $assay->get_characteristics;
                my $matchingAssayChar = _get_matching_property_type( $assayCharacteristics, $configFactorType );
                if( $matchingAssayChar ) {
                    $assayFactors->{ $matchingAssayChar } = $assayCharacteristics->{ $matchingAssayChar };
                    $logger->debug(
                        "Characteristic type \"",
                        $matchingAssayChar,
                        "\" matches \"",
                        $configFactorType,
                        "\""
                    );
                    delete $typesNotInSDRF{ $configFactorType };
                }
                # Warn if we couldn't get this property from the
                # characteristics for this assay. Some assays may be blank for
                # some characteristics.
                else {
                    $logger->warn(
                        "Property matching \"",
                        $configFactorType,
                        "\" from Factors XML config not found in Characteristics for assay ",
                        $assay->get_name
                    );
                }
            }
            else {
                $logger->debug(
                    "Factor type \"",
                    $matchingAssayFactor,
                    "\" matches \"",
                    $configFactorType,
                    "\""
                );
                delete $typesNotInSDRF{ $configFactorType };
            }
        }

        # Set the edited factors for this assay.
        $assay->set_factors( $assayFactors );
        # Replace the edited assay in the hash.
        $atlasAssays->{ $assayName } = $assay;
    }

    # If there are any property types left in the hash created before the loop,
    # this means they were not found at all in the SDRF assays. This is not
    # allowed.
    if( keys %typesNotInSDRF ) {
        my $nonSDRFtypes = join "\", \"", ( keys %typesNotInSDRF );
        $logger->logdie(
            "No assays with types matching the following from Factors XML config: \"",
            $nonSDRFtypes,
            "\" -- cannot continue."
        );
    }
    $logger->info( "Finished checking factors." );
    return $atlasAssays;
}


sub _get_matching_property_type {
    my ( $assayProperties, $configFactorType ) = @_;
    # Replace spaces with underscores to match more easily.
    ( my $cfgFactorTypeSpaces = $configFactorType ) =~ s/_/ /g;
    my $matchingAssayType;
    # If the property doesn't exist in the assay properties
    foreach my $assayType ( keys %{ $assayProperties } ) {
        if( $assayType =~ /$cfgFactorTypeSpaces/i ) {
            $matchingAssayType = $assayType;
        }
    }
    return $matchingAssayType;
}


# Get the unique property type-value pairs and the assays which they apply to.
sub get_all_properties_for_assays {
    my ( $atlasAssays ) = @_;
    my $allPropertiesAssays = {};
    foreach my $assay ( values %{ $atlasAssays } ) {
        my $assayName = $assay->get_name;
        my $characteristics = $assay->get_characteristics;
        # Add the characteristic types and values to the
        foreach my $type ( keys %{ $characteristics } ) {
            foreach my $value ( keys %{ $characteristics->{ $type } } ) {
                $allPropertiesAssays->{ $type }->{ $value }->{ $assayName } = 1;
            }
        }

        # If we also have factors, add them here too.
        if( $assay->has_factors ) {
            my $factors = $assay->get_factors;
            foreach my $type ( keys %{ $factors } ) {
                foreach my $value ( keys %{ $factors->{ $type } } ) {
                    $allPropertiesAssays->{ $type }->{ $value }->{ $assayName } = 1;
                }
            }
        }
    }

    return $allPropertiesAssays;
}


sub run_zooma_mapping {
    my ( $args, $allPropertiesAssays ) = @_;
    # Filename for Zoomifications to be written to.
    my $zoomificationsFilename = File::Spec->catfile( $args->{ "output_directory" }, $expAcc . "-zoomifications-log.tsv" );
    my $atlasSiteConfig = create_atlas_site_config;
    my $zoomaExclusions = Config::YAML->new(
        config => $args->{ "zooma_exclusions_path" }
    );
    # Minimum length of a property value allowed for mapping. Anything less
    # than this is excluded.
    my $minStringLength = 3;
    # Get the ontology mappings from Zooma for each property type and value.
    $logger->info( "Mapping terms using Zooma..." );
    # Collect rows for "zoomifications" log file.
    my $allZoomificationRows = [];
    # Instantiate new Zooma client object.
    my $zoomaClient = Atlas::ZoomaClient->new;
    # Go through all the property type-value pairs and try to get Zooma
    # mappings for them.
    foreach my $type ( sort keys %{ $allPropertiesAssays } ) {
        # Flag in case we should exclude terms with this property type from
        # mapping.
        my $excludeType = 0;
        # If we find this property type in the list of types to be excluded,
        # set the excludeType flag.
        if( grep $_ eq $type, @{ $zoomaExclusions->get_types_to_exclude } ) {
            $excludeType++;
        }
        # Go through the values for this type.
        foreach my $value ( sort keys %{ $allPropertiesAssays->{ $type } } ) {
            # Flag in case we should exclude terms with this property value
            # from mapping.
            my $excludeValue = 0;
            my $tooShort = 0;
            # If this property value is in the list of values to be excluded,
            # set the excludeValue flag.
            if( grep $_ eq lc( $value ), @{ $zoomaExclusions->get_values_to_exclude } ) {
                $excludeValue++;
            }
            # Otherwise, check for the type-value pair in the list of
            # type-value pairs to exclude. Set both flags if the pair is found.
            elsif( grep $_ eq lc( $type ), ( keys %{ $zoomaExclusions->get_type_value_pairs_to_exclude } ) ) {
                my $valuesForType = $zoomaExclusions->get_type_value_pairs_to_exclude->{ $type };
                if( grep $_ eq lc( $value ), @{ $valuesForType } ) {
                    $excludeType++;
                    $excludeValue++;
                }
            }
            # Otherwise, if the value is less than the minimum allowed string
            # length, set the tooShort flag.
            elsif( length( $value ) < $minStringLength ) { $tooShort++; }
            # Initialise variable to store mapping results.
            my $mappingResult;
            my $organism;
            # Do the mapping if appropriate.
            # If not, decide the reason for exclusion (needed for zoomification
            # log) based on the flag(s) that have been set and create a new
            # MappingResult object containing this.
            if( $excludeType || $excludeValue || $tooShort ) {
                my $reasonForExclusion;
                if( $excludeType && $excludeValue ) {
                    $reasonForExclusion = "Type=$type; Value=$value";
                }
                elsif( $excludeType ) {
                    $reasonForExclusion = "Type=$type";
                }
                elsif( $excludeValue ) {
                    $reasonForExclusion = "Value=$value";
                }
                elsif( $tooShort ) {
                    $reasonForExclusion = "property value too short";
                }
                $mappingResult = Atlas::ZoomaClient::MappingResult->new(
                    mapping_category => "EXCLUDED",
                    reason_for_exclusion => $reasonForExclusion
                );
            }
            else {
                $organism= (keys %{ $allPropertiesAssays->{'organism'} })[0];
                $organism=lc $organism;
                $organism =~ s/\s+/_/g;
                $mappingResult = $zoomaClient->map_term( $type, $value, $organism );
            }

            # If we didn't get a mapping result, something must have gone wrong.
            if( ! $mappingResult ) {
                $logger->warn(
                    "Zooma mapping failed for type \"$type\" and value \"$value\"; reason unknown."
                );
                $mappingResult = Atlas::ZoomaClient::MappingResult->new(
                    mapping_category => "NO_RESULTS",
                    zooma_error => "unknown error"
                );

            }

            # Now create the zoomification rows and log results.
            # Check for any errors.
            if( $mappingResult->has_zooma_error ) {
                $logger->warn(
                    "Zooma mapping failed for type \"$type\" and value \"$value\": ",
                    $mappingResult->get_zooma_error
                );
            }

            # Get all the assays with this mapping result.
            my @assayNames = keys %{ $allPropertiesAssays->{ $type }->{ $value } };

            # Create the rows for the Zoomifications file.
            my $zoomificationRow = create_zoomification_row(
                $expAcc,
                $type,
                $value,
                \@assayNames,
                $mappingResult
            );

            push @{ $allZoomificationRows }, $zoomificationRow;
            my $mappingCategory = $mappingResult->get_mapping_category;
            if( $mappingCategory eq "AUTOMATIC" ) {
                $automaticMappings->{ $type }->{ $value } = $mappingResult->get_ontology_mapping;
                $logger->info(
                    "Type \"$type\" with value \"$value\" automatically mapped to ",
                    $mappingResult->get_ontology_mapping
                );
            }
            elsif( $mappingCategory eq "REQUIRES_CURATION" ) {
                $logger->info(
                    "Type \"$type\" with value \"$value\" mapping requires curation. Potential mapping: ",
                    $mappingResult->get_ontology_mapping
                );
            }
            elsif( $mappingCategory eq "EXCLUDED" ) {
                $logger->info(
                    "Type \"$type\" with value \"$value\" was excluded from Zooma mapping."
                );
            }
        }
    }

    $logger->info( "Writing zoomification info to $zoomificationsFilename ..." );
    open( my $fh, ">:encoding(UTF-8)", $zoomificationsFilename ) or $logger->logdie( "Cannot open $zoomificationsFilename for writing: $!" );
    $fh->autoflush( 1 );
    say $fh "PROPERTY_TYPE\tPROPERTY_VALUE\tONTOLOGY_LABEL|ZOOMA_VALUE\tPROP_VALUE_MATCH\tSEMANTIC_TAG\tSTUDY\tBIOENTITY\tCategory of Zooma Mapping\tBasis for Exclusion";
    foreach my $row ( @{ $allZoomificationRows } ) { say $fh $row; }
    close $fh;
    $logger->info( "Successfully written zoomification info." );
    $logger->info( "Zooma mapping finished successfully." );
    return $automaticMappings;
}


# Create a row for the zoomification file for a set of assays.
sub create_zoomification_row {
    my ( $expAcc, $type, $value, $assayNames, $mappingResult ) = @_;
    my $mappingCategory = $mappingResult->get_mapping_category;
    # Column headings are:
    # PROPERTY_TYPE
    # PROPERTY_VALUE
    # ONTOLOGY_LABEL|ZOOMA_VALUE
    # PROP_VALUE_MATCH
    # SEMANTIC_TAG
    # STUDY
    # BIOENTITY
    # Category of Zooma mapping
    # Basis for Exclusion

    if( $mappingCategory eq "AUTOMATIC" || $mappingCategory eq "REQUIRES_CURATION" ) {
        # For automatic mappings, we need: accession, property type,
        # property value, ontology label|zooma value, prop value match,
        # ontology uri(s), mapping category, assay name.
        my $ontologyMapping = $mappingResult->get_ontology_mapping;
        # Replace spaces between URIs with |
        $ontologyMapping =~ s/ /|/g;
        # Get the ontology label and Zooma value.
        my $ontologyLabel = $mappingResult->get_ontology_label;
        my $zoomaValue = $mappingResult->get_zooma_property_value;
        # What should go in ONTOLOGY_LABEL|ZOOMA_VALUE column?
        my $ontologyLabelZoomaValue;
        if( $ontologyLabel ) {
            if( lc( $ontologyLabel ) eq lc( $zoomaValue ) ) {
                $ontologyLabelZoomaValue = $ontologyLabel;
            }
            else {
                $ontologyLabelZoomaValue = "$ontologyLabel|$zoomaValue";
            }
        }
        else {
            $ontologyLabelZoomaValue = "|$zoomaValue";
        }

        # Figure out the property value match category -- either
        # "MATCHES_ONTOLOGY_LABEL", "MATCHES_ZOOMA_VALUE", or "mismatch".
        my $propValueMatch;

        if( $ontologyLabel ) {
            if( lc( $value ) eq lc( $ontologyLabel ) ) {
                $propValueMatch = "MATCHES_ONTOLOGY_LABEL";
            }
            elsif( lc( $value ) eq lc( $zoomaValue ) ) {
                $propValueMatch = "MATCHES_ZOOMA_INPUT";
            }
            else {
                $propValueMatch = "mismatch";
            }
        }
        elsif( lc( $value ) eq lc( $zoomaValue ) ) {
            $propValueMatch = "MATCHES_ZOOMA_INPUT";
        }
        else {
            $propValueMatch = "mismatch";
        }

        # Just use the first assay name.
        my $assayName = $assayNames->[ 0 ];

        return "$type\t$value\t$ontologyLabelZoomaValue\t$propValueMatch\t$ontologyMapping\t$expAcc\t$assayName\t$mappingCategory\tnull";
    }
    elsif( $mappingCategory eq "NO_RESULTS" ) {
        my $assayName = $assayNames->[ 0 ];
        # For mappings with no results, we need: property type, property value,
        # accession, mapping category, and assay name.
        return "$type\t$value\tnull\tnull\tnull\t$expAcc\t$assayName\t$mappingCategory\tnull";
    }
    elsif( $mappingCategory eq "EXCLUDED" ) {
        my $reason = $mappingResult->get_reason_for_exclusion;
        my $assayName = $assayNames->[ 0 ];
        return "$type\t$value\tnull\tnull\tnull\t$expAcc\t$assayName\t$mappingCategory\t$reason";
    }
}


sub _make_assay_lines {
    my ( $expAcc, $atlasAssay, $attributeHash, $attributeType, $automaticMappings, $addBioreps ) = @_;
    my $condensedSdrfLines = [];
    my $doseAttributeLines = {};
    foreach my $type ( sort keys %{ $attributeHash } ) {
        foreach my $value ( sort keys %{ $attributeHash->{ $type } } ) {
            my $line = "$expAcc\t";
            if( $atlasAssay->has_array_design ) {
                $line .= $atlasAssay->get_array_design . "\t";
            }
            else {
                $line .= "\t";
            }
            $line .= $atlasAssay->get_name . "\t";
            if( $addBioreps ) {
                if( $atlasAssay->has_technical_replicate_group ) {
                    my $biorepID = $atlasAssay->get_technical_replicate_group;
                    $biorepID =~ s/^t/biorep/;
                    $line .= "$biorepID\t";
                }
                else { $line .= "\t"; }
            }

            $line .= "$attributeType\t$type\t$value";
            my $uri = $automaticMappings->{ $type }->{ $value };
            if( $uri ) { $line .= "\t$uri"; }
            if( $type =~ /compound/i || $type =~ /irradiate/i ) {
                $doseAttributeLines->{ "attribute" } = $line;
            }
            elsif( $type =~ /dose/i ) {
                $doseAttributeLines->{ "dose" } = $line;
            }
            else {
                push @{ $condensedSdrfLines }, $line;
            }
        }
    }

    if( keys %{ $doseAttributeLines } ) {
        if( $doseAttributeLines->{ "attribute" } ) {
            push @{ $condensedSdrfLines }, $doseAttributeLines->{ "attribute" };
        }
        if( $doseAttributeLines->{ "dose" } ) {
            push @{ $condensedSdrfLines }, $doseAttributeLines->{ "dose" };
        }
    }
    return $condensedSdrfLines;
}