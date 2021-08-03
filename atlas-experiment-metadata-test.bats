#!/usr/bin/env bats

setup() {
    condense_pl="condense_sdrf.pl"
    condense_sc_sh="single_cell_condensed_sdrf.sh"
    test_data_dir="test_data"
    test_exp_acc="E-MTAB-6077"
    test_idf="test_data/$test_exp_acc/$test_exp_acc.idf.txt"
    test_condensed_sdrf="${test_data_dir}/E-MTAB-6077.condensed-sdrf.tsv"
    test_unmelted_sdrf="E-MTAB-6077.unmelted-sdrf.tsv"
    explicit_pl_out_dir='explicit_pl'
    implicit_pl_out_dir='implicit_pl'
    explicit_pl_out="${explicit_pl_out_dir}/E-MTAB-6077.condensed-sdrf.tsv"
    implicit_pl_out="${implicit_pl_out_dir}/E-MTAB-6077.condensed-sdrf.tsv"
    implicit_pl_output_sdrf="${implicit_pl_out_dir}/${test_exp_acc}.sdrf.txt"
    explicit_sc_sh_out_dir='explicit_sc_sh'
    implicit_sc_sh_out_dir='implicit_sc_sh'
    zooma_exclusions="$test_data_dir/zooma_exclusions.yml"
    explicit_sc_sh_out="${explicit_sc_sh_out_dir}/E-MTAB-6077.condensed-sdrf.tsv"
    implicit_sc_sh_out="${implicit_sc_sh_out_dir}/E-MTAB-6077.condensed-sdrf.tsv"
    celltype_fields="inferred cell type"
}


@test "Test single-cell condense perl script with explicit IDF" {
    if [ -f "$explicit_pl_out" ]; then
        skip "Output from explicit condense pl exists"
    fi

    run mkdir -p $explicit_pl_out_dir && $condense_pl -e $test_exp_acc -fi $test_idf -o $explicit_pl_out_dir

    [ "$status" -eq 0 ]
    [ -f "$explicit_pl_out" ]
}

@test "Test single-cell condense perl script with implicit IDF and SDRF copy" {
    if [ -f "$implicit_pl_out" ]; then
        skip "Output from implicit condense pl exists"
    fi

    run mkdir -p $implicit_pl_out_dir && env ATLAS_PROD=$test_data_dir $condense_pl -sc -s -e $test_exp_acc -o $implicit_pl_out_dir

    [ "$status" -eq 0 ]
    [ -f "$implicit_pl_out" ]
    [ -f "$implicit_pl_output_sdrf" ]
}

@test "Test single-cell condense wrapper with explicit IDF and Zooma" {
    if [ -f "$explicit_sc_sh_out" ]; then
        skip "Output from SC sh condense wrapper exists"
    fi

    run mkdir -p $explicit_sc_sh_out_dir && bash single_cell_condensed_sdrf.sh -t "$celltype_fields" -e $test_exp_acc -f test_data/$test_exp_acc/$test_exp_acc.idf.txt -o $explicit_sc_sh_out_dir -z $zooma_exclusions

    [ "$status" -eq 0 ]
    [ -f "$explicit_sc_sh_out" ]
}

@test "Test single-cell condense wrapper with implicit IDF and Zooma" {
    if [ -f "$implicit_sc_sh_out" ]; then
        skip "Output from SC sh condense wrapper exists"
    fi

    run mkdir -p $implicit_sc_sh_out_dir && env ATLAS_SC_EXPERIMENTS=$test_data_dir bash single_cell_condensed_sdrf.sh -t "$celltype_fields" -e E-MTAB-6077 -o $implicit_sc_sh_out_dir -z $zooma_exclusions

    [ "$status" -eq 0 ]
    [ -f "$implicit_sc_sh_out" ]
}

@test "Test single-cell condense wrapper with implicit IDF and Zooma from env" {
    if [ -f "$implicit_sc_sh_out" ]; then
        skip "Output from SC sh condense wrapper exists"
    fi

    run mkdir -p $implicit_sc_sh_out_dir && env ATLAS_SC_EXPERIMENTS=$test_data_dir ATLAS_META_CONFIG=$test_data_dir bash single_cell_condensed_sdrf.sh -t "$celltype_fields" -e E-MTAB-6077 -o $implicit_sc_sh_out_dirs

    [ "$status" -eq 0 ]
    [ -f "$implicit_sc_sh_out" ]
}

@test "Test unmelt for condensed SDRFs" {
    if [ -f "$test_unmelted_sdrf" ]; then
        skip "Output from unmelt exists"
    fi

    run unmelt_condensed.R -i $test_condensed_sdrf -o $test_unmelted_sdrf --retain-types --has-ontology
    echo "output = ${output}"

    [ "$status" -eq 0 ]
    [ -f "$test_unmelted_sdrf" ]
}

