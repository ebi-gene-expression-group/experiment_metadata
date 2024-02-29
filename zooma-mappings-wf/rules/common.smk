# Parse config from command line

mode = config.get("mode")
logs_path = config.get("zooma_logs")
working_dir = config.get("working_dir")


def read_skip_accessions_file():
    import yaml

    if "skip_accessions" in config:
        skip_acc = []
        with open(config["skip_accessions"], "r") as stream:
            try:
                skip_acc = yaml.safe_load(stream)
            except yaml.YAMLError as exc:
                print(exc)
        return skip_acc["skips"]


def get_accessions(working_dir):
    if "accessions" in config:
        ACCESSIONS = config["accessions"].split(":")
    else:
        acc_regex = re.compile(f"E-(\D+)-(\d+)")
        acc_dirs = listdir(f"{working_dir}")
        ACCESSIONS = [acc for acc in acc_dirs if acc_regex.match(acc)]
        # skip accessions if provided in config
        if config.get("skip_accessions"):
            SKIP_ACCESSIONS = read_skip_accessions_file()
            print(f"The following accessions will be skipped: {SKIP_ACCESSIONS}")
            for element in SKIP_ACCESSIONS:
                if element in ACCESSIONS:
                    ACCESSIONS.remove(element)
    return ACCESSIONS


global ACCESSIONS
ACCESSIONS = get_accessions(working_dir)


def get_exp_type_from_xml(wildcards):
    if config["mode"] == "bulk":
        from xml.dom import minidom

        xmldoc = minidom.parse(
            f"{working_dir}/{wildcards['accession']}/{wildcards['accession']}-configuration.xml"
        )
        exp_type = []
        config_tag = xmldoc.getElementsByTagName("configuration")
        for i in config_tag:
            exp_type.append(i.getAttribute("experimentType"))
        return exp_type
    else:
        return None



# Define a function to initialize date_current_run only once, and write it to a file
file_path = f"{logs_path}/date_current_run.txt"

def initialize_date_current_run():
    global date_current_run
    if date_current_run is None:
        if os.path.exists(file_path):
            with open(file_path, "r") as file:
                date_current_run = file.read()
        else:
            date_current_run = datetime.now().strftime("%Y-%m-%d-%H:%M")
            with open(file_path, "w") as file:
                file.write(date_current_run)


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


def get_split_zooma_mapping_report_inputs(accessions, lp):
    inputs = []
    for acc in accessions:
        inputs.append(f"{lp}/{acc}/{acc}-apply_fixes_zooma_mappings.done")
    return inputs

def get_mem_mb(wildcards, attempt):
    """
    To adjust resources in the rules 
    attemps = reiterations + 1
    Max number attemps = 4
    """
    mem_avail = [ 4, 8, 16, 32 ]  
    return mem_avail[attempt-1] * 1000

