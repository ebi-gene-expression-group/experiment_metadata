#!/bin/bash
# @author: rpetry
# @date:   30 APR 2024

# Source script from the same (prod or test) Atlas environment as this script
scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source ${scriptDir}/../bash_util/generic_routines.sh
atlasEnv=`atlas_env`

# Get the first argument (email address(es) to send report to).
NOTIFY_EMAILADDRESS=$1

# If we didn't get any email addresses, default to this one.
if [ -z "$NOTIFY_EMAILADDRESS" ]; then
    NOTIFY_EMAILADDRESS="mkeays@ebi.ac.uk"
fi

# Start of name for processing files.
process_file="/tmp/find_properties."`eval date +%Y%m%d`

# Filename for report.
report=$process_file.report

# Remove the old report file.
rm -rf $report

# Download the contrast details file.
curl -o /tmp/contrastdetails.tsv -s -X GET "http://wwwdev.ebi.ac.uk/gxa/api/contrastdetails.tsv"

# If the download failed, log and exit.
if [ ! -s "/tmp/contrastdetails.tsv" ]; then
    echo "ERROR: Failed to retrieve http://wwwdev.ebi.ac.uk/gxa/api/contrastdetails.tsv" >> $report
    exit 1
fi

# Download the assay group details file.
curl -o /tmp/assaygroupsdetails.tsv -s -X GET "http://wwwdev.ebi.ac.uk/gxa/api/assaygroupsdetails.tsv"

# If the download failed, log and exit.
if [ ! -s "/tmp/assaygroupsdetails.tsv" ]; then
    echo "ERROR: Failed to retrieve http://wwwdev.ebi.ac.uk/gxa/api/assaygroupsdetails.tsv" >> $report
    exit 1
fi

# Create auxilliary files containing unique property types from the assay group and contrast details files.
cat /tmp/assaygroupsdetails.tsv | awk -F"\t" '{print $4}' | sed -e 's/^[ ]*//' | sed -e 's/[ ]*$//' | sort | uniq > ${process_file}.properties.aux
cat /tmp/contrastdetails.tsv | awk -F"\t" '{print $5}' | sed -e 's/^[ ]*//' | sed -e 's/[ ]*$//' | sort | uniq >> ${process_file}.properties.aux
sort ${process_file}.properties.aux | uniq > ${process_file}.properties 

# Do the same, for the property values (without lines containing "individual").
grep -vP '\tindividual\t' /tmp/assaygroupsdetails.tsv | awk -F"\t" '{print $5}' | sort | uniq > ${process_file}.values.aux
grep -vP '\tindividual\t' /tmp/contrastdetails.tsv | awk -F"\t" '{print $6}' | sort | uniq >> ${process_file}.values.aux    
sort ${process_file}.values.aux | uniq > ${process_file}.values  

# Load near-duplicates properties exceptions (to be excluded from the report) 
if [ -s $ATLAS_PROD/sw/atlasinstall_${atlasEnv}/atlasprod/experiment_metadata/exceptions_properties.txt ]; then
   exceptions_properties=`cat $ATLAS_PROD/sw/atlasinstall_${atlasEnv}/atlasprod/experiment_metadata/exceptions_properties.txt`
fi

# Find all properties with max levenshtein distance of ${max_levenshtein_distance}

# Change internal field separator to newline.
IFS="
"

# Maximum distance between types or values allowed.
max_levenshtein_distance=2

# Delete previous file containing similar property types.
rm -rf ${process_file}.ld${max_levenshtein_distance}.properties

# Go through the propery types...
for property in $(cat "${process_file}.properties"); do  
   
   if [ "${#property}" -gt "${max_levenshtein_distance}" ]; then
       # Compare only strings of length greater than ${max_levenshtein_distance} 
	   # Replace _all_ spaces with nothing, and convert to lower case.
       canonical_previous=`echo ${previous// /} | tr [A-Z] [a-z]`
       canonical_current=`echo ${property// /} | tr [A-Z] [a-z]`

	   # If the previous property is not empty...
       if [ ! -z $canonical_previous ]; then

		  # Get the Levenshtein distance via ldistance.py
		  ld=`$ATLAS_PROD/sw/ldistance.py $canonical_current $canonical_previous`

		  # If it's < the max...
          if [ "$ld" -le "$max_levenshtein_distance" ]; then

			  # Create a tab-delimited string from this property and the previous one.
			  similarity=`echo -e "${previous}\t${property}"`
			  similarity_esc="$(echo "$similarity" | sed 's/[^-A-Za-z0-9_]/\\&/g')" # backslash special characters

			  if [[ $exceptions_properties =~ $similarity_esc ]]; then # If similarity is already tagged as an allowable exception, exclude it from the report
				  : # ignoring $similarity
			  else
				  # Otherwise, add it to the .properties file.
				  echo $similarity >> ${process_file}.ld${max_levenshtein_distance}.properties
			  fi
          fi
       fi
   fi
   # Remember this property type for next iteration.
   previous=$property
