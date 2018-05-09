#!/bin/bash

# Source script from the same (prod or test) Atlas environment as this script
scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
projectRoot=${scriptDir}/..
source $projectRoot/geo_import/geo_import_routines.sh
today="`eval date +%Y-%m-%d`"

if [ $# -lt 3 ]; then
        echo "Usage: $0 pgAtlasUser dbIdentifier email"
        echo "e.g. $0 atlasprd3 pro suhaib@ebi.ac.uk"
        exit 1
fi

pgAtlasUser=atlasprd3
dbIdentifier=pro
email=$3


GEO_FILES=$ATLAS_PROD/GEO_import/geo_import_supporting_files
pushd $GEO_FILES

## Script which retrieves ENA study ids and organsim names for RNA-seq experiments from ENA
## converts ENA study ids to GEO (GSE) ids using API (eutils.ncbi.nlm.nih.gov/entrez/eutils/)
## ENA ids that do not exist in GEO are recorded in rnaseq_ena_gse_pooling.log
## Filters GSE ids that have already been loaded in AE2
## output of the script list of filtered GSE_ids / ENA_study_id in geo_rnaseq.tsv
$projectRoot/geo_import/rnaseq_ena_gse_pooling.py > rnaseq_ena_gse_pooling.$today.log

if [ $? -ne 0 ]; then
   "ERROR: rnaseq_ena_gse_pooling" >&2    
    exit 1
fi 

## ENA study ids that do exist in GEO import
makeNoGEOImportList() {
 gsePoolingLog=$1
 cat $gsePoolingLog | grep "Not in GEO" | awk -F" " '{print $5}' > ENA_IDs_NotInGEO.tmp

 test -s "$gsePoolingLog" || (  >&2 echo "$0 gse pooling log file not found: $gsePoolingLog" ; exit 1 )

 join -1 1 -2 2 -o 1.1,2.1 <(cat ENA_IDs_NotInGEO.tmp | sort ) <(curl -s 'https://www.ebi.ac.uk/fg/rnaseq/api/tsv/getBulkRNASeqStudiesInSRA' | sort -k 2) | sort -u 
 
 rm ENA_IDs_NotInGEO.tmp
}

makeNoGEOImportList rnaseq_ena_gse_pooling.$today.log > NotInGEO_list.txt


# Set up DB connection details
# get password file
pgPassFile=$ATLAS_PROD/sw/${pgAtlasUser}_gxpatlas${dbIdentifier}
if [ ! -s "$pgPassFile" ]; then
    echo "ERROR: Cannot find password for $pgAtlasUser and $dbIdentifier" >&2  
    exit 1
fi

pgAtlasDB=gxpatlas${dbIdentifier}
pgAtlasHostPort=`cat $pgPassFile | awk -F":" '{print $1":"$2}'`
pgAtlasUserPass=`cat $pgPassFile | awk -F":" '{print $5}'`
if [ $? -ne 0 ]; then
    email_log_error "ERROR: Failed to retrieve DB password" $log $email    
    exit 1
fi 
dbConnection="postgresql://${pgAtlasUser}:${pgAtlasUserPass}@${pgAtlasHostPort}/${pgAtlasDB}"

## remove ENA_IDs already been import before
filterGEOImport() {
 dbConnection=$1
 GSEImport=$2
 GSELoaded=`echo "select geo_acc from atlas_eligibility;" | psql $dbConnection | tail -n +3 | head -n -2 | sed 's/ //g' | tr '\t' '\n' | sort -u` 
 comm -23 <(cat $GSEImport | cut -f 1 | sort ) <(echo -e $GSELoaded | tr ' ' '\n' | sort )
}

## filter GSE ids that have already been imported in the atlas eligibility database
filterGEOImport $dbConnection geo_rnaseq.tsv > latest_geo_accessions.txt

## Download GEO impport soft files and anb convert to MAGE-TAB format
bsub -q production-rh7 -cwd `pwd` -M 80000 -R "rusage[mem=80000]" -o geo_import.out -e geo_import.err "$projectRoot/geo_import/import_geo_subs.pl -f latest_geo_accessions.txt"
if [ $? -ne 0 ]; then
    "ERROR: import_geo_subs.pl LSF submission "  >&2  
    exit 1
fi 

### 