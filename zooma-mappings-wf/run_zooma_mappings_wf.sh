#!/usr/bin/env bash

MODE="atlas"
FORCEALL=${FORCEALL:-false}
RESTART_TIMES=${RESTART_TIMES:-3}
NJOBS=${NJOBS:-2}
EMAIL=${EMAIL:-false}
RETRYWOUTZOOMA=${3:-yes}
ZOOMA_META_URL=${ZOOMA_API_BASE}/server/metadata

# Check that relevant env vars are set
[ -z ${SN_CONDA_PREFIX +x} ] && echo "Env var SN_CONDA_PREFIX needs to be defined." && exit 1

# -conda-prefix $SN_CONDA_PREFIX
snakemake --use-conda --conda-frontend mamba --restart-times $RESTART_TIMES --config \
    mode=$MODE \
    zooma_exclusions=$ZOOMA_EXCLUSIONS \
    zoomaMetadataUrl=$ZOOMA_META_URL \
    notifEmail=$EMAIL \
    retryWithoutZooma=$RETRYWOUTZOOMA \
    atlas_exps=$ATLAS_EXPS \
    atlas_sc_experiments=$ATLAS_SC_EXPERIMENTS \
    irap_single_lib=$IRAP_SINGLE_LIB/zoomage \
    -j $NJOBS -s Snakefile


