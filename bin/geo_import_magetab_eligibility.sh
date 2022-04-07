#!/usr/bin/env bash

# script performs geo import magetab elibility checks and populates db table with relevant meta-data for each experiment,
# number of assays, factor value, validation and eligibility status required for curation.

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
projectRoot=${scriptDir}/..
source $projectRoot/bin/geo_import_routines.sh

today="`eval date +%Y-%m-%d`"


USAGE="Usage: `basename $0` [-t bulkORsinglecell ] [-s supportingFilesPath ] [-f geoEnaMappingFile ] [-p pathToDownloads ] [-c pathToCuration ]"
    while getopts ":u:d:t:s:f:p:c:" params; do
        case $params in
            
            t)
                bulkORsinglecell=$OPTARG;
                ;;
            s)
                supportingFilesPath=$OPTARG;
                ;;
            f)
                geoEnaMappingFile=$OPTARG;
                ;;

            p)
                pathToDownloads=$OPTARG;
                ;;

            c)
                pathToCuration=$OPTARG;
                ;;

            ?)
                echo "Invalid Option Specified"
                echo "$USAGE" 1>&2 ; exit 1
                ;;
        esac
    done


if ! [[ "$bulkORsinglecell" =~ ^(bulk|singlecell)$ ]]; then
    echo "please provide type -t as 'bulk' or 'singlecell'"
   exit 1;
fi

if [ ! -f "$geoEnaMappingFile" ]; then
    echo " geoEnaMappingFile $geoEnaMappingFile file doesn't exist"
    exit 1;
fi

if [ ! -d "$supportingFilesPath" ]; then
    echo "supporting files $supportingFilesPath path doesn't exist"
    exit 1;
fi

if [ ! -d "$pathToDownloads" ]; then
    echo "path to GEO downloads $pathToDownloads doesn't exist"
    exit 1;
fi

#if [ ! -d "$pathToCuration" ]; then
#    echo "path to curation $pathToCuration doesn't exist"
#    exit 1;
#fi

# Set up DB connection details
dbConnection=$(get_pg_db_connection)
if [ $? -ne 0 ]; then
   "ERROR: dbConnection connection not established" >&2
    exit 1
fi


# This section looks at each experiment within GEOImportDownloads folder
# Splits merged MGAE-TAB to IDF and SDRF
# Validates mage-tab and exports report
# Performs Atlas elgibility check
# Performs experiment loading check, and loads pheno-data info into database for each new experiment.
# This is useful for curators to prioritise studies.
find ${pathToDownloads} -mindepth 1 -maxdepth 1 | xargs -n1 basename \
    | while read -r exp ; do
    echo $exp
    expAcc=$(echo -e $exp | sed 's/_output//g')
    pushd $pathToDownloads/$exp/

    if [[ -e "${expAcc}.merged.idf.txt" ]]; then
        echo "splitting MAGE-TAB - $expAcc"
		    split_magetab.pl ${expAcc}.merged.idf.txt
            if  [ ! -s ${expAcc}_atlas_eligibility.out ]; then
                echo "validating MAGE-TAB - $expAcc"
                validate_magetab.pl -m ${expAcc}.merged.idf.txt > ${expAcc}_validate_magetab.out

                echo "Atlas eligility check - $expAcc"
                check_atlas_eligibility.pl -m ${expAcc}.merged.idf.txt > ${expAcc}_atlas_eligibility.out

                echo "Creating Atlas MAGE-TAB files - $expAcc"
                create_atlas_accession_files $expAcc $bulkORsinglecell

                echo "Loading in the database - $expAcc"
                exp_loading_check $expAcc $geoEnaMappingFile $dbConnection $bulkORsinglecell $pathToDownloads

	        else
                echo "${expAcc}_atlas_eligibility already done"
                exp_loading_check $expAcc $geoEnaMappingFile $dbConnection $bulkORsinglecell $pathToDownloads
                echo "Loaded in the database - $expAcc"
            fi
    else
	      echo "MAGE-TAB files for $expAcc missing"
    fi

    popd
done


### create atlas accession folders (E-GEOD-xxx) under associated bulk or singlecell RNA-seq and sync all mage-tab files for curation
#echo "Creating folders and moving files for new studies"
#move_files $pathToDownloads $pathToCuration
