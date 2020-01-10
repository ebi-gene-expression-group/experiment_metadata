#!/bin/bash

# N.B. This script should be called as fg_atlas user only.
# It archives /ebi/ftp/pub/databases/microarray/data/atlas/curation/zoomage_report.CURATED.tsv and then copies in place of that the file passed as the argument
# It serves to move experiment directory containing an Atlas configuration xml file under $ATLAS_PROD/conan_incoming

# Source script from the same (prod or test) Atlas environment as this script
echo "Please use deploy_zooma_curated_file.sh instead, this script is no longer used."
echo "Most probably, deploy_zooma_curated_file.sh is being run by the CI system on automatic triggers from"
echo "merges on master of https://github.com/ebi-gene-expression-group/curated-metadata, but you can probably"
echo "run manual triggers on specified commits/tags if needed."
exit 1
