#!/usr/bin/env bash


usage() { echo "Usage: $0 <accession> path-to-atlas-exps" 1>&2; }

expAcc=$1
ATLAS_EXPS=$2

if [ -z "${expAcc}" ] || [ -z "${ATLAS_EXPS}" ]; then
    usage
    exit 1
fi

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# Get the experiment type from the XML config.
expType=$(${scriptDir}/get_experiment_type_from_xml.pl $expAcc/$expAcc-configuration.xml)
if [ $? -ne 0 ]; then
    echo "ERROR: failed to get $expAcc experiment type from XML config. Cannot generate condensed SDRF."
    exit 1
fi

# Now generate condensed sdrf containing ontology mappings from Zooma. This
# will also copy IDF from ArrayExpress load directory (using "-i" option).
# If this is a baseline experiment, pass the factors XML filename as well to ensure factors match in condensed SDRF.
if [[ $expType == *baseline ]]; then

    ${scriptDir}/condense_sdrf.pl -e $expAcc -f $expAcc/$expAcc-factors.xml -z -i -o $expAcc
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to generate $expAcc/${expAcc}.condensed-sdrf.tsv with Zooma mappings, trying without..."
        ${scriptDir}/condense_sdrf.pl -e $expAcc -f $expAcc/$expAcc-factors.xml -i -o $expAcc
    fi
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to generate $expAcc/${expAcc}.condensed-sdrf.tsv"
        return 1
    fi
else

    ${scriptDir}/condense_sdrf.pl -e $expAcc -z -i -o $expAcc
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to generate $expAcc/${expAcc}.condensed-sdrf.tsv with Zooma mappings, trying without..."
        ${scriptDir}/condense_sdrf.pl -e $expAcc -i -o $expAcc
    fi
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to generate $expAcc/${expAcc}.condensed-sdrf.tsv"
        return 1
    fi
fi

if [ ! -s "$expAcc/${expAcc}.condensed-sdrf.tsv" ]; then
echo "ERROR: Failed to generate $expAcc/${expAcc}.condensed-sdrf.tsv"
return 1
fi

applyAllFixesForExperiment $expAcc
if [ $? -ne 0 ]; then
echo "ERROR: Applying fixes for experiment $e failed" >&2
return 1
fi

rm -rf $expAcc/$expAcc-zoomifications-log.tsv
popd
