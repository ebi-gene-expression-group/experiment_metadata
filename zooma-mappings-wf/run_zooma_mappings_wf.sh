#!/usr/bin/env bash

MODE=${MODE:-"atlas"}
ATLAS_PROD_BRANCH=${ATLAS_PROD_BRANCH:-"develop"}
FORCEALL=${FORCEALL:-true} # set to true. If the file is present it won't update
RESTART_TIMES=${RESTART_TIMES:-3}
NJOBS=${NJOBS:-2}
EMAIL=${EMAIL:-false}
RETRYWOUTZOOMA=${RETRYWOUTZOOMA:-yes} # or true
ZOOMA_META_URL=${ZOOMA_API_BASE}/server/metadata
# temp dir for zooma mapping reports
TEMP_DIR=/hps/nobackup/ma/... #$FG_ATLAS_TMP !!!!!!!!!!!!!!
ZOOMA_EXCLUSIONS=

# Check that relevant env vars are set
[ -z ${SN_CONDA_PREFIX +x} ] && echo "Env var SN_CONDA_PREFIX needs to be defined." && exit 1


# Determine working directory to use
if [ "$MODE" == "atlas" ]; then
  WORKING_DIR=$ATLAS_EXPS
elif [ "$MODE" == "single_cell" ]; then
  [ -z ${ATLAS_SC_EXPERIMENTS+x} ] && echo "Env var ATLAS_SC_EXPERIMENTS pointing to the directory for Atlas SC Experiments needs to be defined to run with SC data." && exit 1
  WORKING_DIR=$ATLAS_SC_EXPERIMENTS
elif [ "$MODE" == "irap_single_lib" ]; then
  WORKING_DIR=$IRAP_SINGLE_LIB/zoomage
else
  echo "ERROR: mode: $MODE not recognised"
  exit 1
fi


# Derive variables and source script for apply_fixes rule
PROCESSED_BRANCH=$(echo $ATLAS_PROD_BRANCH | sed 's+/+_+g')
ATLAS_PROD_CO="${ATLAS_PROD}/sw/atlasinstall_branches/atlasprod_${PROCESSED_BRANCH}/atlasprod"
#EXP_METADATA_DIR="${ATLAS_PROD_CO}/experiment_metadata"
#source ${ATLAS_PROD_CO}/bash_util/generic_routines.sh
export -f applyAllFixesForExperiment


# -conda-prefix $SN_CONDA_PREFIX
snakemake --use-conda --conda-frontend mamba --restart-times $RESTART_TIMES --config \
    mode=$MODE \
    zooma_exclusions=$ZOOMA_EXCLUSIONS \
    temp_dir=$TEMP_DIR \
    zoomaMetadataUrl=$ZOOMA_META_URL \
    notifEmail=$EMAIL \
    retryWithoutZooma=$RETRYWOUTZOOMA \
    working_dir=$WORKING_DIR \
    atlas_prod_co=$ATLAS_PROD_CO \
    #exp_metadata_dir=$EXP_METADATA_DIR \
    -j $NJOBS -s Snakefile


