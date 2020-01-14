#!/usr/bin/env Rscript 

suppressPackageStartupMessages(require(optparse))

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

ucfirst <- function(string) {
  paste0(toupper(substr(string, 1, 1)), substr(string, 2, nchar(string)))
}

condensed <- read.delim(opt[['input_file']], row.names = NULL, header=F, stringsAsFactors = FALSE)
colnames(condensed) <- c('exp_id', 'array_design', 'id', 'type', 'variable', 'value', 'ontology')

# Remove replicated sets of id, variable and value, since these are likely to be
# duplicated values from multiple files for the same run

condensed <- condensed[! duplicated(paste(condensed$id, condensed$variable, condensed$value, condensed$type)), ]

# Remaining duplicates should be labelled  

dup <- which(duplicated(paste(condensed$id, condensed$variable, condensed$value)))
condensed$variable[dup] <- unlist(lapply(split(condensed[dup, 'variable'], condensed[dup, 'id']), function(x) paste0(x, '.', 1:length(x))))

# Label as factor, characteristic etc if specified

if (opt[['retain_types']]){
  condensed$variable <- paste0(ucfirst(condensed$type), '[', condensed$variable, ']')
}

# Names we'll use for ontology columns

condensed$ont_var <- paste(condensed$variable, 'ontology')

# Do the casting to get back to a wide format. In cases where a variable isn't
# defined for a run, we will have a zero-length vector, in which case set an
# empty string

wide <- dcast(condensed, id ~ variable, value.var = 'value', fun.aggregate = function(x){
  if (length(x) == 0 || is.na(x)){
    ''
  }else{
    x
  }
})

# Now make a separate ontology table

ontology <- dcast(condensed, id ~ ont_var, value.var = 'ontology', fun.aggregate = function(x){
  if (length(x) == 0 || is.na(x)){
    ''
  }else{
    paste(x, collapse=',')
  }
})

# Merge the two

wide <- merge(wide, ontology, by='id', all.x = TRUE, sort = FALSE)

# Write output

write.table(wide, file = opt[['output_file']], sep="\t", quote = FALSE, row.names = FALSE)

