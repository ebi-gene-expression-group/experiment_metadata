#!/bin/bash
# @author: rpetry, mkeays
# @date:   05 Aug 2013

# This script updates all ontology mappings in condensed SDRF files, and then
# updates all experiment designs on ves-hx-76:8080


# Source script from the same (prod or test) Atlas environment as this script
scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source ${scriptDir}/../bash_util/generic_routines.sh

# For condense_sdrf.pl, get_experiment_type_from_xml.pl
export PATH=${scriptDir}:${scriptDir}/../db/scripts:$PATH

# Check that relevant env vars are set
[ -z ${LSF_QUEUE+x} ] && echo "Env var LSF_QUEUE with a valid lsf queue name needs to be defined." && exit 1

if [ $# -lt 1 ]; then
  echo "# First export relevant variables: "
  echo "# LOG_UPDATE_EXPERIMENT_METADATA"
  echo "# LSF_QUEUE"
  echo "Usage: $0 NOTIFICATION_EMAILADDRESS MODE" >&2
  echo "Usage: $0 suhaib@ebi.ac.uk atlas" >&2
  exit;
fi

notifEmail=$1
mode=$2

checkZooma() {
  log=$1
  httpResponse=`curl -o /dev/null -X GET -s -w %{http_code} "${ZOOMA_API_BASE}/server/metadata"`
  if [ "$httpResponse" -ne 200 ]; then
    echo "ERROR: ${zoomaUrl}/v2/api/server/metadata returned a non-success http code: $httpResponse " >> $log
    return 1
  fi
}

#### Main code starts
today="`eval date +%Y-%m-%d`"
# Log is setable from the outside through LOG_UPDATE_EXPERIMENT_METADATA
log=${LOG_UPDATE_EXPERIMENT_METADATA:-"$FG_ATLAS_TMP/${mode}_refresh_experiment_metadata.$today.log"}
zoomaMappingReport="$FG_ATLAS_TMP/${mode}_zooma_mapping_report.$today.tsv"
MAX_TIME=1800
SUCCESS_HTTP_RESPONSE=200

MEM_FOR_APPLY_FIXES=${MEM_FOR_APPLY_FIXES:-16384}

rm -rf $log
checkZooma $log
if [ $? -ne 0 ]; then
  echo "ERROR: Zooma doesn't respond correctly" >> $log
  exit 1
fi

# Make sure that the number of zoomifications lsf jobs is restricted to 25
bgmod -L 25 /ATLAS3_ZOOMA > /dev/null 2>&1

if [ "$mode" == "atlas" ]; then
  workingDir=$ATLAS_EXPS
elif [ "$mode" == "single_cell" ]; then
  [ -z ${ATLAS_SC_EXPERIMENTS+x} ] && echo "Env var ATLAS_SC_EXPERIMENTS pointing to the directory for Atlas SC Experiments needs to be defined to run with SC data." && exit 1
  workingDir=$ATLAS_SC_EXPERIMENTS
elif [ "$mode" == "irap_single_lib" ]; then
  workingDir=$IRAP_SINGLE_LIB/zoomage
else
  echo "ERROR: mode: $mode not recognised"
  exit 1
fi

pushd $workingDir

echo "About to download sdrf and idf files for all experiments..." >> $log

numLsfJobsSubmitted=0

echo "Removing auxiliary files..." >> $log

for e in $(ls | grep E- ); do
  rm -rf $e/condense_sdrf.???
  rm -rf $e/fixes.???
  rm -rf $e/$e-zoomifications-log.tsv
done

rm -rf $zoomaMappingReport.aux

# This script is currently submitting too many jobs that take very short time,
# we would be better off by submitting many runs (100?) per lsf job.
# Unfortunately, the condense_sdrf.out and condense_sdrf.err are being used later
# to diagnose success and failure.
for f in $(ls | grep E-); do
  # Process only directories
  if [ ! -d $f ]; then
    continue
  fi

  # Run condense_sdrf.pl with options to map terms with Zooma (-z) and import
  # the IDF from ArrayExpress load directory (-i).
  if [ "$mode" == "atlas" ]; then

    # Get the experiment type from the experiment config.
    expType=$(get_experiment_type_from_xml.pl $f/$f-configuration.xml)
    if [ $? -ne 0 ]; then
      echo "ERROR: failed to get $f experiment type from XML config. Cannot generate condensed SDRF."
      continue
    fi

    if [[ $expType == *baseline ]]; then
      bsub -q $LSF_QUEUE -g /ATLAS3_ZOOMA -cwd "$workingDir" -o $f/condense_sdrf.out -e $f/condense_sdrf.err "condense_sdrf.pl -e $f -f $f/$f-factors.xml -z -i -o $f"
    else
      bsub -q $LSF_QUEUE -g /ATLAS3_ZOOMA -cwd "$workingDir" -o $f/condense_sdrf.out -e $f/condense_sdrf.err "condense_sdrf.pl -e $f -z -i -o $f"
    fi

  elif [ "$mode" == "single_cell" ]; then
    export EXP_ID=$f
    bsub -q $LSF_QUEUE -g /ATLAS3_ZOOMA -cwd "$workingDir" -o $f/condense_sdrf.out -e $f/condense_sdrf.err "single_cell_condensed_sdrf.sh"

  elif [ "$mode" == "irap_single_lib" ]; then
    # Also collect biological replicate IDs for irap_single_lib mode.
    bsub -q $LSF_QUEUE -g /ATLAS3_ZOOMA -cwd "$workingDir" -o $f/condense_sdrf.out -e $f/condense_sdrf.err "condense_sdrf.pl -e $f -z -b -i -o $f"
  else
    echo "Mode $mode not recognised."
    exit 1
  fi

  numLsfJobsSubmitted=$[$numLsfJobsSubmitted+1]

done


# Now monitor the runs for all experiments - until all jobs are completed (successfully or failed)
# NOTE: we had some issues with *-zoomifications-log.tsv files missing and
# negative job counts in the logs. So we decided not to remove the LSF logs or
# zoomifications logs during the following while loop and instead leave them
# there until afterwars, and then delete them. This seems to make things work
# as expected though it's not clear why yet.

jobCnt=0
successfulCnt=0

while [ $jobCnt -lt $numLsfJobsSubmitted ]; do

  # calling ls E-* repeatedly is probably a bad idea given slow file system
  # and large number of files in the experiments folder
  ls E-*/condense_sdrf.out > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    if [ $jobCnt -eq 0 ]; then
      echo "No jobs started yet - sleeping for 1 min..." >> $log
      sleep 60
      continue
    fi
  fi

  # and here we go again with ls E-*...
  for lsfOut in $(ls E-*/condense_sdrf.out); do

    lsfErr=$(echo $lsfOut | sed 's|.out$||').err
    expAcc=$(echo $lsfOut | awk -F"/" '{print $1}')
    grep 'Exited with' $lsfOut >> /dev/null

    if [ $? -eq 0 ]; then
      jobCnt=$[$jobCnt+1]

      # Log error condition, but don't fail - condense SDRF without Zooma mapping.
      errors=$(cat $lsfErr)
      errors="$errors"`grep "Failed to query ZOOMA" $lsfOut | grep ":ERROR"`
      errors="$errors"`grep "Exception:" $lsfOut`
      errors="$errors"`grep "^ERROR" $lsfOut`

      if [ ! -z "$errors" ]; then
        echo -e "\n\nErrors for ${expAcc} (condense_sdrf.pl call FAILED): " >> $log
        echo -e $errors >> $log
      fi

      echo "Condensing SDRF $expAcc without Zooma mapping..." >> $log

      if [ "$mode" == "atlas" ]; then
        # Get the experiment type from the experiment config.
        expType=$(get_experiment_type_from_xml.pl $expAcc/$expAcc-configuration.xml)
        if [ $? -ne 0 ]; then
          echo "ERROR: failed to get $expAcc experiment type from XML config. Cannot generate condensed SDRF."
          exit 1
        fi

        if [[ $expType == *baseline ]]; then
          condense_sdrf.pl -e $expAcc -f $expAcc/$expAcc-factors.xml -i -o $expAcc
        else
          condense_sdrf.pl -e $expAcc -i -o $expAcc
        fi

      elif [ "$mode" == "single_cell" ]; then
        export EXP_ID=$expAcc
        export SKIP_ZOOMA=yes
        single_cell_condensed_sdrf.sh

      elif [ "$mode" == "irap_single_lib" ]; then
        condense_sdrf.pl -e $expAcc -i -o $expAcc -b
      fi

      if [ $? -ne 0 ]; then
        echo -e "\nFailed to condense SDRF for $expAcc without Zooma mappings, following error from trying with Zooma mappings" >> $log
      else
        echo "Done" >> $log
      fi

      rm -rf $lsfOut
      rm -rf $lsfErr

    else

      grep 'Successfully completed.' $lsfOut > /dev/null

      if [ $? -eq 0 ]; then
        jobCnt=$[$jobCnt+1]
        successfulCnt=$[$successfulCnt+1]
        expAcc=$(echo $lsfOut | awk -F"/" '{print $1}')
        cat $expAcc/$expAcc-zoomifications-log.tsv >> $zoomaMappingReport.aux
        rm -rf $expAcc/$expAcc-zoomifications-log.tsv

        errors=$(cat $lsfErr)
        errors="$errors"$(grep "Failed to query ZOOMA" $lsfOut | grep ":ERROR")
        errors="$errors"$(grep "Exception:" $lsfOut)
        errors="$errors"$(grep "^ERROR" $lsfOut)

        if [ ! -z "$errors" ]; then
          echo -e "\n\nErrors for ${expAcc} (condense_sdrf.pl call SUCCESSFUL): " >> $log
          echo -e $errors >> $log
        fi

        rm -rf $lsfOut
        rm -rf $lsfErr
      fi
    fi
  done

  if [ $jobCnt -eq $numLsfJobsSubmitted ]; then
    echo -e "\n\n${successfulCnt} out of $numLsfJobsSubmitted condense_sdrf.pl jobs have succeeded" >> $log
  else
    inProgressNum=$[$numLsfJobsSubmitted-$jobCnt]
    echo "$inProgressNum of $numLsfJobsSubmitted tasks are still in progress - sleeping for 1 min..." >> $log
    sleep 60
  fi
done

echo "All condense_sdrf tasks now done" >> $log
echo "Updated condensed sdrf and idf files for all experiments" >> $log


echo "About to apply automatic fixes to all imported sdrf and idf files" >> $log
numLsfJobsSubmitted=0

for e in $(ls | grep E-); do
  # Process only directories
  if [ ! -d $e ]; then
    continue
  fi

  # This script is currently submitting too many jobs that take very short time,
  # we would be better off by submitting many runs (100?) per job
  bsub -q $LSF_QUEUE -M $MEM_FOR_APPLY_FIXES -cwd "$workingDir" -o $e/fixes.out -e $e/fixes.err "source ${scriptDir}/../bash_util/generic_routines.sh; applyAllFixesForExperiment $e"
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to submit fixes job for experiment $e" >> $log
    exit 1
  fi
  numLsfJobsSubmitted=$[$numLsfJobsSubmitted+1]
done

# Now monitor the fixes run for all experiments - until all fixes jobs are completed (successfully or failed)
jobCnt=0
successfulCnt=0

while [ $jobCnt -lt $numLsfJobsSubmitted ]; do

  ls E-*/fixes.out > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    if [ $jobCnt -eq 0 ]; then
      echo "No jobs started yet - sleeping for 1 min..." >> $log
      sleep 60
      continue
    fi
  fi

  for lsfOut in $(ls E-*/fixes.out); do
    lsfErr=$(echo $lsfOut | sed 's|.out$||').err
    expAcc=$(echo $lsfOut | awk -F"/" '{print $1}')
    grep 'Exited with' $lsfOut > /dev/null

    if [ $? -eq 0 ]; then
      jobCnt=$[$jobCnt+1]
      errors=$(cat $lsfErr)
      if [ ! -z "$errors" ]; then
        echo -e "\n\nErrors for ${expAcc} (Fixes call FAILED): " >> $log
        echo -e $errors >> $log
      fi
      rm -rf $lsfOut
      rm -rf $lsfErr
    else
      grep 'Successfully' $lsfOut > /dev/null
      if [ $? -eq 0 ]; then
        jobCnt=$[$jobCnt+1]
        successfulCnt=$[$successfulCnt+1]
        rm -rf $lsfOut
        rm -rf $lsfErr
      fi
    fi
  done

  if [ $jobCnt -eq $numLsfJobsSubmitted ]; then
    echo -e "\n\n${successfulCnt} out of $numLsfJobsSubmitted fixes jobs have succeeded" >> $log
  else
    inProgressNum=$[$numLsfJobsSubmitted-$jobCnt]
    echo "$inProgressNum of $numLsfJobsSubmitted tasks are still in progress - sleeping for 1 min..." >> $log
    sleep 60
  fi
done

echo "All fixes tasks now done" >> $log


if [ -s "$log" ]; then
  mailx -s "[${mode}/cron] Experiment metadata refresh for $today" ${notifEmail} < $log
fi

if [ ! -s "$zoomaMappingReport.aux" ]; then
  echo "ERROR: Something went wrong with condense_sdrf.pl run with Zooma mappings - no report is available" >> $log
  exit 1
else
  # Now break down $zoomaMappingReport.aux into four report files: automatic, excluded, noresults, requirescuration
  section=AUTOMATIC
  head -1 $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="SEMANTIC_TAG" -v col4="STUDY" -v col5="BIOENTITY" -v col6="ONTOLOGY_LABEL|ZOOMA_VALUE" -v col7="PROP_VALUE_MATCH" -v col8="Category of Zooma Mapping" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i;if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;if($i==col6)c6=i;if($i==col7)c7=i;if($i==col8)c8=i;}} NR==1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5 "\t" $c6 "\t" $c7 "\t" $c8}' > $zoomaMappingReport.$section.tsv
  # Note below that intended sort is: primary by PROP_VALUE_MATCH, secondary by property "PROPERTY_TYPE", and tertiary by "PROPERTY_VALUE"
  cat $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="SEMANTIC_TAG" -v col4="STUDY" -v col5="BIOENTITY" -v col6="ONTOLOGY_LABEL|ZOOMA_VALUE" -v col7="PROP_VALUE_MATCH" -v col8="Category of Zooma Mapping" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;if($i==col6)c6=i;if($i==col7)c7=i;if($i==col8)c8=i;}} NR>1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5 "\t" $c6 "\t" $c7 "\t" $c8}' | grep -P "\t$section" | sed 's|null||g' | sort -t"`echo -e \"\t\"`" -k5,5 -k2,2 -k3,3 >> $zoomaMappingReport.$section.tsv

  section=EXCLUDED
  head -1 $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="STUDY" -v col4="Category of Zooma Mapping" -v col5="Basis for Exclusion" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;}} NR==1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5}' > $zoomaMappingReport.$section.tsv
  # Note below that intended sort is: primary by property "PROPERTY_TYPE", and secondary by "PROPERTY_VALUE"
  cat $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="STUDY" -v col4="Category of Zooma Mapping" -v col5="Basis for Exclusion" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;}} NR>1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5}' | grep -P "\t$section" | sed 's|null||g' | sort -t"`echo -e \"\t\"`" -k1,1 -k2,2 >> $zoomaMappingReport.$section.tsv

  section=NO_RESULTS
  head -1 $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="STUDY" -v col4="BIOENTITY" -v col5="Category of Zooma Mapping" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;}} NR==1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5}' > $zoomaMappingReport.$section.tsv
  # Note below that intended sort is: primary by property "PROPERTY_TYPE", and secondary by "PROPERTY_VALUE"
  cat $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="STUDY" -v col4="BIOENTITY" -v col5="Category of Zooma Mapping" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;}} NR>1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5}' | grep -P "\t$section" | sed 's|null||g' | sort -t"`echo -e \"\t\"`" -k1,1 -k2,2 >> $zoomaMappingReport.$section.tsv

  section=REQUIRES_CURATION
  head -1 $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="SEMANTIC_TAG" -v col4="STUDY" -v col5="BIOENTITY" -v col6="ONTOLOGY_LABEL|ZOOMA_VALUE" -v col7="PROP_VALUE_MATCH" -v col8="Category of Zooma Mapping" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;if($i==col6)c6=i; if($i==col7)c7=i; if($i==col8)c8=i;}} NR==1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5 "\t" $c6 "\t" $c7 "\t" $c8}' | sed 's|null||g' > $zoomaMappingReport.$section.tsv
  # Note below that intended sort is: primary by PROP_VALUE_MATCH, secondary by property "PROPERTY_TYPE".
  cat $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="SEMANTIC_TAG" -v col4="STUDY" -v col5="BIOENTITY" -v col6="ONTOLOGY_LABEL|ZOOMA_VALUE" -v col7="PROP_VALUE_MATCH" -v col8="Category of Zooma Mapping" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;if($i==col6)c6=i; if($i==col7)c7=i; if($i==col8)c8=i;}} NR>1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5 "\t" $c6 "\t" $c7 "\t" $c8}' | grep -P "\t$section" | sed 's|null||g' | sort -t"`echo -e \"\t\"`" -k7,7 -k2,2 >> $zoomaMappingReport.$section.tsv

  # Copy reports to $targetDir
  if [ "$mode" == "atlas" ]; then
    targetDir=$ATLAS_FTP/curation/zoomage_reports/${today}
  elif [ "$mode" == "single_cell" ]; then
    targetDir=$ATLAS_FTP/curation/zoomage_reports/single_cell/${today}
  elif [ "$mode" == "irap_single_lib" ]; then
    targetDir=$IRAP_SINGLE_LIB/zoomage/reports/${today}
  else
    echo "ERROR: mode: $mode not recognised"
    exit 1
  fi
  mkdir -p $targetDir
  cp $zoomaMappingReport.AUTOMATIC.tsv $zoomaMappingReport.EXCLUDED.tsv $zoomaMappingReport.NO_RESULTS.tsv $zoomaMappingReport.REQUIRES_CURATION.tsv ${targetDir}/

  if [ ! -z ${previousRunDate+x} ] && [ -d ${targetDir}/../$previousRunDate ]; then
    # Calculating new lines not previously seen
    previousCurated=${targetDir}/../${previousRunDate}/atlas_zooma_mapping_report.${previousRunDate}.tsv.REQUIRES_CURATION.tsv
    newToCurate=${targetDir}/atlas_zooma_mapping_report.${today}.tsv.REQUIRES_CURATION.tsv
    # Compare based on fields Property value ($2), semantic tag ($3), Ontology label / Zooma mapping ($6)
    awk -F'\t' 'NR==FNR{e[$2$3$6]=1;next};!e[$2$3$6]' $previousCurated $newToCurate > ${targetDir}/atlas_zooma_mapping_report.${today}.tsv.REQUIRES_CURATION_NEW_LINES.tsv
  else
    echo "Variable previousRunDate value \"$previousRunDate\" does not take us to previous run, so no new lines" >> $log
  fi

  # Mail out the Zoomification reports location
  echo -e "Dear curators,\n      Please find the Zooma mapping reports for the latest run for $today in $targetDir.\n\nGreetings from your friendly neighbourhood cron." | mutt -s "[${mode}/cron] Zooma mapping report is available in $targetDir" -- ${notifEmail}
  pushd $targetDir/../
  current_run=$(ls -ltr | grep -v previous_run | grep -e '[[:digit:]]\{4\}-[[:digit:]]\{2\}' | tail -n 1 | awk '{ print $9 }')
  rm -f previous_run
  ln -s $current_run previous_run
  popd
fi



# Update all the experiment designs in Atlas.
#if [ "$mode" == "atlas" ]; then
#    update_all_atlas_designs.pl
#fi
