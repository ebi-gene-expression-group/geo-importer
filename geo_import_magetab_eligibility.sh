#!/bin/bash

# script performs geo import magetab elibility checks and populates db table with relevant meta-data for each experiment, 
# number of assays, factor value, validation and eligibility status required for curation.

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $ATLAS_PROD/sw/atlasinstall_prod/atlasprod/db/scripts/experiment_loading_routines.sh
source /ebi/microarray/home/suhaib/Atlas/GEO_import/geo_import_routines.sh
today="`eval date +%Y-%m-%d`"

if [ $# -lt 3 ]; then
    echo "Usage: $0 atlasprd3 pro full_path_to_geo_ena_ids "
    echo "e.g. $0 atlasprd3 pro geo_rnaseq.tsv"
    exit 1;
fi

pgAtlasUser=$1
dbIdentifier=$2
geo_ena_mapping=$3

SUPPORT_FILES=/nfs/production3/ma/home/atlas3-production/GEO_import/geo_import_supporting_files

# get password file
pgPassFile=$ATLAS_PROD/sw/${pgAtlasUser}_gxpatlas${dbIdentifier}
if [ ! -s "$pgPassFile" ]; then
    echo "ERROR: Cannot find password for $pgAtlasUser and $dbIdentifier"  >&2
    exit 1
fi

pgAtlasDB=gxpatlas${dbIdentifier}
pgAtlasHostPort=`cat $pgPassFile | awk -F":" '{print $1":"$2}'`
pgAtlasUserPass=`cat $pgPassFile | awk -F":" '{print $5}'`
dbConnection="postgresql://${pgAtlasUser}:${pgAtlasUserPass}@${pgAtlasHostPort}/${pgAtlasDB}"

expPath=/nfs/production3/ma/home/atlas3-production/GEO_import/GEOImportDownload
find ${expPath} -mindepth 1 -maxdepth 1 | xargs -n1 basename \
 | while read -r exp ; do
    echo $exp
    expAcc=`echo -e $exp | sed 's/_output//g'`
    pushd $expPath/$exp/
        
     if [[ -e "${expAcc}.idf.txt" || -e "${expAcc}.merged.idf.txt" ]]; then
          rename_magetab $expAcc > /dev/null 2>&1
          echo "renamed merged magetab - ${expAcc}"
  
	       if  [ ! -s "${expAcc}-sdrf.txt" ]; then 
               
           	echo "splitting MAGE-TAB - $expAcc"
		        if [ -s "${expAcc}.idf.txt" ]; then
		          $ATLAS_PROD/sw/atlasinstall_prod/atlasprod/curation/split_magetab.pl ${expAcc}.idf.txt
		        elif [ -s "${expAcc}.merged.idf.txt" ]; then
                $ATLAS_PROD/sw/atlasinstall_prod/atlasprod/curation/split_magetab.pl ${expAcc}.merged.idf.txt
		        else
		        >&2 echo "data file not found in $exp" ;
		        fi

		            if  [ ! -s ${expAcc}_atlas_eligibility.out ]; then
       
           		     echo "validating MAGE-TAB - $expAcc"
           		     /nfs/production3/ma/home/atlas3-production/sw/atlasinstall_prod/atlasprod/curation/validate_magetab.pl -m ${expAcc}.merged.idf.txt | tee ${expAcc}_validate_magetab.out
         
           		     echo "Atlas eligility check - $expAcc"
           		     /nfs/production3/ma/home/atlas3-production/sw/atlasinstall_prod/atlasprod/curation/check_atlas_eligibility.pl -m ${expAcc}.merged.idf.txt | tee ${expAcc}_atlas_eligibility.out
             
        		      echo "Loading in the database - $expAcc"
           		     exp_loading_check $expAcc $geo_ena_mapping $dbConnection
          
	             else
			             echo "${expAcc}_atlas_eligibility done"
           		     exp_loading_check $expAcc $geo_ena_mapping $dbConnection
                  echo "Loaded in the database - $expAcc"
        	     fi
    	
	       else
           echo "sdrf exist"
           exp_loading_check $expAcc $geo_ena_mapping $dbConnection
           echo "Loaded in the database - $expAcc"         
        fi
	
   else
	   echo "MAGE-TAB for $expAcc missing"
   fi 
  popd
done


## create atlas accession folders (E-GEOD-xxx) under $ATLAS_PROD/GEO_import/GEOD and sync all mage-tab files 
echo "Creating folders and moving files"         
move_files
