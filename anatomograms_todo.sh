#!/usr/bin/env bash

# This script identifies organisms with missing anatomograms, and for organisms with anatomograms already - tissues not yet included in anatomograms

if [ $# -lt 2 ]; then
  echo "Usage: $0 atlasCheckoutRoot notificationEmail"
  exit 1
fi 

atlasCheckoutRoot=$1
notificationEmail=$2

function lowercase_first_letter {
    arg=$1
    echo -n $arg | sed 's/\(.\).*/\1/' | tr "[:upper:]" "[:lower:]" | tr -d "\n"; echo -n $arg | sed 's/.\(.*\)/\1/'
}

IFS="
"
aux="$FG_ATLAS_ISILON_HOMES/"`whoami`"/tmp/anatomograms_todo.$$.aux"
echo -e "cervix\nmammary\nmammary gland\nanimal ovary\nplacenta\nendometrium\nvagina\nuterus\nfallopian tube" > $aux.female_only
echo -e "testis\nprostate\ntestes\npenis\nepididymis" > $aux.male_only

# This script is currently not clever enough to which species in multi-species experiment have which tissue. Since such experiments are more of an exception than the rule (and genereally we will attempt to split such experiments into single-species experiments going forward), for now we will just use an exceptions list covering the current experiments:
echo -e "E-GEOD-41338\tliver\tMISSING_FROM anolis_carolinensis.svg\nE-GEOD-41338\tliver\tMISSING_FROM tetraodon_nigroviridis.svg\nE-GEOD-30352\tprefrontal cortex\tMISSING_FROM mouse.svg\nE-GEOD-30352\tfrontal lobe\tMISSING_FROM mouse.svg\nE-GEOD-30352\ttemporal lobe\tMISSING_FROM mouse.svg" | sort -k1,1 > $aux.exceptions

assaygroupsdetailsFilePath=~/tmp/assaygroupsdetails.tsv
curl -s -o $assaygroupsdetailsFilePath "http://wwwdev.ebi.ac.uk/gxa/api/assaygroupsdetails.tsv"
# Mapping between organism name and svg
organismToSvg=${atlasCheckoutRoot}/web/src/main/resources/configuration.properties
# Check out directory containing anatomogram svgs
svgDir=${atlasCheckoutRoot}/web/src/main/webapp/resources/svg
# Get all organism names 
grep '^organism.' $organismToSvg | sed 's|\\||g' > $aux.config
# Remove any auxiliary files
rm -rf $aux.svgs

# Obtain mapping between experiment accessions and their corresponding svgs ($aux.svgs)
# Report organisms with missing svgs (directly into $aux.email_report)
for l in $(grep -P '\torganism\t' $assaygroupsdetailsFilePath | grep -v 'organism part' | awk -F"\t" '{print $1"\t"$5}' | sort | uniq); do
    expAcc=`echo $l | awk -F"\t" '{print $1}'`
    grep $expAcc $assaygroupsdetailsFilePath | grep factor | grep -P '\torganism part\t' > /dev/null
    if [ $? -eq 0 ]; then 
	# If this is a tissue experiment (i.e. one for which we need an anatomogram in the first place)
	organism=`echo $l | awk -F"\t" '{print $2}' | awk '{print $1" "$2}'`
	lcOrganism=`lowercase_first_letter "$organism"`
	foundSvg=0
	for svg in $(grep "\.$lcOrganism" $aux.config | awk '{print $NF}'); do
    	    echo -e "$expAcc\t$svg" >> $aux.svgs
	    foundSvg=1
	done
	if [ $foundSvg -ne 1 ]; then
	    echo "$organism SVG_MISSING" >> $aux.email_report
	fi  
    fi
done 
sort $aux.svgs | uniq > $aux.svgs.tmp
mv $aux.svgs.tmp $aux.svgs
sort $aux.email_report | uniq > $aux.email_report.tmp
mv $aux.email_report.tmp $aux.email_report

# Now for all experiments with organisms for which we have an svg, report all cases of tissues 
# which either don't have an EFO mapping; or they are mapped to EFO, but are not in svg
for l in $(cat $aux.svgs); do
   expAcc=`echo $l | awk -F"\t" '{print $1}'`
   svg=`echo $l | awk -F"\t" '{print $2}'`    
   for l1 in $(grep -P "$expAcc\t" $assaygroupsdetailsFilePath | grep -P "\torganism part\t"); do
       tissue=`echo $l1 | awk -F"\t" '{print $5}'`
       efoUrl=`echo $l1 | awk -F"\t" '{print $6}'`
       if [ ! -z "$efoUrl" ]; then
           efoID=`echo $efoUrl | awk -F"/" '{print $NF}'`
	   grep $efoID $svgDir/$svg > /dev/null
	   if [ $? -ne 0 ]; then
	      echo $svg | grep -P '\_female' > /dev/null
	      if [ $? -eq 0 ]; then
	      	    grep $tissue $aux.male_only > /dev/null
		    if [ $? -ne 0 ]; then  
	      	         echo -e "$expAcc\t$tissue\tMISSING_FROM $svg"
		    fi
	      fi
	      echo $svg | grep -P '\_male' > /dev/null
	      if [ $? -eq 0 ]; then
	      	    grep $tissue $aux.female_only > /dev/null
		    if [ $? -ne 0 ]; then  
	      	         echo -e "$expAcc\t$tissue\tMISSING_FROM $svg"
		    fi
	      fi
	      echo $svg | grep -vP '\_male|\_female' > /dev/null
	      if [ $? -eq 0 ]; then
	      	    echo -e "$expAcc\t$tissue\tMISSING_FROM $svg"
	      fi
	   fi 
       elif [ ! -z "$tissue" ]; then 
           echo -e "$expAcc\t$tissue\tNO_EFO_MAPPING ($svg)"
       fi 
   done
done | sort -k1,1 | uniq > $aux.missing_tissues_report

# Now remove exceptions from the final report
comm -3 $aux.missing_tissues_report $aux.exceptions >> $aux.email_report

if [ -s $aux.email_report ]; then
     mailx -s "[atlas3/cron]: Anatomograms report" $notificationEmail < $aux.email_report
 fi 

# Auxiliary files clean up
rm -rf $aux.*
