#!/usr/bin/env bash

# This script replaces load_to_zooma, as the archival process is not needed
# since the mappings are available on a Git repository.
# It will require a particular git repo and commit from where to fetch the file
# and then it will copy it in the destination directory from where Zooma will consume it.

set -e

# Source script from the same (prod or test) Atlas environment as this script
scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# Advice on directory (to keep track of previous usage):
# DESTINATION_DIRECTORY=$ATLAS_FTP/curation

CURATED_METADATA_GITHUB_REPO=${CURATED_METADATA_GITHUB_REPO:-"https://github.com/ebi-gene-expression-group/curated-metadata"}
CURATED_METADATA_REVISION=${CURATED_METADATA_REVISION:-"master"}
CURATED_METADATA_PATH_IN_REPO=${CURATED_METADATA_PATH_IN_REPO:-"zoomage_report.CURATED.tsv"}

f=$(basename -- "$CURATED_METADATA_PATH_IN_REPO")

[ ! -z ${CURATED_METADATA_GITHUB_REPO+x} ] || ( echo "Env var CURATED_METADATA_GITHUB_REPO pointing to the curated file needs to be defined." && exit 1 )
[ ! -z ${CURATED_METADATA_REVISION+x} ] || ( echo "Env var ZOOMA_CURATED_FILE pointing to the curated file needs to be defined." && exit 1 )
[ ! -z ${DESTINATION_DIRECTORY+x} ] || ( echo "Env var DESTINATION_DIRECTORY pointing to the directory where the curated file should be copied needs to be defined." && exit 1 )

# Given that this repo holds very little data, is fine to do a whole clone and then checkout the desired revision.
# That also makes it git provider independent (as opposed to using the github api).
rm -rf ./curated_metadata
# Get the repo
git clone $CURATED_METADATA_GITHUB_REPO curated_metadata
cd curated_metadata
git checkout $CURATED_METADATA_REVISION
if [ -f $DESTINATION_DIRECTORY/$f ]; then
  # Check that we are copying something different to what is in the destination currently.
  set +e
  # diff returns an non-zero code on differences, but we don't want to fail here
  filediff=$( diff $CURATED_METADATA_PATH_IN_REPO $DESTINATION_DIRECTORY/$f )
  set -e
  # If the output of diff was empty, this means the files are the same, so quit.
  if [ -z "$filediff" ]; then
    echo "ERROR: the new file is the same as the old file. Please ensure that you have committed and pushed the new file to $CURATED_METADATA_GITHUB_REPO and that you are using the correct revision in variable CURATED_METADATA_REVISION (master by default)." >&2
    exit 1
  fi
fi

cp $CURATED_METADATA_PATH_IN_REPO $DESTINATION_DIRECTORY/
echo "File copied to $DESTINATION_DIRECTORY/$f"
cd ..
rm -rf curated_metadata
