#!/usr/bin/env bash

MODE=${mode:-"atlas"}
FORCEALL=${FORCEALL:-false}
RESTART_TIMES=${RESTART_TIMES:-3}
NJOBS=${NJOBS:-2}
EMAIL=${EMAIL:-false}
RETRYWOUTZOOMA=${3:-yes}
ZOOMA_META_URL=${ZOOMA_API_BASE}/server/metadata

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


# -conda-prefix $SN_CONDA_PREFIX
snakemake --use-conda --conda-frontend mamba --restart-times $RESTART_TIMES --config \
    mode=$MODE \
    zooma_exclusions=$ZOOMA_EXCLUSIONS \
    zoomaMetadataUrl=$ZOOMA_META_URL \
    notifEmail=$EMAIL \
    retryWithoutZooma=$RETRYWOUTZOOMA \
    working_dir=$WORKING_DIR \
    -j $NJOBS -s Snakefile


