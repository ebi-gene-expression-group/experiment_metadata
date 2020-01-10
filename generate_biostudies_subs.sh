#!/bin/bash
IFS="
"

grep_quote() {
    echo $1 | sed 's/[\.\\[(){}|$^+*]/\\&/g' | sed 's|\]|\\&|g'
}

if [ $# -lt 1 ]; then
        echo "Usage: $0 <outpu_path_also_containing input file: curated.tsv>"
        echo "e.g. $0 $ATLAS_PROD/eurocan"
        exit 1
fi
outputPath=$1

for l in $(tail -n +2 $outputPath/curated.tsv); do
    cancerTerms=`echo $l | awk -F"\t" '{print $13}'`
    cancerCellSource=`echo $l | awk -F"\t" '{print $14}'`
    # Rows with no $cancerTerms or $cancerCellSource are not suitable for BioStudies
    if [ -z "$cancerTerms" ]; then 
	continue
    fi
    if [ -z "$cancerCellSource" ]; then 
	continue
    fi
    ae2Acc=`echo $l | awk -F"\t" '{print $1}'`
    res=${outputPath}/${ae2Acc}.tsv
    middle=`echo $ae2Acc | awk -F"-" '{print $2}'`
    bsStudy="S-ECPF-"`echo $ae2Acc | awk -F"-" '{print $2"-"$3}'`
    eurocanStudy=`echo $l | awk -F"\t" '{print $3}'`
    dataSource="EurocanPlatform"
    title=`echo $l | awk -F"\t" '{print $10}'`
    experimentType=`echo $l | awk -F"\t" '{print $7}'`
    organism="Homo sapiens"
    idf="/ebi/microarray/home/arrayexpress/ae2_production/data/EXPERIMENT/$middle/$ae2Acc/$ae2Acc.idf.txt"
    experimentDescription=`grep '^Experiment Description' $idf | awk -F"\t" '{print $2}'`
    geoAccession=`grep "Comment\[SecondaryAccession\]" $idf | awk -F"\t" '{print $2}' | grep GSE`

    # Output starts here
    echo -e "Submission\t$bsStudy" > $res
    echo -e "Title\t$title" >> $res
    echo -e "DataSource\t$dataSource" >> $res
    echo -e "RootPath\t$bsStudy" >> $res
    echo -e "" >> $res
    echo -e "Study\t$bsStudy" >> $res
    echo -e "Title\t$title" >> $res
    echo -e "Abstract\t$experimentDescription" >> $res
    echo -e "Project\t$dataSource" >> $res
    if [ "$eurocanStudy" == "Eurocan" ]; then
	echo -e "Project\t$dataSource core" >> $res
    fi
    echo -e "Experiment type\t$experimentType" >> $res
    echo -e "Organism\t$organism" >> $res

    # Get Cancer cell source
    for efoId in $(echo $cancerCellSource | tr "," "\n" | sed 's| ||g'); do
        term=`curl -s "http://www.ebi.ac.uk/efo/$efoId" | grep '<rdfs:label' | head -1 | perl -p -e 's|</rdfs:label>||' | perl -p -e 's|<.\
*>||' | sed 's|^\s*||'`
        echo -e "Cancer cell source\t$term" >> $res
        echo -e "[Ontology]\tEFO" >> $res
        echo -e "[TermId]\t$efoId" >> $res
    done    

    # Get Cancer type(s)
    for efoId in $(echo $cancerTerms | tr "," "\n" | sed 's| ||g'); do
        term=`curl -s "http://www.ebi.ac.uk/efo/$efoId" | grep '<rdfs:label' | head -1 | perl -p -e 's|</rdfs:label>||' | perl -p -e 's|<.\
*>||' | sed 's|^\s*||'`
        echo -e "Cancer type\t$term" >> $res
        echo -e "[Ontology]\tEFO" >> $res
        echo -e "[TermId]\t$efoId" >> $res
    done
    echo -e "" >> $res
    echo -e "Links\tType\tTitle" >> $res
    echo -e "${ae2Acc}\tArrayExpress\tExperiment in ArrayExpress" >> $res
    echo -e "${ae2Acc}\tArrayExpress files\tExperiment files in ArrayExpress" >> $res
    if [ ! -z "$geoAccession" ]; then
	echo -e "${geoAccession}\tGEO\tExperiment in GEO"  >> $res   
    fi

    # Get publication details
    aux=~/tmp/aux.$ae2Acc
    studyAuthorsDone=
    for pubmedId in $(grep '^PubMed ID' $idf | tr "\t" "\n" | grep -P '\d'); do 
	curl -s -o $aux.download "http://www.ebi.ac.uk/europepmc/webservices/rest/search/query=EXT_ID:$pubmedId%20src:med%20&resulttype=core"
	xml_grep result $aux.download > $aux
	if [ ! -s $aux ]; then 
	    echo "ERROR: Failed to retrieve information via 'http://www.ebi.ac.uk/europepmc/webservices/rest/search/query=$pubmedId%20src:med%20&resulttype=core'"
	    exit 1
	fi

        # Get authors and affiliations - output the authors of the first (primary) paper as the authors of the study
	limit=`cat $aux | perl -p -e 's|\<|\n<|g' | grep -n '<\/authorList>' | awk -F":" '{print $1}'`
	cat $aux | perl -p -e 's|\<|\n<|g' | head -$limit | grep -P '<fullName>|<affiliation>' | perl -p -e 's|[\<]||g' | perl -p -e 's|[\>]|\t|g' > $aux.authors.affiliations
	grep -P "affiliation\t" $aux.authors.affiliations  | perl -p -e 's|\t*$||g' | awk -F"\t" '{print $NF}' | perl -p -e 's|\sElectronic address:.*$||g' | sort | uniq > $aux.affiliations
	
	for l in $(cat $aux.authors.affiliations); do
	    echo $l | grep '^fullName' > /dev/null 
	    if [ $? -eq 0 ]; then 
		if [ -z "$studyAuthorsDone" ]; then
		    echo "" >> $res
		    echo "Author" >> $res
		    echo $l | sed 's|fullName|Name|' >> $res
		fi
	    else
		echo $l | grep  '^affiliation' > /dev/null 
		if [ $? -eq 0 ]; then 
		    org=`echo $l | awk -F"\t" '{print $NF}' | perl -p -e 's|\sElectronic address:.*$||'`
		    oNum=`grep -nP "^$(grep_quote "$org")$" $aux.affiliations | awk -F":" '{print $1}'`
		    if [ -z "$studyAuthorsDone" ]; then
			echo -e "<affiliation>\to${oNum}" >> $res
		    fi
		else
		    echo "ERROR: unknown line type found in aux.$f: $l"
		    break
		fi
	    fi
	done
	i=1
	if [ -z "$studyAuthorsDone" ]; then
	    for org in $(cat $aux.affiliations); do
		echo "" >> $res
	        echo -e "Organisation\to${i}" >> $res                                                                      
		echo -e "Name\t$org" >> $res                                  
		i=$[$i+1]
	    done
	fi
	studyAuthorsDone=1
        publicationAuthors=`grep "^fullName" $aux.authors.affiliations | sed 's|fullName\t||g' | tr "\n" ", " | sed 's|,$||'`

	title=`xml_grep result/title $aux --text`
	journal=`xml_grep result/journalInfo/journal/title $aux --text`
	volume=`xml_grep result/journalInfo/volume $aux --text`
	pages=`xml_grep result/pageInfo $aux --text`
	publicationDate=`xml_grep result/journalInfo/dateOfPublication $aux --text`
        echo -e "" >> $res
	echo -e "Publication\t$pubmedId" >> $res
	echo -e "Authors\t${publicationAuthors}" >> $res
	echo -e "Title\t$title" >> $res
        echo -e "Journal\t$journal" >> $res
        echo -e "Volume\t$volume" >> $res
        echo -e "Pages\t$pages" >> $res
        echo -e "Publication date\t$publicationDate" >> $res
    done
    if [ -z "$studyAuthorsDone" ]; then
	# No publication were found - we need to retrieve study authors from idf
	grep "^Person Last Name" $idf | sed 's|Person Last Name\t||' | tr "\t" "\n" | grep -v '^$' > $aux.lastNames
	grep "^Person First Name" $idf | sed 's|Person First Name\t||' | tr "\t" "\n" | grep -v '^$' > $aux.firstNames
	
	i=1
	max=`wc -l $aux.lastNames | awk '{print $1}'`
	while [ $i -le $max ]; do
	    firstName=`sed -n "${i}p" $aux.firstNames`
	    lastName=`sed -n "${i}p" $aux.lastNames`
	    echo "" >> $res
	    echo "Author" >> $res
	    echo -e "Name\t${lastName} ${firstName}" >> $res
	    echo -e "<affiliation>\to1" >> $res
	    i=$[$i+1]
	done
	affiliation=`grep '^Person Affiliation' $idf | awk -F"\t" '{print $2}'`
        echo "" >> $res
        echo -e "Organisation\to1" >> $res                                                                      
	echo -e "Name\t$affiliation" >> $res 
	
    fi

    rm -rf ${aux}*
done
