#!/usr/bin/env perl

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
use Atlas::ZoomaClient;
use Atlas::ZoomaClient::MappingResult;
use Atlas::AtlasConfig::Reader qw( parseAtlasFactors );
use File::Basename;
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

my $unique_properties = {};
my $cell2organism = {};
# Read file and produce hash as expected by run_zooma_mapping
open COND_IN, $args->{"condensed_sdrf_path"};
my $expAcc;
while(my $line = <COND_IN>) {
  # That is: $hash->{ $type }->{ $value } where type is the type of annotation
  # (characteristic, factor, etc)
  # Example line to read:
  # (there is a hidden field between 1st and 2nd visible fields)
  # E-MTAB-6701   ERR2743635-CGAATGTGTCCTCTTG characteristic  developmental stage     adult   http://www.ebi.ac.uk/efo/EFO_0001272
  chomp $line;
  my ($expAccAux, $arrayDesign, $cell, $attributeType, $type, $value, $uri) = split /\t/, $line;
  $expAcc = $expAccAux;
  # we only care about cell types
  $unique_properties->{ $type }->{ $value }->{ $cell } = 1;
  # and run zooma needs the organism
  if ($type =~ /^organism$/ && !$cell2organism->{ $cell }) {
      my $org = lc $value;
      $org =~ s/\s+/_/g;
      $cell2organism->{ $cell } = $org;
  }
  # even if the content of a droplet wouldn't be a cell (such as a set of oligos),
  # this would still have an organism such as "synthetic" or "mixed samples".
  # So there is no case where a "cell" for this purposes has no organism.
}
close(COND_IN);

my $automaticMappings = {};
$automaticMappings = run_zooma_mapping($unique_properties, $cell2organism, $args->{"exclusions_file_path"}, $args->{"output_zoomifications"}, $expAcc);

# Open the output file for writing.
open( my $fh, ">:encoding(UTF-8)", $args->{"output_sdrf_condensed"} ) or die( "ERROR - Cannot open $args->{'output_sdrf_condensed'} for writing: $!\n" );
$logger->info( "Re-writing condensed SDRF to $args->{'output_sdrf_condensed'} ..." );

open COND_IN_2, $args->{"condensed_sdrf_path"};
while(my $line = <COND_IN_2>) {
  chomp $line;
  my ($expAccAux, $arrayDesign, $cell, $attributeType, $type, $value, $uri) = split /\t/, $line;
  $uri = "" if( !$uri );
  my $organism = $cell2organism->{ $cell };
  my $annot_uri = $automaticMappings->{ $type }->{ $value }->{$organism};
  $uri = $annot_uri if( $annot_uri );
  say $fh join("\t", $expAccAux, $arrayDesign, $cell, $attributeType, $type, $value, $uri);
}
close(COND_IN_2);
close($fh);

$logger->info( "Successfully produced condensed SDRF with zooma terms annotated." );

# Get commandline arguments.
sub parse_args {
    my %args;
    my $want_help;
    GetOptions(
        "h|help"            => \$want_help,
        "c|condensed=s"    => \$args{ "condensed_sdrf_path" },
        "x|exclusions_file=s"        => \$args{ "exclusions_file_path" },
        "o|out_condensed=s"        => \$args{ "output_sdrf_condensed" },
        "l|zoomifications_log=s"   => \$args{ "output_zoomifications" },
        "d|debug"           => \$args{ "debug" }
    );
    unless( $args{ "condensed_sdrf_path" } ) {
        pod2usage(
            -message => "You must specify an input condensed_sdrf_path (-c).\n",
            -exitval => 255,
            -output => \*STDOUT,
            -verbose => 1,
        );
    }
    unless( $args{ "output_zoomifications" } ) {
        pod2usage(
            -message => "You must specify an output file for zoomification logs (-l).\n",
            -exitval => 255,
            -output => \*STDOUT,
            -verbose => 1,
        );
    }
    unless($args{ "output_sdrf_condensed" }) {
        pod2usage(
          -message => "No output condensed sdrf path given (-o)\n",
          -exitval => 255,
          -output => \*STDOUT,
          -verbose => 1,
        );
    }
    return \%args;
}

sub run_zooma_mapping {
    my ( $allPropertiesAssays, $cell2organism, $zoomaExclusionsFilename, $zoomificationsFilename, $expAcc ) = @_;
    my $zoomaExclusions = Config::YAML->new(
        config => $zoomaExclusionsFilename
    ) if $zoomaExclusionsFilename;
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

            # get all different cells for this type/value
            my @cells = keys %{ $allPropertiesAssays->{ $type }->{ $value } };
            my $organisms = {};
            foreach my $cell (@cells) {
              $organisms->{ $cell2organism->{$cell} } = 1;
            }
            # run for all different organisms for these cells with this type/value
            foreach my $organism (keys %{ $organisms } ) {
                #$organism =~ s/\s+/_/g;


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
                    $automaticMappings->{ $type }->{ $value }->{ $organism } = $mappingResult->get_ontology_mapping;
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
