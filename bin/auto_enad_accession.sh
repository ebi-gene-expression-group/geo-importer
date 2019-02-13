#!/bin/bash

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
projectRoot=${scriptDir}/..
source $projectRoot/../bash_util/generic_routines.sh

# Capture call arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <dbUser> <dbSID>"
    echo "e.g. $0 atlasprd3 pro" >&2
    exit 1;
fi

pgAtlasUser=$1
dbIdentifier=$2

dbConnection=$(get_db_connection $pgAtlasUser $dbIdentifier)

max_db_id=$(psql -d "$dbConnection" -a -f $scriptDir/auto_enad_accession.sql | grep "E-ENAD-" | tail -n1 | sed 's/[^0-9]*//g')

max_single_id=$(find $ATLAS_PROD/singlecell/experiment -type f -name "E-ENAD-*" -exec basename {} ';' | sed 's/[^0-9]*//g' | sort -nr | head -n1)

max_id=$(echo -e "$max_db_id"'\n'"$max_single_id" | sort -nr | head -n1)

echo "E-ENAD-$(($max_id+1))"

echo "update reference_ids SET max_id='$(($max_id+1))' where acc_prefix='E-ENAD';" | psql "$dbConnection" > /dev/null