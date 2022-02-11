# geo-importer

# geo import release v0.1.0

Atlas Prod Importer for GEO

import_geo_sub.pl runs the import of the GEO experiment files. The SOFT file and data files are downloaded to to desired location path fetched from config.yml files and converted to MAGE-TAB using new_soft2magetab.pl. You can find a log file from the soft->magetab conversion in this download directory.

Usage: import_geo_subs.pl -x -f list_of_GSE_ids.txt -o output_path

-o output_paths :
 RNA-seq : $ATLAS_PROD/GEO_import/GEOImportDownload
 single cell : $ATLAS_PROD/GEO_import/single_cell/GEOImportDownload

for example, cat list_of_GSE_ids.txt, should result something like this GSE98816 GSE99058 GSE99235 The -x additional flag indicates the supplementary files should not be downloaded. For microarrays, the -x should not be used
(eg. usage : $ATLAS_PROD/sw/atlasinstall_prod/atlasprod/geo_import/import_geo_subs.pl -f list_of_GSE_ids.txt -x -o output_directory_path") as we need to download raw (.cel/txt) supplementary files
Dwonloaded and converted MAGE-TAB metadata are stored in respectiveGEOImportDownload/GSExxx_output

A python script rnaseq_ena_gse_pooling.py is used to retrieve ENA study ids and converting to GEO based GSE ids. This script depends on RNA-seqer API is used to retrieve ENA study ids and organism name from ENA (http://www.ebi.ac.uk/fg/rnaseq/api/json/getBulkRNASeqStudiesInSRA) GEO studies that have been previously downloaded in ArrayExpress (AE2) are filtered so there are no redundant downloads. NCBI eutilis (http://eutils.ncbi.nlm.nih.gov/entrez/eutils) is used for converting filtered ENA study id to GSE id. The output list of converted GSE id are stored as geo_rnaseq.tsv under geo_import_supporting_files ENA ids that do not have meta-data in GEO are recorded in NotInGEO_list.txt that has ENA study id and associated organism name which may be useful for curators to prioritise for ENA import.

The GSExx ids (geo_rnaseq.tsv) is further filtered to remove GSE ids exist in atlas_eligibility table in atlasprd3 database to make the latest geo accessions list latest_geo_accessions.txt ready for GEO import.



## Install dependencies

Conda packages:
```
conda install -c bioconda perl-atlas-modules
conda install -c bioconda magetab-curation-scripts
conda install -c ebi-gene-expression-group atlas-bash-util
conda install -c bioconda perl-go-perl
conda install -c bioconda perl-config-tiny
```

Perl dependencies:
- cpanm LWP::UserAgent::ProxyAny
- OWL::Simple::Parser
- MeSH::Parser::ASCII
- Bio::Phenotype::OMIM::OMIMparser


Python dependencies:
- Python (3.8)
- pandas (1.4.0)
- requests (2.27.1)


ENV variables:
```
dbConnection
ATLAS_PROD_LSF_DEFAULT_QUEUE
FASTQ_FILE_REPORT
```
