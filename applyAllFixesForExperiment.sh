#!/usr/bin/env bash


usage() { echo "Usage: $0 <accession> path-to-atlas-exps" 1>&2; }

expAcc=$1

if [ -z "${expAcc}" ]; then
  usage
  exit 1
fi

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

exp=$1
echo "Applying fixes for $exp ..."

# Applies fixes encoded in $fixesFile to $exp.$fileTypeToBeFixed.txt
applyFixes() {
  exp=$1
  fixesFile=$2
  fileTypeToBeFixed=$3

  # Apply factor type fixes in ${fileTypeToBeFixed} file
  for l in $(cat $scriptDir/$fixesFile | sed 's|[[:space:]]*$||g');
  do
    if [ ! -s "$exp/$exp.${fileTypeToBeFixed}" ]; then
      echo "ERROR: $exp/$exp.${fileTypeToBeFixed} not found or is empty" >&2
      return 1
    fi
    echo $l | grep -P '\t' > /dev/null
    if [ $? -ne 0 ]; then
      echo  "WARNING: line: '$l' in automatic_fixes_properties.txt is missing a tab character - not applying the fix "
    fi
    correct=`echo $l | awk -F"\t" '{print $1}'`
    toBeReplaced=`echo $l | awk -F"\t" '{print $2}' | sed 's/[^-A-Za-z0-9_ ]/\\\&/g'`

    if [ "$fixesFile" == "automatic_fixes_properties.txt" ]; then
      # in sdrf or condensed-sdrv fix factor/characteristic types only
      #if [ "$fileTypeToBeFixed" == "sdrf.txt" ]; then
      #perl -pi -e "s|\[${toBeReplaced}\]|[${correct}]|g" $exp/$exp.${fileTypeToBeFixed}
      if [ "$fileTypeToBeFixed" == "condensed-sdrf.tsv" ]; then
        # In condensed-sdrf, the factor/characteristic type is the penultimate column - so tabs on both sides
        perl -pi -e "s|\t${toBeReplaced}\t|\t${correct}\t|g" $exp/$exp.${fileTypeToBeFixed}
      else
        # idf
        perl -pi -e "s|\t${toBeReplaced}\t|\t${correct}\t|g" $exp/$exp.${fileTypeToBeFixed}
        perl -pi -e "s|\t${toBeReplaced}$|\t${correct}|g" $exp/$exp.${fileTypeToBeFixed}
      fi
    elif [ "$fixesFile" == "automatic_fixes_values.txt" ]; then
      #if [ "$fileTypeToBeFixed" == "sdrf.txt" ]; then
      #perl -pi -e "s|\t${toBeReplaced}\t|\t${correct}\t|g" $exp/$exp.${fileTypeToBeFixed}
      #perl -pi -e "s|\t${toBeReplaced}$|\t${correct}|g" $exp/$exp.${fileTypeToBeFixed}
      if [ "$fileTypeToBeFixed" == "condensed-sdrf.tsv" ]; then
        # In condensed-sdrf, the factor/characteristic value is the last column - so tab on the left and line ending on the right
        perl -pi -e "s|\t${toBeReplaced}$|\t${correct}|g" $exp/$exp.${fileTypeToBeFixed}
      fi
    fi
  done
}

# Apply factor type fixes in idf file
applyFixes $exp automatic_fixes_properties.txt idf.txt
if [ $? -ne 0 ]; then
  echo "ERROR: Applying factor type fixes in idf file for $exp failed" >&2
  return 1
fi

# Apply factor/sample characteristic type fixes to the condensed-sdrf file
applyFixes $exp automatic_fixes_properties.txt condensed-sdrf.tsv
if [ $? -ne 0 ]; then
  echo "ERROR: Applying sample characteristic/factor types fixes in sdrf file for $exp failed" >&2
  return 1
fi
# Apply sample characteristic/factor value fixes to the condensed-sdrf file
applyFixes $exp automatic_fixes_values.txt condensed-sdrf.tsv
if [ $? -ne 0 ]; then
  echo "ERROR: Applying sample characteristic/factor value fixes in sdrf file for $exp failed" >&2
  return 1
fi
