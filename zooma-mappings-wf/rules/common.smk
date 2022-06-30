# Parse config from command line

mode = config.get("mode")
working_dir = config.get("working_dir")


def get_accessions(working_dir):
    acc_regex = re.compile(f"E-(\D+)-(\d+)")
    acc_dirs = listdir(f"{working_dir}")
    ACCESSIONS = [acc for acc in acc_dirs if acc_regex.match(acc)]
    return ACCESSIONS


ACCESSIONS = get_accessions(working_dir)

# define timestamp only once
def get_date():
    x = datetime.now()
    date_time = x.strftime("%Y-%m-%d-%H:%M")
    return date_time


date_current_run = get_date()


def zooma_mapping_report(date_current_run):
    return f"{config['temp_dir']}/{config['mode']}_zooma_mapping_report.{date_current_run}.tsv"


def get_attempt(wildcards, attempt):
    return attempt


def get_split_report_files(date_current_run):
    zooma_mapping_report = f"{config['temp_dir']}/{config['mode']}_zooma_mapping_report.{date_current_run}.tsv"
    split_report_files = []
    for section in ["AUTOMATIC", "EXCLUDED", "NO_RESULTS", "REQUIRES_CURATION"]:
        split_report_files.append(f"{zooma_mapping_report}.{section}.tsv")
    return split_report_files


def get_split_zooma_mapping_report_inputs(accessions, wd):
    inputs = []
    for acc in accessions:
        inputs.append(f"{wd}/{acc}/{acc}-apply_fixes.done")
    return inputs
