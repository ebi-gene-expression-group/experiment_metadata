from os import listdir
import re

# example run 

# snakemake .....--config \
#    accession={wildcards.accession} \
#    mode="single_cell" 

# This workflow updates all ontology mappings in condensed SDRF files, and then
# updates all experiment designs on ves-hx-76:8080


# source bash functions

# need somewhere a mapping part, to go from many accessions build the unified reports (agreggation)


# Parse config from command line

mode = config.get("mode")


def get_accessions(mode):
    """
    Generate the expected output file names.
    Not yet sure if for all modes, the glob path below
    is where the accession dirs are found.
    Edit accordingly once known.
    """
    workdir = "" # Should be determined by mode
    acc_regex = re.compile("E-\D+-\d+")
    acc_dirs = listdir(f"{workdir}")
    ACCESSIONS = [acc for acc in acc_dirs if acc_regex.match(acc)]
    return(workdir, ACCESSIONS)

workdir, ACCESSIONS = get_accessions(mode)


# Below probably no longer needed bec of regex above
wildcard_constraints:
    accession = "E-\D+-\d+"


# Rule for running the whole pipelien
# Not yet sure if below is the desired path for the output condensed sdrf files
# Edit accordingly once the output dir is identified
rule all:
    input:
        expand("{workdir}/{acc}/{acc}.condensed-sdrf.tsv", acc=ACCESSIONS)




# MEM_FOR_APPLY_FIXES=
# or adjust via retrial system


rule check_zooma:
    """
    Check that zooma returns successful http code
    """
    output:
        http_code_txt=temp("prep_env/http_code.txt")
    shell:
        """
        zoomaMetadataUrl="${ZOOMA_API_BASE}/server/metadata"
        httpResponse=`curl -o /dev/null -X GET -s -w %{http_code} ${zoomaMetadataUrl}`
        if [ "$httpResponse" -e 200 ]; then
            echo $httpResponse > {http_code_txt}
        else
            # Message 
            echo "ERROR: Zooma not responding correctly"
            echo "${zoomaMetadataUrl} returned a non-success http code: $httpResponse"
        """

rule remove_aux_files:
    input:
        "prep_env/http_code.txt"
    output:
        ""
    shell:
        """
        """


rule run_condense_sdrf:
    """
    Run condense_sdrf.pl with options to map terms with Zooma (-z) and import
    the IDF from ArrayExpress load directory (-i).
    """
    conda: "envs/perl-atlas-modules.yaml"
    log:
    output:
    shell:
        """
        set -e # snakemake on the cluster doesn't stop on error when --keep-going is set
        exec &> "{log}"

        ..condense_sdrf.pl

        # if error detected, then condense SDRF without Zooma mapping:
        ..condense_sdrf.pl

        #if success, run next rule
        """

rule apply_fixes:
    """
    Apply automatic fixes to all imported sdrf and idf files
    """


rule check_zooma_mapping_report:


rule copy_reports_to_targetDir:
    """
    Copy reports to $targetDir.
    Mail out the Zoomification reports location
    """

