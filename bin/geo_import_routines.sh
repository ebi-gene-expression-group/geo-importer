#!/usr/bin/env bash

geo_experiment() {
  expAcc=$1
  gse=$(echo "$expAcc" | sed 's/[0-9]*//g')
  if [ "$gse" == "GSE" ]; then
        return 0
    else
        return 1
  fi
}

get_ena_id(){
 expAcc=$1
 geoEnaMappingFile=$2
 idx=$(grep -n "$expAcc" "$geoEnaMappingFile" | head -n1 | awk -F":" '{print $1}')
 awk 'FNR == '${idx}' {print $2}' "$geoEnaMappingFile"
}

elibility_error_code(){
expAcc=$1
pathToDownloads=$2

geo_experiment "$expAcc"
res=$(geo_experiment "$expAcc")
  if [ $? -ne 0 ]; then
       echo "ERROR: Not GEO experiment type - $expAcc" >&2
  fi
  
  if [ -e "$pathToDownloads/${expAcc}_output/${expAcc}_atlas_eligibility.out" ]; then
    cat "$pathToDownloads/${expAcc}_output/${expAcc}_atlas_eligibility.out" | grep "Atlas eligibility fail codes:" | awk -F":" '{print $2}' | sed 's/-//g'
  fi
}

geo_fixable(){
  expAcc=$1
  pathToDownload=$2

  error_code=$(elibility_error_code "$expAcc" "$pathToDownloads")
  scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

  if [[ -s "$scriptDir/../error_codes.txt" ]]; then
      ERROR_CODES=$scriptDir/../error_codes.txt
  else
      echo "ERROR: error_codes file doesn't exist"
  fi

  code=$(echo "$error_code" | sed 's/,/\t/g' | cut -f 1 | sed -e 's/^\s*//')
  comment=$(cat "$ERROR_CODES" | grep -w "$code" | awk -F"\t" '{print $3}')
  echo -e "$comment"
}

exp_meta_info(){
  expAcc=$1
  pathToDownloads=$2

  GEO_IMPORT_FOLDER=$(echo $pathToDownloads/${expAcc}_output)

    if [[ -s "$GEO_IMPORT_FOLDER/${expAcc}_family.soft" ]]; then
        title=$(cat "$GEO_IMPORT_FOLDER/${expAcc}_family.soft" | grep "Series_title" | awk -F"=" '{print $2}')
        organism=$(cat "$GEO_IMPORT_FOLDER/${expAcc}_family.soft" | grep -P "Platform_organism" | awk -F"=" '{print $2}' | sort -u)
        no_of_samples=$(cat "$GEO_IMPORT_FOLDER/${expAcc}_family.soft" | grep -c "Series_sample_id")
   else
    echo "ERROR: soft file doesn't exist - $expAcc"
  fi
  
  if [[ -s "$GEO_IMPORT_FOLDER/${expAcc}-sdrf.txt" ]]; then
      no_of_replicates=$(cat "$GEO_IMPORT_FOLDER/${expAcc}-sdrf.txt" | cut -d$'\t' -f 1 | tail -n+2 |  uniq -c | awk -F" " '{print $1}' | sort -u | tr "\n" " ")
      factor_value=$(cat "$GEO_IMPORT_FOLDER/${expAcc}-sdrf.txt" | head -n1 | tr "\t" "\n" | grep -P "FactorValue" | awk -F" " '{print $2}' | sed -r 's/(\[|\])//g' | tr "\n" " ")
  else
    echo "ERROR: sdrf file doesn't exist - $expAcc"
 fi

  if [[ -s "$GEO_IMPORT_FOLDER/${expAcc}-idf.txt" ]]; then
     exp_type=$(cat "$GEO_IMPORT_FOLDER/${expAcc}-idf.txt" | grep "Comment\[AEExperimentType\]"  |  cut -d$'\t' -f2 | tr "\n" " ")
  else
     echo "ERROR: idf file doesn't exist - $expAcc"
  fi

  echo -e "$title"'\t'"$organism"'\t'"$no_of_samples"'\t'"$no_of_replicates"'\t'"$factor_value"'\t'"$exp_type"
}


