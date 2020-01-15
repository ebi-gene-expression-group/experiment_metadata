#!/usr/bin/env Rscript 

suppressPackageStartupMessages(require(optparse))

# Flatten a condensed SDRF back to 'wide' format. Condensed SDRFs (made by
# condense_sdrf.pl) will have the following fields:
#
# 1. Experiment accession
# 2. Array design (empty in sequencing experiments)
# 3. Assay name (e.g. run ID)
# 4. (optionally) biorep ID
# 5. Attribute type (characteristic, factor etc)
# 6. Variable, e.g 'organism part'
# 7. Variable value, e.g 'liver'
# 8. (optionally) Ontology term URI
#
# The optional fields mean that the file can have 6,7 or 8 fields, and the order
# means that we can't rely on the number of fields to infer which is present. To
# complicate things further, for single-cell the single_cell_condensed_sdrf.sh
# script assumes that 8 fields are present and adds blank fields if there are
# not. So we must apply some logic to deal with all eventualities.

option_list = list(
  make_option(
    c("-i", "--input-file"),
    action = "store",
    default = NA,
    type = 'character',
    help = "Input condensed SDRF in long format."
  ),
  make_option(
    c("-o", "--output-file"),
    action = "store",
    default = NA,
    type = 'character',
    help = 'File path for output.'
  ),
  make_option(
    c("-r", "--retain-types"),
    action = "store_true",
    default = FALSE,
    type = 'logical',
    help = "Optional flag. Retain field types (characteristic, factor etc) in column headers?"
  ),
  make_option(
    c("-b", "--has-bioreps"),
    action = "store_true",
    default = FALSE,
    type = 'logical',
    help = "Optional flag. Interpret 4th field as biorep identifier?"
  ),
  make_option(
    c("-n", "--has-ontology"),
    action = "store_true",
    default = FALSE,
    type = 'logical',
    help = "Optional flag. Indicate that there is a field containing ontology mappings present in either column 7 or 8 (depending on the value of --has-bioreps) ?"
  )
)

opt <- parse_args(OptionParser(option_list=option_list), convert_hyphens_to_underscores = TRUE)

# Check parameter values

for (file_param in c('input_file', 'output_file')){
  if (is.na(opt[[file_param]])){
    stop((paste('You must supply', file_param)))
  }else if (! file.exists(opt$input_file)){
    stop((paste('File', opt$input_file, 'does not exist')))
  }
}

# Do setup after argument parsing

suppressPackageStartupMessages(library(reshape2))
suppressPackageStartupMessages(library(data.table))

ucfirst <- function(string) {
  paste0(toupper(substr(string, 1, 1)), substr(string, 2, nchar(string)))
}

# Read condensed SDRF

print(paste('Reading', opt[['input_file']], '...'))
condensed <- fread(opt[['input_file']], header=F, stringsAsFactors = FALSE, fill = TRUE)
print('...done')

# Apply logic to set which fields are which

column_names <- c('exp_id', 'array_design', 'id')
if (opt[['has_bioreps']]){
  column_names <- c(column_names, 'biorep_id')
}
column_names <- c(column_names, c('type', 'variable', 'value'))
if (opt[['has_ontology']]){
  column_names <- c(column_names, 'ontology')
}

# Sometimes input will have had unnecessary blank fields added due to
# assumptions made by single_cell_condensed_sdrf.sh. It's safe to strip them if
# they're all NA.

if (ncol(condensed) > length(column_names)){
  extra_cols <- (length(column_names)+1):ncol(condensed)
  
  for (ec in extra_cols){
    if (all(is.na(condensed[,..ec]))){
      condensed <- condensed[,-..ec]
      print(paste('Removed empty column', ec))
    }else{
      stop(paste0('Non-empty ', ec, 'th column not predicted by options used. Make sure you have set --has-bioreps and --has-ontology correctly.'))
    }
  }
}

colnames(condensed) <- column_names

# Remove replicated sets of id, variable and value, since these are likely to be
# duplicated values from multiple files for the same run

print("Checking for and removing duplicate rows from multi-file assays, labelling genuine duplicates...")
condensed <- condensed[! duplicated(paste(condensed$id, condensed$variable, condensed$value, condensed$type)), ]

# Remaining duplicates should be labelled  

dup <- which(duplicated(paste(condensed$id, condensed$variable, condensed$value, condensed$type)))
condensed$variable[dup] <- unlist(lapply(split(condensed[dup, 'variable'], condensed[dup, 'id']), function(x) paste0(x, '.', 1:length(x))))
print("...done")

# Label as factor, characteristic etc if specified

if (opt[['retain_types']]){
  condensed$variable <- paste0(ucfirst(condensed$type), '[', condensed$variable, ']')
}

# Names we'll use for ontology columns

condensed$ont_var <- paste(condensed$variable, 'ontology')

# Do the casting to get back to a wide format. In cases where a variable isn't
# defined for a run, we will have a zero-length vector, in which case set an
# empty string

print("Reshaping main data...")
wide <- dcast(condensed, id ~ variable, value.var = 'value', fun.aggregate = function(x){
  if (length(x) == 0 || is.na(x)){
    ''
  }else{
    x
  }
})
print("... done")

# Now make a separate ontology table where appropriate

if (opt[['has_ontology']]){
  print("Reshaping ontology...")
  ontology <- dcast(condensed, id ~ ont_var, value.var = 'ontology', fun.aggregate = function(x){
    if (length(x) == 0 || is.na(x)){
      ''
    }else{
      paste(x, collapse=',')
    }
  })
  print("... done")

  # Merge the two

  print("Merging ontology table with main...")
  wide <- merge(wide, ontology, by='id', all.x = TRUE, sort = FALSE)
  print("... done")
}

# Write output

print("Writing reshaped output to file ...")
fwrite(wide, file = opt[['output_file']], sep="\t", quote = FALSE, row.names = FALSE)
print("... done")
