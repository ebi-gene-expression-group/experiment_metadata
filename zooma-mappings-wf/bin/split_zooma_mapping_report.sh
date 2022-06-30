#!/bin/bash
split_zooma_mapping_report() {

    zoomaMappingReport=$1

    # Now break down $zoomaMappingReport.aux into four report files: automatic, excluded, noresults, requirescuration
    section=AUTOMATIC
    head -1 $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="SEMANTIC_TAG" -v col4="STUDY" -v col5="BIOENTITY" -v col6="ONTOLOGY_LABEL|ZOOMA_VALUE" -v col7="PROP_VALUE_MATCH" -v col8="Category of Zooma Mapping" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i;if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;if($i==col6)c6=i;if($i==col7)c7=i;if($i==col8)c8=i;}} NR==1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5 "\t" $c6 "\t" $c7 "\t" $c8}' >$zoomaMappingReport.$section.tsv
    # Note below that intended sort is: primary by PROP_VALUE_MATCH, secondary by property "PROPERTY_TYPE", and tertiary by "PROPERTY_VALUE"
    cat $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="SEMANTIC_TAG" -v col4="STUDY" -v col5="BIOENTITY" -v col6="ONTOLOGY_LABEL|ZOOMA_VALUE" -v col7="PROP_VALUE_MATCH" -v col8="Category of Zooma Mapping" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;if($i==col6)c6=i;if($i==col7)c7=i;if($i==col8)c8=i;}} NR>1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5 "\t" $c6 "\t" $c7 "\t" $c8}' | grep -P "\t$section" | sed 's|null||g' | sort -t"$(echo -e \"\t\")" -k5,5 -k2,2 -k3,3 >>$zoomaMappingReport.$section.tsv

    section=EXCLUDED
    head -1 $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="STUDY" -v col4="Category of Zooma Mapping" -v col5="Basis for Exclusion" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;}} NR==1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5}' >$zoomaMappingReport.$section.tsv
    # Note below that intended sort is: primary by property "PROPERTY_TYPE", and secondary by "PROPERTY_VALUE"
    cat $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="STUDY" -v col4="Category of Zooma Mapping" -v col5="Basis for Exclusion" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;}} NR>1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5}' | grep -P "\t$section" | sed 's|null||g' | sort -t"$(echo -e \"\t\")" -k1,1 -k2,2 >>$zoomaMappingReport.$section.tsv

    section=NO_RESULTS
    head -1 $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="STUDY" -v col4="BIOENTITY" -v col5="Category of Zooma Mapping" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;}} NR==1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5}' >$zoomaMappingReport.$section.tsv
    # Note below that intended sort is: primary by property "PROPERTY_TYPE", and secondary by "PROPERTY_VALUE"
    cat $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="STUDY" -v col4="BIOENTITY" -v col5="Category of Zooma Mapping" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;}} NR>1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5}' | grep -P "\t$section" | sed 's|null||g' | sort -t"$(echo -e \"\t\")" -k1,1 -k2,2 >>$zoomaMappingReport.$section.tsv

    section=REQUIRES_CURATION
    head -1 $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="SEMANTIC_TAG" -v col4="STUDY" -v col5="BIOENTITY" -v col6="ONTOLOGY_LABEL|ZOOMA_VALUE" -v col7="PROP_VALUE_MATCH" -v col8="Category of Zooma Mapping" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;if($i==col6)c6=i; if($i==col7)c7=i; if($i==col8)c8=i;}} NR==1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5 "\t" $c6 "\t" $c7 "\t" $c8}' | sed 's|null||g' >$zoomaMappingReport.$section.tsv
    # Note below that intended sort is: primary by PROP_VALUE_MATCH, secondary by property "PROPERTY_TYPE".
    cat $zoomaMappingReport.aux | awk -F"\t" -v col1="PROPERTY_TYPE" -v col2="PROPERTY_VALUE" -v col3="SEMANTIC_TAG" -v col4="STUDY" -v col5="BIOENTITY" -v col6="ONTOLOGY_LABEL|ZOOMA_VALUE" -v col7="PROP_VALUE_MATCH" -v col8="Category of Zooma Mapping" 'NR==1{for(i=1;i<=NF;i++){if($i==col1)c1=i; if ($i==col2)c2=i;if($i==col3)c3=i;if($i==col4)c4=i;if($i==col5)c5=i;if($i==col6)c6=i; if($i==col7)c7=i; if($i==col8)c8=i;}} NR>1{print $c1 "\t" $c2 "\t" $c3 "\t" $c4 "\t" $c5 "\t" $c6 "\t" $c7 "\t" $c8}' | grep -P "\t$section" | sed 's|null||g' | sort -t"$(echo -e \"\t\")" -k7,7 -k2,2 >>$zoomaMappingReport.$section.tsv

}