atlas_loaded_experiments(){
  dbConnection=$1
  type=$2

  # experiment that are already loaded
  if [ "$type" == "bulk" ]; then        
      expLoaded=$(echo -e "select accession from experiment where type like 'RNASEQ%';" \
      | psql "$dbConnection" | tail -n +3 | head -n -2 | grep "E-GEOD-" | sed 's/E-GEOD-/GSE/g' | sed 's/^ //g' | sort -u)
  elif [ "$type" == "singlecell" ]; then 
      expLoaded=$(echo -e "select accession from scxa_experiment where type like 'RNASEQ%';" \
      | psql "$dbConnection" | tail -n +3 | head -n -2 | grep "E-GEOD-" | sed 's/E-GEOD-/GSE/g' | sed 's/^ //g' | sort -u)
  fi

  # experiments ongoing in Atlas
  inAtlas=$(echo -e "select jobobject from atlas_jobs;" \
    | psql "$dbConnection" | tail -n +3 | head -n -2 | grep "E-GEOD-" | sed 's/E-GEOD-/GSE/g' | sed 's/^ //g' | sed '/^$/d' | sort -u)

  echo -e "$expLoaded\n$inAtlas" | sed 's/ //g'
}

# function to create experiment accession directory and move all processed files to GEOD
move_files(){
pathToDownloads=$1
pathToCuration=$2

pushd "$pathToDownloads"
  for f in *; do
    expAcc=$(basename "$f" | sed 's/_output//g' | sed 's/GSE/E-GEOD-/g')

    echo "making directory $expAcc"
    exp_dir="$pathToCuration/$expAcc"

    if [ ! -d "$exp_dir" ]; then
      mkdir -p "$exp_dir"
    fi  

    ## while copying preserve time stamps
    rsync -ar $pathToDownloads/$f/*txt* $exp_dir/

    # rename files with ArrayExpress accession prefix
    rename_magetab_files $exp_dir

  done
popd
}

rename_magetab_files(){
  pathToMagetabDir=$1
      pushd "$pathToMagetabDir"
        ## rename all files in the folder
          for filename in *.txt*; do
              mv "$filename" "$(echo "$filename" | sed 's/GSE/E-GEOD-/g')";
          done
      popd
}

sync_experiments_folder(){
  expID=$1
  pathToDownloads=$2
  pathToCuration=$3

## create ArrayExpress accession
  expAcc=$(basename "$expID" | sed 's/_output//g' | sed 's/GSE/E-GEOD-/g')
  
  exp_dir_path="$pathToCuration/$expAcc"

  if [ ! -d "exp_dir_path" ]; then
      mkdir -p "$exp_dir_path"
      # sync files
      rsync -ar $pathToDownloads/$expID/*txt* $exp_dir_path/
      
      # rename files with ArrayExpress accession prefix
      rename_magetab_files $exp_dir_path
  fi    
}

exp_loading_check(){
  expAcc=$1
  geoEnaMappingFile=$2
  dbConnection=$3
  type=$4
  pathToDownloads=$5

  if [ "$type" == "bulk" ]; then        
      count=$(echo "select count(*) from rnaseq_atlas_eligibility where geo_acc='$expAcc';" | psql "$dbConnection" | tail -n +3 | head -n1 | sed 's/ //g')
  elif [ "$type" == "singlecell" ]; then 
      count=$(echo "select count(*) from sc_atlas_eligibility where geo_acc='$expAcc';" | psql "$dbConnection" | tail -n +3 | head -n1 | sed 's/ //g')
  fi

  count_in_atlas=$(atlas_loaded_experiments "$dbConnection" "$type" | grep -c "$expAcc")

  if [ "$count_in_atlas" -ne 0 ]; then
        echo "$expAcc - previously loaded in $type atlas table"
        return 1
  elif [ "$count" -ne 0 ]; then
        echo "$expAcc - already exist in $type atlas eligbility table"
        return 1
  else
        echo "loading $expAcc in db"
        load_eligibility_to_db "$expAcc" "$geoEnaMappingFile" "$dbConnection" "$type" "$pathToDownloads"
        return 0
  fi
}

load_eligibility_to_db(){
  expAcc=$1
  geoEnaMappingFile=$2
  dbConnection=$3
  type=$4 
  pathToDownloads=$5

  ena_id=$(get_ena_id "$expAcc" "$geoEnaMappingFile")
   if [[ -z "$ena_id" ]]; then
      echo "ENA-ID doesn't match for $expAcc" >&2
   fi
   atlas_id=$(echo -e "$expAcc" | sed 's/GSE/E-GEOD-/g')
   error_code=$(elibility_error_code "$expAcc" "$pathToDownloads")
   comment=$(geo_fixable "$expAcc" "$pathToDownloads")
   title=$(exp_meta_info "$expAcc" "$pathToDownloads" | awk -F'\t' '{print $1}')
   organism=$(exp_meta_info "$expAcc" "$pathToDownloads" | awk -F'\t' '{print $2}')
   no_of_samples=$(exp_meta_info "$expAcc" "$pathToDownloads" | awk -F'\t' '{print $3}')
   no_of_replicate=$(exp_meta_info "$expAcc" "$pathToDownloads" | awk -F'\t' '{print $4}')
   factor_value=$(exp_meta_info "$expAcc" "$pathToDownloads" | awk -F'\t' '{print $5}')
   exp_type=$(exp_meta_info "$expAcc" "$pathToDownloads" | awk -F'\t' '{print $6}')

  if [ $type == "bulk" ]; then
       echo "Loading $expAcc to rnaseq_atlas_eligibility"    
       echo "insert into rnaseq_atlas_eligibility values (current_timestamp(0),'$atlas_id','$ena_id','$expAcc','$error_code', '$comment','$title','$organism','$no_of_samples','$no_of_replicate','$factor_value',current_timestamp(0),NULL,NULL,'$exp_type');" | psql "$dbConnection"

  elif [ $type == "singlecell" ]; then 
        echo "Loading $expAcc to sc_atlas_eligibility"    
        echo "insert into sc_atlas_eligibility values (current_timestamp(0),'$atlas_id','$ena_id','$expAcc','$error_code','$comment','$title','$organism','$no_of_samples','$no_of_replicate','$factor_value',current_timestamp(0),NULL,NULL,'$exp_type');" | psql "$dbConnection"
  fi
}


# query experiments for species that are having reference genome in ISL
# extract species and subspecies from RNA-seqer API call for ensembl, plants metazoa and wbps.
query_rnaseq_atlas_eligibility() {
IFS="
"
dbConnection=$1

species_in_ensembl=$(curl -s "https://www.ebi.ac.uk/fg/rnaseq/api/tsv/0/getOrganisms/ensembl" | cut -f 1 | tail -n +2 | awk '{ gsub("_", " ") ; print $0 }' | sed -e 's/^./\U&/')
species_in_plants=$(curl -s "https://www.ebi.ac.uk/fg/rnaseq/api/tsv/0/getOrganisms/plants" | cut -f 1 | tail -n +2 | awk '{ gsub("_", " ") ; print $0 }' | sed -e 's/^./\U&/')
species_in_metazoa=$(curl -s "https://www.ebi.ac.uk/fg/rnaseq/api/tsv/0/getOrganisms/metazoa" | cut -f 1 | tail -n +2 | awk '{ gsub("_", " ") ; print $0 }' | sed -e 's/^./\U&/')
species_in_wbps=$(curl -s "https://www.ebi.ac.uk/fg/rnaseq/api/tsv/0/getOrganisms/wbps" | cut -f 1 | tail -n +2 | awk '{ gsub("_", " ") ; print $0 }' | sed -e 's/^./\U&/')

species_in_isl=$(printf '%s\n' "$species_in_ensembl" "$species_in_plants" "$species_in_metazoa" "$species_in_wbps")
output=""
echo -e "a2_acc'\t'na_study_id'\t'geo_acc'\t'organism'\t'status'\t'exp_type"
for species in $species_in_isl; do
    var=$(echo "select DISTINCT ae2_acc, ena_study_id, geo_acc, organism,status, exp_type from rnaseq_atlas_eligibility where organism like'%$species';" | psql "$dbConnection" | tail -n +3 | head -n -2)
     if [[ -z $var ]]; then
      echo "query didn't succeed for the $species" > /dev/null
     fi
     output+="$var\n"
 done

echo -e "$output" | sed -e '/^ *$/d'
}