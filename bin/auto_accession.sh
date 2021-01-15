#!/bin/bash

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
projectRoot=${scriptDir}/..
source $projectRoot/../bash_util/generic_routines.sh
source $projectRoot/bin/geo_import_routines.sh

# Capture call arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <accession_type>"
    echo "e.g. $0 ENAD" >&2
    exit 1;
fi

accession_type=$1

[ ! -z ${SCXA_METADATA_REPO+x} ] || ( echo "SCXA_METADATA_REPO ie. Gitlab repo" && exit 1 )


dbConnection=$(get_db_connection atlasprd3 pro)
scdbConnection=$(get_pg_db_connection -u 'atlasprd3' -d 'pro' -t 'scxa')

## check for loaded studies im DB in bulk and single cell
max_db_id=$(psql -d "$dbConnection" -a -v TYPE="E-${accession_type}" -f $scriptDir/auto_accession.sql | grep "E-${accession_type}-" | tail -n1 | sed 's/[^0-9]*//g')
max_scdb_id=$(echo -e "select accession from experiment where accession like '%${accession_type}%'" | psql -tA -F $'\t' $scdbConnection | sort | tail -n1 | sed 's/[^0-9]*//g')

## check for ongoing bulk and single cell studies
## Ongoing bulk in atlas jobs
max_atlasdb_id=$(echo -e "select jobobject from atlas_jobs where JOBOBJECT like '%${accession_type}%'" | psql -tA -F $'\t' $dbConnection | sort | tail -n1 | sed 's/[^0-9]*//g')

meta_clone=$ATLAS_PROD/singlecell/scxa-metadata
if [ ! -d "$meta_clone" ]; then
    git clone $SCXA_METADATA_REPO $meta_clone
fi
pushd $meta_clone > /dev/null
git checkout master && git pull > /dev/null
popd > /dev/null
	
## Ongoing single cell
max_sc_id=$(find $meta_clone/${accession_type} -type f -name "E-$accession_type-*" -exec basename {} ';' | sed 's/[^0-9]*//g' | sort -nr | head -n1)

## ongoing curation 
if [ $accession_type == 'CURD' ]; then
	max_curation=$(find $AE2_BASE_DIR/${accession_type} -type d -exec basename {} ';' |  sed 's/[^0-9]*//g' | sort -nr | head -n1)
elif [ $accession_type == 'ENAD' ]; then
	max_curation=$(find $ATLAS_PROD/ENA_import/${accession_type} -type d -exec basename {} ';' |  sed 's/[^0-9]*//g' | sort -nr | head -n1)
fi

## maximum id from all sources
max_id=$(echo -e "$max_db_id"'\n'"$max_scdb_id"'\n'"$max_atlasdb_id"'\n'"$max_sc_id"'\n'"$max_curation" | sort -nr | head -n1)

## current max curated
echo "Current curated maximum accession : E-${accession_type}-$(($max_id))"

## next accession
echo "Next accession : E-${accession_type}-$(($max_id+1))"

echo "update reference_ids SET max_id='$(($max_id+1))' where acc_prefix='E-${accession_type}';" | psql "$dbConnection" > /dev/null