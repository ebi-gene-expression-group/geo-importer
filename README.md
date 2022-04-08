# geo-importer

geo-importer is the Atlas Prod Importer for GEO and its current release version is **v0.1.0**.

## How it works

`import_geo_sub.pl` runs the import of the GEO experiment files. The SOFT file and data files are downloaded to to desired location path fetched from `config.yml` files and converted to MAGE-TAB using `new_soft2magetab.pl`. You can find a log file from the soft->magetab conversion in this download directory.

**Usage**: `import_geo_subs.pl -x -f list_of_GSE_ids.txt -o output_path`

`-o output_paths`:

- RNA-seq : $ATLAS_PROD/GEO_import/GEOImportDownload
- single cell : $ATLAS_PROD/GEO_import/single_cell/GEOImportDownload

Dwonloaded and converted MAGE-TAB metadata are stored in respective `GEOImportDownload/GSExxx_output`

`-f list_of_GSE_ids.txt`:

For example, `cat list_of_GSE_ids.txt`, should result something like this:

```
GSE98816
GSE99058
GSE99235
```

`-x`:

The `-x` additional flag indicates the supplementary files should not be downloaded.

For microarrays, the -x should not be used as we need to download raw (.cel/txt) supplementary files. eg. usage: <br>
`$ATLAS_PROD/sw/atlasinstall_prod/atlasprod/geo_import/import_geo_subs.pl -f list_of_GSE_ids.txt -o output_directory_path`

## Subprocesses

A python script `rnaseq_ena_gse_pooling.py` is used to retrieve ENA study ids and convert to GEO based GSE ids. This script depends on RNA-seqer API, which is used to retrieve ENA study ids and organism names from ENA (http://www.ebi.ac.uk/fg/rnaseq/api/json/getBulkRNASeqStudiesInSRA). GEO studies that have been previously downloaded in ArrayExpress (AE2) are filtered, so there are no redundant downloads. NCBI eutilis (http://eutils.ncbi.nlm.nih.gov/entrez/eutils) is used for converting filtered ENA study id to GSE id. The output list of converted GSE ids are stored as `geo_rnaseq.tsv` under `geo_import_supporting_files`. ENA ids that do not have meta-data in GEO are recorded in `NotInGEO_list.txt` that has ENA study id and associated organism name which may be useful for curators to prioritise for ENA import.

The `geo_import_cron.sh` script encapsulates this process and goes on to filter the GSExx ids (`geo_rnaseq.tsv`) list further to remove GSE ids that already exist in the `atlas_eligibility` table in the atlasprd3 database. The process produces a latest GEO accessions list `latest_geo_accessions.txt` ready to run batch GEO import.

After the batch import is run, the `geo_import_magetab_eligibility.sh` script crawls the Downloads directory and runs 
1) MAGE-TAB split into IDF/SDRF, 
2) Atlas eligibility check,
3) recording of the dataset in the database. 

The optional parameter `-c` can be used to specify a "curation directory" where to copy the generated MAGE-TAB files. 
