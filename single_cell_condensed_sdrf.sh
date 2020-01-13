#!/usr/bin/env bash
#
# We require
# EXP_ID
# ATLAS_SC_EXPERIMENTS
# Optionally:
# SKIP_ZOOMA (if set, then Zooma mapping is skipped)

usage() { echo "Usage: $0 [-e <experiment id>] [-f <IDF file location (optional, otherwise inferred from ATLAS_SC_EXPERIMENTS env var)>] [-s <supply any non-empty string to skip zooma processing (if not specified, inferred from SKIP_ZOOM env var where available)>] [-o <directory to store file output (where not specified, output will be experiment location under ATLAS_SC_EXPERIMENTS env var, where specified)>]" 1>&2; }

# Parse arguments

expId="$EXP_ID"
idfFile=
experimentDir="$ATLAS_SC_EXPERIMENTS"
skipZooma="$SKIP_ZOOMA"
outputDir=

while getopts ":e:f:s:o:" o; do
    case "${o}" in
        e)
            expId=${OPTARG}
            ;;
        f)
            idfFile=${OPTARG}
            ;;
        s)
            skipZooma=${OPTARG}
            ;;
        o)
            outputDir=${OPTARG}
            ;;
        *)
            usage
            exit 0
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${expId}" ]; then
    usage
    exit 1
fi

if [ -z "$outputDir" ]; then 
    outputDir=$experimentDir/$expId/
fi

# If an actual file is specified, we can pass that directly

set -e

# Source script from the same (prod or test) Atlas environment as this script
scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# Derive input files
if [ -z "$idfFile" ]; then
    idfFile=$experimentDir/$expId/${expId}.idf.txt
fi

sdrfFile=$(dirname $idfFile)/${expId}.sdrf.txt
cellToLib=$(dirname $idfFile)/cell_to_library.txt

# Check input files exist

if [ ! -e "$idfFile" ]; then
    echo "IDF file for experiment ID $expId ($idfFile) not present" 1>&2
    exit 1
elif [ ! -e "$sdrfFile" ]; then
    echo "SDRF file $sdrfFile missing" 1>&2
    exit 1
fi

checkExecutableInPath() {
  [[ $(type -P $1) ]] || (echo "$1 binaries not in the path." && exit 1)
  [[ -x $(type -P $1) ]] || (echo "$1 is not executable." && exit 1)
}

