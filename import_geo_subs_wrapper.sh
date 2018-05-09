#!/bin/bash
#  wrapper script for the import_geo_subs.pl script
# installed in bin by EBI::FGPT package deployment

SCRIPT_HOME=/nfs/production3/ma/home/atlas3-production/sw/atlasinstall_prod/atlasprod/geo_import
FILES_HOME=/nfs/production3/ma/home/atlas3-production/GEO_import/geo_import_supporting_files/
export http_proxy=http://www-proxy.ebi.ac.uk:3128
export PERL5LIB=/nfs/ma/home/fgpt/sw/lib/perl/CentOS_prod/lib64/perl5/site_perl:/nfs/ma/home/fgpt/sw/lib/perl/CentOS_prod/lib:$SCRIPT_HOME/lib
today="`eval date +%Y-%m-%d`"

pushd $FILES_HOME || exit 1 > /dev/null
 if [ -f geo_rnaseq.tsv ]; then
 	/usr/bin/perl $SCRIPT_HOME/import_geo_subs.pl "$@" | tee rnaseq_geo_import_$today.log
 else
  	echo "geo_rnaseq.tsv not found"
 fi
popd || exit 1 > /dev/null
