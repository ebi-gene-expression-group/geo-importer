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
    ## Script which retrieves ENA study ids and organsim names for RNA-seq experiments from ENA
    ## converts ENA study ids to GEO (GSE) ids using API (eutils.ncbi.nlm.nih.gov/entrez/eutils/)
    ## ENA ids that do not exist in GEO are recorded in rnaseq_ena_gse_pooling.log
    ## Filters GSE ids that have already been loaded in AE2
    ## output of the script list of filtered GSE_ids/ENA_study_id as geo_${bulkORsinglecell}_rnaseq.tsv in desired output path
    $projectRoot/bin/rnaseq_ena_gse_pooling.py --type $bulkORsinglecell --output $supportingFilesPath > ${bulkORsinglecell}_ena_gse_pooling.$today.log
    if [ $? -ne 0 ]; then
        echo "ERROR: ${bulkORsinglecell}_ena_gse_pooling" >&2
        exit 1
    fi

    ## ENA_study_ids list that do no exist in GEO import that will help curators to fetch studies from ENA directly
    makeNotInGEOList() {
        gsePoolingLog=$1
        type=$(echo $gsePoolingLog | awk -F'_' '{print $1}')
        cat $gsePoolingLog | grep "Not in GEO" | awk -F" " '{print $5}' > ${bulkORsinglecell}_ENA_IDs_NotInGEO.tmp
        test -s "$gsePoolingLog" || (  >&2 echo "$0 gse pooling log file not found: $gsePoolingLog" ; exit 1 )
        if [ "$type" == "bulk" ]; then
            join -1 1 -2 2 -o 1.1,2.1 <(cat ${bulkORsinglecell}_ENA_IDs_NotInGEO.tmp | sort ) <(curl -s 'https://www.ebi.ac.uk/fg/rnaseq/api/tsv/getBulkRNASeqStudiesInSRA' | tail -n +2 | sort -k 2) | sort -u
        elif [ "$type" == "singlecell" ]; then
            join -1 1 -2 2 -o 1.1,2.1 <(cat ${bulkORsinglecell}_ENA_IDs_NotInGEO.tmp | sort ) <(curl -s 'https://www.ebi.ac.uk/fg/rnaseq/api/tsv/getSingleCellStudies' | tail -n +2 | sort -k 2) | sort -u
        fi
        rm -rf ${bulkORsinglecell}_ENA_IDs_NotInGEO.tmp
    }
    makeNotInGEOList ${bulkORsinglecell}_ena_gse_pooling.$today.log  > ${bulkORsinglecell}_NotInGEO_list.txt

    ## remove ENA_IDs already been import before
    filterGEOImport() {
        dbConnection=$1
        GSEImport=$2
        type=$(echo $GSEImport | awk -F'_' '{print $2}')
        if [ "$type" == "bulk" ]; then
            GSELoaded=$(echo "select geo_acc from rnaseq_atlas_eligibility;" | psql $dbConnection | tail -n +3 | head -n -2 | sed 's/ //g' | tr '\t' '\n' | sort -u)
        elif [ "$type" == "singlecell" ]; then
            GSELoaded=$(echo "select geo_acc from sc_atlas_eligibility;" | psql $dbConnection | tail -n +3 | head -n -2 | sed 's/ //g' | tr '\t' '\n' | sort -u)
        fi
        comm -23 <(cat $GSEImport | cut -f 1 | sort ) <(echo -e $GSELoaded | tr ' ' '\n' | sort )
    }
    ## filter GSE ids that have already been imported in the atlas eligibility database
    filterGEOImport $dbConnection geo_${bulkORsinglecell}_rnaseq.tsv > latest_${bulkORsinglecell}_geo_accessions.txt

popd


