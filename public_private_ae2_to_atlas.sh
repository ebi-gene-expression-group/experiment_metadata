#!/bin/bash
# @author: rpetry
# @date:   7 Aug 2013§

# This script serves to reflect in Atlas private/public experiment status switch on the AE2 side.
IFS="
"

if [ $# -ne 5 ]; then
        echo "Usage: $0 ATLAS_URL AE2_URL ATLAS_ADMIN_UID ATLAS_ADMIN_PASS ERROR_NOTIFICATION_EMAILADDRESS" >&2
        exit 1;
fi

ATLAS_URL=$1
AE2_URL=$2
ATLAS_ADMIN_UID=$3
ATLAS_ADMIN_PASS=$4
ERROR_NOTIFICATION_EMAILADDRESS=$5

SUCCESS_HTTP_RESPONSE=200
process_file="$HOME/tmp/publicprivate_ae2_to_atlas."`eval date +%Y%m%d`
rest_results_file=$process_file.rest_results
all_atlas_experiments_file=$process_file.all_atlas_exps
all_ae2_experiments_file=$process_file.all_ae2_exps
exps_not_in_ae2=$process_file.$$.exps_not_in_ae2
exps_public_in_atlas=$process_file.$$.exps_public_in_atlas
exps_private_in_atlas=$process_file.$$.exps_private_in_atlas

expsDir=$ATLAS_EXPS
if [ "$ATLAS_URL" == "ves-hx-77.ebi.ac.uk:8080/gxa" ]; then
    expsDir=${expsDir}_test
fi

# Remove any previous $process_file
rm -rf $process_file
rm -rf $process_file.log
touch $process_file.log

# Fetch the list of experiment privacies in Atlas.
 # we will removing PanCancer experiments (E-MTAB-5200 and E-MTAB-5423) as they dont want to be checked, as we want to keep them public
 # in Atlas as they are officially private in ArrayExpress
fetch_experiment_privacy_from_atlas.pl | grep -v "PROT\|ENAD" | grep -v "E-MTAB-5200\|E-MTAB-5423" > $all_atlas_experiments_file
if [ $? -ne 0 ]; then
    echo "Error getting privacy statuses from Atlas to sync with ArrayExpress." >> $process_file.log
    mailx -s "[gxa/cron] Error getting privacy statuses from Atlas to sync with ArrayExpress." ${ERROR_NOTIFICATION_EMAILADDRESS} < $process_file.log
    exit 1
fi

num_all_atlas_exps=`cat $all_atlas_experiments_file | wc -l`
echo "Found $num_all_atlas_exps experiments in $ATLAS_URL. Processing..."  >> $process_file.log

# Retrieve all AE2 experiments into $all_ae2_experiments_file (ssv)
curl -X GET -s "http://${AE2_URL}/api/privacy.txt" > $all_ae2_experiments_file
if [ ! -f $all_ae2_experiments_file ]; then
   err_msg="Updating private/public status of experiments on ${ATLAS_URL} was unsuccessful due failure to retrieve all AE2 experiments"
   echo $err_msg >> $process_file.log
   mailx -s "[gxa/cron] $err_msg" ${ERROR_NOTIFICATION_EMAILADDRESS} < $process_file.log
fi

for l in $(cat "$all_atlas_experiments_file"); do
    exp_accession=`echo $l | awk -F"\t" '{print $1}'`
    atlas_private_flag=`echo $l | awk -F"\t" '{print $2}'`
    if [ ! -z $exp_accession ]; then
          # Now get the experiments private/public status in AE2
          # E.g. line in $all_ae2_experiments_file: accession:E-MEXP-31 privacy:public releasedate:2004-03-01
          ae2_experiment=`grep -P "accession:$exp_accession\t" $all_ae2_experiments_file`
          if [ ! -z "$ae2_experiment" ]; then
               ae2_public_status=`echo $ae2_experiment | grep -Po 'privacy:public'`
               ae2_private_status=`echo $ae2_experiment | grep -Po 'privacy:private'`
               if [ ! -z $ae2_public_status ]; then
                  if [ $atlas_private_flag == "true" ]; then
                        # Experiment public in AE2 and private in Atlas - make it public in Atlas
                        echo -e "\n$exp_accession - AE2: public; Atlas: private - status change in Atlas: private->public"  >> $process_file.log
		                    curl -u ${ATLAS_ADMIN_UID}:${ATLAS_ADMIN_PASS} -X GET -s -w %{http_code} "http://${ATLAS_URL}/admin/experiments/${exp_accession}/update_public" >> $process_file.log
                        echo "$exp_accession" >> $exps_public_in_atlas
		                    # At this point, the last line of $process_file.log should contain something like 'Experiment E-GEOD-10406 successfully updated.200'
		                    # where 200 is the http response code - fail if the response code is not $SUCCESS_HTTP_RESPONSE
		                    httpCode=`tail -1 $process_file.log | awk -F"]" '{print $NF}'`
		                      if [ "$httpCode" -ne "$SUCCESS_HTTP_RESPONSE" ]; then
			                         err_msg="http://${ATLAS_URL}/admin/experiments/${exp_accession}/update_public returned non-success http code: $httpCode. Failing..." >> $process_file.log
			                         echo $err_msg >> $process_file.log
			                         mailx -s "[gxa/cron] $err_msg" ${ERROR_NOTIFICATION_EMAILADDRESS} < $process_file.log
			                         exit 1
		                      fi
                  fi
		            # Make the experiments public ftp directory readable by public
		              chmod 755 $expsDir/$exp_accession
              elif [ ! -z $ae2_private_status ]; then
                   if [ $atlas_private_flag == "false" ]; then
                      # Experiment private in AE2 and public in Atlas - make it private in Atlas
                      echo -e "\n$exp_accession - AE2: private; Atlas: public - status change in Atlas: public->private" >> $process_file.log
		                  curl -u ${ATLAS_ADMIN_UID}:${ATLAS_ADMIN_PASS} -X GET -s -w %{http_code} "http://${ATLAS_URL}/admin/experiments/${exp_accession}/update_private" >> $process_file.log
                      echo "$exp_accession" >> $exps_private_in_atlas
		                  httpCode=`tail -1 $process_file.log | awk -F"]" '{print $NF}'`
		                  if [ "$httpCode" -ne "$SUCCESS_HTTP_RESPONSE" ]; then
		                        err_msg="http://${ATLAS_URL}/admin/experiments/${exp_accession}/update_private returned non-success http code: $httpCode. Failing..." >> $process_file.log
		                        echo $err_msg >> $process_file.log
		                        mailx -s "[gxa/cron] $err_msg" ${ERROR_NOTIFICATION_EMAILADDRESS} < $process_file.log
		                        exit 1
                      fi	  
                   fi
		            # Make the experiments public ftp directory unreadable by public
		              chmod 750 $expsDir/$exp_accession	
               fi
          else
             err_msg="Updating private/public status of experiments on ${ATLAS_URL} unsuccessful: failed to find $exp_accession in AE2"
             echo $err_msg >> $process_file.log
             echo "$exp_accession" >>  $exps_not_in_ae2
          fi
    else
          err_msg="Updating private/public status of experiments on ${ATLAS_URL} failed due to incorrect format of Atlas API call output"
          echo $err_msg >> $process_file.log
          mailx -s "[gxa/cron] $err_msg" ${ERROR_NOTIFICATION_EMAILADDRESS} < $process_file.log
          exit 1
    fi
done

# Notify of any experiments which gone public from private in Atlas.
if [ -e $exps_public_in_atlas ]; then
   mailx -s "[gxa/cron] Experiments status change in Atlas: private->public" ${ERROR_NOTIFICATION_EMAILADDRESS} < $exps_public_in_atlas
fi

# Notify of any experiments which gone private from public in Atlas.
if [ -e $exps_private_in_atlas ]; then
   mailx -s "[gxa/cron] Experiments status change in Atlas: public->private" ${ERROR_NOTIFICATION_EMAILADDRESS} < $exps_private_in_atlas
fi

echo -e "\nProcessed $num_all_atlas_exps experiments successfully" >> $process_file.log

# Remove auxiliary file created by this script
rm -rf $all_atlas_experiments_file
rm -rf $all_ae2_experiments_file
rm -rf $exps_not_in_ae2
rm -rf $rest_results_file
rm -rf $exps_public_in_atlas
rm -rf $exps_private_in_atlas
