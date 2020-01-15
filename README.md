# Atlas metadata handling [![install with bioconda](https://img.shields.io/badge/install%20with-bioconda-brightgreen.svg?style=flat)](https://anaconda.org/ebi-gene-expression-group/atlas-experiment-metadata)

This is a factoring out of code preiously present in the internal atlas-prod repository. It provides functionality for handling Atlas metadata. Some of the scripts are unused legacy code and will be prunded in time.

## Install

These scripts are most easily installed via Bioconda:

```
conda install -c ebi-gene-expression-group atlas-experiment-metadata
```

## Commands

### condense_sdrf.pl

A 'condensed' SDRF is a 'melted' version of the starting SDRF file, with one row for each combination of assay, variable type (factor, characteristic) and variable. This is produced from an SDRF like:

```
condense_sdrf.pl -e <experiment accession> -fi -o <output directory>
```

The condense_sdrf.pl script will also use Zooma to add ontology terms.

By default this will look for SDRF files under a path defined by the ATLAS_PROD environment variable. But you can also specify an IDF file, from which the SDRF location will be determined:
    
```
condense_sdrf.pl -e <experiment accession> -fi <path to IDF file> -o <output directory>
```

### single_cell_condensed_sdrf.sh

This script is a wrapper for condense_sdrf.pl which deals with some single-cell specific issues on technical replication and handling droplet experiments (where cell != library). 

Again, this script can be run in two modes. Default behaviour is to pull the SDRF location from a directory defined by ATLAS_SC_EXPERIMENT:

```
bash single_cell_condensed_sdrf.sh -e <experiment ID> -o <output dir> -z <zooma exclusions file>
```

... but you can also pass an IDF file directly:

```
single_cell_condensed_sdrf.sh -e <experiment accession> -f <path to IDF file> -o <output dir> -z <zooma exclusions file>
```

See inline help for information on available options:

```
single_cell_condensed_sdrf.sh -h
```

### unmelt_condensed.R

Sometimes we want to 'unmelt' the condensed SDRF, returning it to a wide format, for example for use in downstream analysis. This is what unmelt_condensed.R does:

```
unmelt_condensed.R -i $test_condensed_sdrf -o $test_unmelted_sdrf --retain-types --has-ontology
```

It is important that options are provided matching the way in which the condensed SDRF was genereated in the first place:

 - --retain-types: SDRF files have different types of field, for example factors and characteristics. We can retain these annotations in the wide format, and we probably should (because it's possible to have factors and characteristics with the same name!).
 - --has-ontology: if you ran condense_sdrf.pl or single_cell_condensed_sdrf.sh while enabling zooma mapping you need to use this option (off by default)
 - --has-biotypes: if you ran condense_sdrf.pl with the -b option, you need to set this flag (off by default)

See inline help for information on available options:

```
unmelt_condensed.R --help
```
