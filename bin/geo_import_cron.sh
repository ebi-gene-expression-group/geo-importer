#!/usr/bin/env bash

# Source script from the same (prod or test) Atlas environment as this script
scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
projectRoot=${scriptDir}/..
source $projectRoot/bin/geo_import_routines.sh

today="`eval date +%Y-%m-%d`"

USAGE="Usage: `basename $0` [-t bulkORsinglecell ] [-s supportingFilesPath ] [-o output ]"
    while getopts ":u:d:t:s:o:" params; do
        case $params in

            t)
                bulkORsinglecell=$OPTARG;
                ;;
            s)
                supportingFilesPath=$OPTARG;
                ;;
            o)
                outputPath=$OPTARG;
                ;;
            ?)
                echo "Invalid Option Specified"
                echo "$USAGE" 1>&2 ; exit 1
                ;;
        esac
    done


if ! [[ "$bulkORsinglecell" =~ ^(bulk|singlecell)$ ]]; then
    echo "please provide type -t as 'bulk' or 'singlecell'"
   exit 1
fi

if [ ! -d "$outputPath" ]; then
    echo " output path $outputPath doesn't exist"
    exit 1
fi

if [ ! -d "$supportingFilesPath" ]; then
    echo "supporting file $supportingFilesPath path doesn't exist"
    exit 1
fi

# Set up DB connection details
dbConnection=$(get_pg_db_connection)
if [ $? -ne 0 ]; then
    echo "ERROR: dbConnection connection not established" >&2
    exit 1
fi


pushd $supportingFilesPath
    ## Script which retrieves ENA study to SRA study ID mapping a
    ## output of the script list of GSE_ids/ENA_study_id as geo_${bulkORsinglecell}_rnaseq.tsv in desired output path
    $projectRoot/bin/geo_studies_list.py --type $bulkORsinglecell --output $supportingFilesPath > ${bulkORsinglecell}_ena_gse_pooling.$today.log
    if [ $? -ne 0 ]; then
        echo "ERROR: ${bulkORsinglecell}_ena_gse_pooling" >&2
        exit 1
    fi

    ## remove ENA_IDs that have already been imported before
    filterGEOImport() {
        dbConnection=$1
        GSEImport=$2
        type=$(echo $GSEImport | awk -F'_' '{print $2}')
        if [ "$type" == "bulk" ]; then
            GSELoaded=$(echo "select geo_acc from rnaseq_atlas_eligibility;" | psql -At $dbConnection | sed 's/ //g' | tr '\t' '\n' | sort -u)
        elif [ "$type" == "singlecell" ]; then
            GSELoaded=$(echo "select geo_acc from sc_atlas_eligibility;" | psql -At $dbConnection | sed 's/ //g' | tr '\t' '\n' | sort -u)
        fi
        comm -23 <(cat $GSEImport | cut -f 1 | sort ) <(echo -e $GSELoaded | tr ' ' '\n' | sort )
    }
    ## filter GSE ids that have already been imported in the atlas eligibility database
    filterGEOImport $dbConnection geo_${bulkORsinglecell}_rnaseq.tsv > latest_${bulkORsinglecell}_geo_accessions.txt

popd


