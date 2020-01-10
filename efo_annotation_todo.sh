#!/usr/bin/env bash

# This script identifies property values with missing EFO annotation for all experiments in Atlas - with the exception of properties/values in $exclusionRegex (see below)

if [ $# -lt 1 ]; then
  echo "Usage: $0 notificationEmail"
  exit 1
fi 

notificationEmail=$1

IFS="
"
tmp="/nfs/public/rw/homes/fg_atlas/tmp"

aux="$$.aux"

# Property types/values to exclude from the EFO coverage report - we're not aiming to map these to EFO
exclusionRegex="\tage\t|\tbiosource provider\t|\tbiosource_provider\t|\tblock\t|\tbody weight\t|\tclinical history\t|\tclinical information\t|\tclinical_history\t|\tclinical_information\t|\tcold\t|\texcercise\t|\tgenotype\t|\tindividual\t|\tlast follow up\t|\tmass\t|\tmitotic rate\t|\tpassage\t|\treplicate\t|\tRNA interference\t|\tsampling time point\t|\ttime\t|\ttumor mass\t|\ttumor size\t|\tunknown\t"

allCnt=0
rm -rf ${tmp}/all_vals.$file.$aux
for f in assaygroupsdetails.tsv contrastdetails.tsv; do
    curl -s -o ~/tmp/$f "http://wwwdev.ebi.ac.uk/gxa/api/$f"
    if [ "$f" == "assaygroupsdetails.tsv" ]; then
	cat ~/tmp/$f | grep -vP "$exclusionRegex" | awk -F"\t" '{print $1"\t"$4"\t"$5"\t"$6}' | sort | uniq > ${tmp}/all_vals.$f.$aux
    else 
	cat ~/tmp/$f | grep -vP "$exclusionRegex" | awk -F"\t" '{print $1"\t"$5"\t"$6"\t"$7}' | sort | uniq > ${tmp}/all_vals.$f.$aux
    fi
    cnt=`wc -l ${tmp}/all_vals.$f.$aux | awk '{print $1}'`
    allCnt=$[$allCnt+$cnt]
    grep -P '\t$' ${tmp}/all_vals.$f.$aux >> ${tmp}/missing_efo_annot_report.$aux
done

sort -k2,2 -k3,3 ${tmp}/missing_efo_annot_report.$aux > ${tmp}/missing_efo_annot_report.$aux.tmp
mv ${tmp}/missing_efo_annot_report.$aux.tmp ${tmp}/missing_efo_annot_report.$aux

missingCnt=`wc -l ${tmp}/missing_efo_annot_report.$aux | awk '{print $1}'`
annotatedCnt=$[$allCnt-$missingCnt]
efoCoveragePct=`echo "scale=0; $annotatedCnt*100/$allCnt" | bc -l`


if [ -s ${tmp}/missing_efo_annot_report.$aux ]; then 
      mailx -s "[atlas3/cron]: EFO coverage report ($efoCoveragePct%) " $notificationEmail < ${tmp}/missing_efo_annot_report.$aux
fi 

# Auxiliary files clean up
echo "efoCoveragePct = $efoCoveragePct%"
rm -rf ${tmp}/*.$aux