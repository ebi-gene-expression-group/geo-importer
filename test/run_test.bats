#!/usr/bin/env bats

load setup_perl_env

@test "Check that we have input list of GEO ids file exist" {
 run stat $projectRoot/geo_import/test/GSE93979.txt
 [ $status = 0 ]
}

@test "Running ENA to GEO ids pooling" {
run projectRoot/geo_import/rnaseq_ena_gse_pooling.py --type $bulkORsinglecell --output $BATS_TMPDIR 
file=$(ls $BATS_TMPDIR/geo_{$bulkORsinglecell}_rnaseq)
[ -s $file ]
}

@test "Running the geo import script" {
rm -rf $BATS_TMPDIR/GSE93979
mkdir $BATS_TMPDIR/GSE93979
run $projectRoot/geo_import/import_geo_subs.pl -f $projectRoot/geo_import/test/GSE93979.txt -x -o $BATS_TMPDIR/GSE93979
[ $status = 0 ]
}

@test "Check if the soft-file has downloaded" {
  file=$(ls $BATS_TMPDIR/GSE93979/GSE93979_output/GSE93979_family.soft)
  [ -s $file ]
}

@test "Check if MAGE-TAB has converted" {
  file=$(ls $BATS_TMPDIR/GSE93979/GSE93979_output/GSE93979.idf.txt)
  [ -s $file ]
}