done
unset IFS

# Load near-duplicates property values exceptions (to be excluded from the report) 
if [ -s $ATLAS_PROD/sw/atlasinstall_${atlasEnv}/atlasprod/experiment_metadata/exceptions_values.txt ]; then
   exceptions_values=`cat $ATLAS_PROD/sw/atlasinstall_${atlasEnv}/atlasprod/experiment_metadata/exceptions_values.txt`
fi

# Find all property values with max levenshtein distance of ${max_levenshtein_distance}
IFS="
"

# Delete old files.
rm -rf ${process_file}.ld${max_levenshtein_distance}.values.nonuniq
rm -rf ${process_file}.ld${max_levenshtein_distance}.values

# Reset $previous
previous=

for value in $(cat "${process_file}.values"); do
   if [ "${#value}" -gt "${max_levenshtein_distance}" ]; then
       # Compare only strings of length greater than ${max_levenshtein_distance}
       canonical_current=`echo ${value// /} | tr [A-Z] [a-z]`
       canonical_previous=`echo ${previous// /} | tr [A-Z] [a-z]`
       
	   # Remove numbers.
	   nonumbers_current=`echo ${value// /} | sed 's|[0-9.]*||g'`
       nonumbers_previous=`echo ${previous// /} | sed 's|[0-9.]*||g'`

	   if [ ! -z $nonumbers_current ]; then
         if [ ! -z $nonumbers_previous ]; then 	   
           if [ $nonumbers_current != $nonumbers_previous ]; then # Don't report number-only differences
             
			 # Get the Levenshtein distance via ldistance.py.
			 ld=`$ATLAS_PROD/sw/ldistance.py $canonical_current $canonical_previous`

             if [ "$ld" -le "$max_levenshtein_distance" ]; then
	           if [ $previous != $value ]; then
	             similarity=`echo -e "${previous}\t${value}"`
	             similarity_esc="$(echo "$similarity" | sed 's/[^-A-Za-z0-9_'\''<>]/\\&/g')" # backslash special characters (note exclusion of single quote and <>)
	             if [[ $exceptions_values =~ $similarity_esc ]]; then # If similarity is already tagged as an allowable exception, exclude it from the report
		           : # ignoring $similarity
	             else
		           echo $similarity >> ${process_file}.ld${max_levenshtein_distance}.values.nonuniq
	             fi
	           fi
             fi
           fi
	     fi
       fi
   fi
   # Remember this value for next time.
   previous=$value
done
unset IFS

# If the file with non-unique similar property values exists and is a regular file, put the unique ones into a new file.
if [ -f ${process_file}.ld${max_levenshtein_distance}.values.nonuniq ]; then 
    cat ${process_file}.ld${max_levenshtein_distance}.values.nonuniq | sort | uniq > ${process_file}.ld${max_levenshtein_distance}.values
fi 

# If the file with similar property types exists and has size > 0, add them to the report.
if [ -s ${process_file}.ld${max_levenshtein_distance}.properties ]; then
    echo "Near duplicate property names: " >> $report
    cat ${process_file}.ld${max_levenshtein_distance}.properties >> $report
    echo -e "\n" >> $report
fi

# If the file with similar property values exists and is > 0, add them to the report as well.
if [ -s ${process_file}.ld${max_levenshtein_distance}.values ]; then
    echo "Near duplicate property values: " >> $report
    cat ${process_file}.ld${max_levenshtein_distance}.values >> $report
    echo -e "\n" >> $report
fi

# If the report file doesn't exist or is empty, just add that no duplicates
# were found.
if [ ! -s $report ]; then
    echo "No duplicates found" > $report
fi

# Clean up.
rm -rf ${process_file}.properties*
rm -rf ${process_file}.values*
rm -rf ${process_file}.ld${max_levenshtein_distance}.properties
rm -rf ${process_file}.ld${max_levenshtein_distance}.values
rm -rf ${process_file}.ld${max_levenshtein_distance}.values.nonuniq

# Email the report.
if [ -s "$report" ]; then
    mailx -s "[gxa/cron] Atlas Data Sanity Tests for: "`date +'%d-%m-%Y'` ${NOTIFY_EMAILADDRESS} < $report
fi

# Delete it.
rm -rf $report
