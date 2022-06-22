#!/usr/bin/env bash

MODE=${MODE:-"atlas"}
ZOOMA_EXCLUSIONS=$( pwd )/zooma_exclusions.yml
FORCEALL=${FORCEALL:-true} # set to true. If the file is present it won't update
if [ "$FORCEALL" = true ]; then FORCE_ALL="--forceall"; else FORCE_ALL=""; fi

RESTART_TIMES=${RESTART_TIMES:-3}
NJOBS=${NJOBS:-2}
EMAIL=${EMAIL:-false}
RETRYWOUTZOOMA=${RETRYWOUTZOOMA:-yes} # or true
ZOOMA_META_URL=${ZOOMA_API_BASE}/server/metadata

ATLAS_PROD_BRANCH=${ATLAS_PROD_BRANCH:-"develop"}
PROCESSED_BRANCH=$(echo $ATLAS_PROD_BRANCH | sed 's+/+_+g')
ATLAS_PROD_CO="${ATLAS_PROD}/sw/atlasinstall_branches/atlasprod_${PROCESSED_BRANCH}/atlasprod"
LSF_CONFIG=$( pwd )/lsf.yaml
CONDA_PREFIX_LINE="--conda-prefix $SN_CONDA_PREFIX"

# Check that relevant env vars are set
[ -z ${WORKING_DIR+x} ] && echo "Env var WORKING_DIR needs to be defined." && exit 1

[ -z ${TEMP_DIR+x} ] && echo "Env var TEMP_DIR needs to be defined." && exit 1

[ -z ${CONDA_PREFIX_LINE+x} ] && echo "Env var CONDA_PREFIX_LINE needs to be defined." && exit 1

[ -z ${ZOOMA_API_BASE+x} ] && echo "Env var ZOOMA_API_BASE needs to be defined." && exit 1

[ -z ${ZOOMA_META_URL+x} ] && echo "Env var ZOOMA_META_URL needs to be defined." && exit 1

[ -z ${EXPERIMENT_METADATA_DIR+x} ] && echo "Env var EXPERIMENT_METADATA_DIR needs to be defined." && exit 1

[ -z ${PREVIOUS_RUN_DATE+x} ] && echo "Env var PREVIOUS_RUN_DATE needs to be defined." && exit 1

#--dry-run
snakemake --use-conda --conda-frontend mamba --restart-times $RESTART_TIMES \
    --latency-wait 20 --keep-going \
    $PROFILE_LINE $CONDA_PREFIX_LINE $FORCE_ALL  --config \
    mode=$MODE \
    zooma_exclusions=$ZOOMA_EXCLUSIONS \
    temp_dir=$TEMP_DIR \
    zoomaMetadataUrl=$ZOOMA_META_URL \
    notifEmail=$EMAIL \
    retryWithoutZooma=$RETRYWOUTZOOMA \
    working_dir=$WORKING_DIR \
    experiment_metadata_dir=$EXPERIMENT_METADATA_DIR \
    atlas_prod_co=$ATLAS_PROD_CO \
    lsf_config=$LSF_CONFIG \
    previousRunDate=$PREVIOUS_RUN_DATE \
    -j $NJOBS -s Snakefile

