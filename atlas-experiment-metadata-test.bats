#!/usr/bin/env bats

setup() {
    condense_sc_sh="single_cell_condensed_sdrf.sh"
    test_exp_acc="E-MTAB-6077"
    test_data_dir="test_data"
    explicit_sc_sh_out_dir=explicit_sc_sh
    implicit_sc_sh_out_dir=implicit_sc_sh
    zooma_exclusions="test_data/zooma_exclusions.yml"
    explicit_sc_sh_out="${explicit_sc_sh_out_dir}/E-MTAB-6077.condensed-sdrf.tsv"
    implicit_sc_sh_out="${implicit_sc_sh_out_dir}/E-MTAB-6077.condensed-sdrf.tsv"
}

@test "Test single-cell condense wrapper with explicit IDF" {
    if [ -f "$explicit_sc_sh_out" ]; then
        skip "Output from SC sh condense wrapper exists"
    fi

    run mkdir -p $explicit_sc_sh_out_dir && bash single_cell_condensed_sdrf.sh -e $test_exp_acc -f test_data/$test_exp_acc/$test_exp_acc.idf.txt -o $explicit_sc_sh_out_dir -z $zooma_exclusions

    [ "$status" -eq 0 ]
    [ -f "$explicit_sc_sh_out" ]
}

@test "Test single-cell condense wrapper with implicit IDF" {
    if [ -f "$implicit_sc_sh_out" ]; then
        skip "Output from SC sh condense wrapper exists"
    fi

    run mkdir -p $implicit_sc_sh_out_dir && env ATLAS_SC_EXPERIMENTS=$test_data_dir bash single_cell_condensed_sdrf.sh -e E-MTAB-6077 -o $implicit_sc_sh_out_dir -z $zooma_exclusions

    [ "$status" -eq 0 ]
    [ -f "$implicit_sc_sh_out" ]
}