hasTechnicalReplicates() {
  [ -z ${expId+x} ] && "Var EXP_ID for the experiment accession needs to be defined."

  columnTechRep=$(head -n 1 $sdrfFile | sed 's/\t/\n/g' | awk -F'\t' '{ if( $s ~ /^Comment\s{0,1}\[technical replicate group\]$/ ) { print NR } }' )
  columnRun=$(head -n 1 $sdrfFile | sed 's/\t/\n/g' | awk -F'\t' '{ if( $s ~ /^Comment\s{0,1}\[ENA_RUN\]$/ ) { print NR } }' )
  if [[ ! $columnRun =~ ^-?[0-9]+$ ]]; then
    # No column found, must be HCA case
    columnRun=$(head -n 1 $sdrfFile | sed 's/\t/\n/g' | awk -F'\t' '{ if( $s ~ /^Comment\s{0,1}\[RUN\]$/ ) { print NR } }' )
  fi


  # "Column num: $columnTechRep"
  if [[ ! $columnTechRep =~ ^-?[0-9]+$ ]]; then
     # "No replicas column found, setting sample_id to the run_id value..."
     # "No technical replicates, first if"
     replicates=false
     return
  else
     # Check that the technical replicates column has relevant values
     uniqueTechnicalReplicatesValues=$(awk -v c1=$columnTechRep -F'\t' '{ print $c1 }' $sdrfFile | grep -v '^Comment' | sort -u )
     uniqueTechReplicasCount=$(echo $uniqueTechnicalReplicatesValues | wc | awk '{ print $1 }')
     uniqueRunIDCount=$(awk -v c1=$columnRun -F'\t' '{ print $c1 }' $sdrfFile | grep -v '^Comment' | sort -u | wc | awk '{ print $1 }')
     # "Array size ${#techReplicasContent[@]}"
     # "First value ${techReplicasContent[0]}"

     if [ "$uniqueTechReplicasCount" = "$uniqueRunIDCount" ]; then
       # if the amount of unique runs and the amount of unique technical replicates
       # is the same, then there are not technical replicates either.
       replicates=false
       return
     fi

     # if the array only contains a single value and this is "not applicable",
     # set it to point to columnRun as there are no replicates here either.
     if [ "$uniqueTechReplicasCount" = "1" ]; then
       if [ "$(echo $uniqueTechnicalReplicatesValues | tr '[:upper:]' '[:lower:]')" = "not applicable" ]; then
         # No replicas defined as it is all "not applicable", setting sample_id to the run_id value...
         replicates=false
         return
       fi
       if [ ${#uniqueTechnicalReplicatesValues} = 0 ]; then
         # All values of the technical replicates column are blank, so no technical replicates either.
         replicates=false
         return
       fi
     fi
  fi
  # "Past all checks, it has replicates"
  replicates=true
  return
}

use_run_id_cell_id_In_condensed() {
  COND=$CONDENSED_SDRF_TSV
  # Format follows the fields of the condensed SDRF, replacing the 3rd field
  # for the 1st field in the cell_to_library file. Condensed can have up to 8 fields
  join -t$'\t' -o '1.1 1.2 2.1 1.4 1.5 1.6 1.7 1.8' -1 3 -2 2 \
    <( sort -t$'\t' -k 3,3 $COND ) \
    <( grep -v '^# Comment' $cellToLib | sort -t$'\t' -k 2,2 ) > $COND\_expanded
  if [ ! -s $COND\_expanded ]; then
    # file is empty, no keys matched
    echo "Error: $expId sdrf doesn't have the correct technical replicates identifiers or cell identifiers"
    echo "as expected in the cell to library file $cellToLib."
    echo "In the past this has been because the SDRF's technical replicates group has either an issue in the column name,"
    echo "the technical replicate group column is in the incorrect place or there are strange characters in the identifiers."
    echo "See the condensed SDRF file $COND and check for column names and order in the SDRF file"
    echo "The condensed SDRF was not modified as a result, and can be checked."
    rm $COND\_expanded
    exit 1
  fi
  mv $COND\_expanded $COND
}

use_cell_types_In_condensed() {
  CT=$CELLTYPES
  COND=$CONDENSED_SDRF_TSV
  # Find the column in CT for the cell id and the inferred cell types.
  col_num_ct=$( head -1 $CT | tr '\t' '\012' | nl | grep 'inferred cell type' | awk '{ print $1 }' )
  col_num_cell_id=$( head -1 $CT | tr '\t' '\012' | nl | grep 'Cell ID' | awk '{ print $1 }' )
  # For all elements in COND (column 3) that are in CT Cell id column, add columns:
  # expId\t\tcell-id\tfactor\tinferred cell types\t<value-for-inferred-cell-type
  # to condensed SDRF

  # First generate the additional condensed rows
  awk -F'\t' 'BEGIN { OFS = "\t" } NR == FNR { cell[$1]; type[$1]=$2; next } $3 in cell { print $1, $2, $3, "factor", "inferred cell type", type[$3] }' \
    <( awk -F'\t' -v cellCol=$col_num_cell_id -v ctCol=$col_num_ct 'BEGIN { OFS = "\t" } { print $cellCol, $ctCol }' $CT ) \
    $COND > $COND\.with_ct
  # if the file has content, merge it with the condensed.
  # TODO in the future, we could have a Zooma call to get identifiers for each inferred cell type, before adding it to the condensed.
  if [ -s $COND\.with_ct ]; then
    echo "Found matches for inferred cell types to add to the condensed..."
    cat $COND\.with_ct >> $COND
  else
    echo "WARNING: No matches found between cell types file and the condensed SDRF, please check"
    echo $CT "and"
    echo $COND
  fi
  rm $COND\.with_ct
}

checkExecutableInPath condense_sdrf.pl
checkExecutableInPath annotate_celltypes_condensed_sdrf.pl

# Figure out if the experiment has technical replicates
hasTechnicalReplicates
technicalReplicatesOption=""
if [ "$replicates" = true ]; then
  echo "Experiment detected to have technical replicates..."
  technicalReplicatesOption="--mergeTechReplicates"
fi

zoomaOption="-z"
if [ -n "$skipZooma" ]; then
  zoomaOption=""
fi

condense_sdrf.pl -e $expId -fi $idfFile $technicalReplicatesOption -sc $zoomaOption -o $outputDir
export CONDENSED_SDRF_TSV=$outputDir/$expId.condensed-sdrf.tsv
# Explode condensed SDRF for droplet experiments from RUN_ID to RUN_ID-CELL_ID.
if [ -f $cellToLib ]; then
  use_run_id_cell_id_In_condensed
fi

# Explode condensed SDRF with inferred cell type
export CELLTYPES=$ATLAS_PROD/singlecell/experiment/$expId.cells.txt
if [ -f $CELLTYPES ]; then
  echo "Found cell types file for $expId"
  use_cell_types_In_condensed

  exclusions=
  exclusionsFile=$scriptDir/../supporting_files/zooma_exclusions.yml

  if [ -e "$exclusionsFile" ]; then
    exclusions=" -x $exclusionsFile"
  fi

  annotate_celltypes_condensed_sdrf.pl -c $CONDENSED_SDRF_TSV \
                                       -o $CONDENSED_SDRF_TSV"_celltypes" \
                                       -l $CONDENSED_SDRF_TSV"_zoomalogs"$exclusions
  if [ "$?" = "0" ]; then # zooma mapping went fine
    # replace condensed file with the new one that has cell type ontologies.
    mv $CONDENSED_SDRF_TSV"_celltypes" $CONDENSED_SDRF_TSV
    # Append cell type zommification logs to main zoomification logs
    tail -n+2 $CONDENSED_SDRF_TSV"_zoomalogs" >> $outputDir/$expId-zoomifications-log.tsv
    rm $CONDENSED_SDRF_TSV"_zoomalogs"
  fi
fi
