#!/usr/bin/env python
# coding=utf-8
import requests
import pandas as pd
import os
import argparse

__author__ = 'Suhaib Mohammed'

# GEO eutils API
BASE_URL = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/'

# ArrayExpress API to retrieve existing downloaded GEO/ENA studies.
AE2_ENA = 'https://www.ebi.ac.uk/fg/rnaseq/api/json/getAE2ToENAMapping'

# Parse API curl
def parse_RNAseqAPI(api_url):
    try:
        response = requests.get(api_url)
        """status code of the response"""
        if response.status_code == 200:
            print("API response successful")
            json_data = response.json()
            return (json_data)
        elif response.status_code == 403:
            print("resource you’re trying to access is forbidden")
        elif response.status_code == 404:
            print("resource you tried to access wasn’t found on the server.")
        else:
            print('Got an error code:', response.status_code)
    except requests.exceptions.RequestException as e:
        print(e)
        sys.exit(1)

# Retrieve ENA study ids and organism list
def fetch_study_ids(response_data):
    if (type(response_data) is list):
        sc_studies = []
        for ids in response_data:
            sc_studies.append([(ids['STUDY_ID']),ids['ORGANISM']])
        # retrieve all the single cell RNA-seq experiments in ENA.
        df = pd.DataFrame(sc_studies, columns=['study_ids', 'organism'])
        print("RNA-seq studies in ENA = %d " % (df.study_ids.count()))
        return (df)

# For a particular ENA-ID get associated GEO-id using GEO eutilis API
def fetch_gse_ids(sraid):
    url = BASE_URL + 'esearch.fcgi'
    sra=sraid+'[ACCN]'
  #  print 'checking .. %s' % sraid
    data = {'db': 'gds', 'term': sra, 'retmode': 'json'}

    try:
        r = requests.get(url, params=data)
        if 'Error 503' in r.text:
            print('eutils gave Error 503. Waiting 20 secs then trying again')
            time.sleep(20)
            return fetch_gse_ids(sraid)
        if 'esearchresult' in r.json():
            if 'idlist' in r.json()['esearchresult']:
                r_id=r.json()['esearchresult']['idlist']
                if len(r_id) == 1:
                    r_id = r_id[0].encode('utf-8')
                    gse_id = "GSE" + str(int(r_id[1:]))
                    print('%s' % gse_id)
                    return gse_id
                elif len(r_id) == 0:
                    print('Not in GEO - %s' % sraid)
                elif len(r_id) == 2:
                    print('2 GEO ids - %s' % sraid)
            else:
                print('idlist missing in json - %s' % sraid)
        else:
             print('esearchresult missing in json - %s' % sraid)
    except requests.exceptions.RequestException as e:
        print(e)

# convert it to GEO ids list
def convert_gse_list(studies):
     gse_ids = []
     for idx, ids in enumerate(studies.study_ids):
         gse_ids.append((fetch_gse_ids(ids),ids))
     gse_ids = [x for x in gse_ids if x[0] is not None]
     gse_ids = pd.DataFrame(gse_ids)
     return gse_ids

# Function to filter GEO ids that exist in ArrayExpress
def exclude_atlas_loaded(AE2_ENA,studies):
    ae2_df = pd.read_json(AE2_ENA)
    df_load = studies[studies['study_ids'].isin(ae2_df.STUDY_ID) == False]
    return(df_load)

# write dataframe in tsv format
def write_dataframe_to_tsv(filename,object,output):
    file_path = os.path.join(output, filename)
    file_name = file_path + '.tsv'
    object.to_csv(file_name, sep='\t', index=False, header=None)

# get all arguments
def get_args(argv=None):
    parser = argparse.ArgumentParser(
        description='This program retrieves ENA-ids and organism list for bulk or singlecell RNA-seq experiments, '
                    'and convert it to GEO ids. Filtering ids the ones which already exist in ArrayExpress')
    parser.add_argument('-t', '--type', help='Please provide type as "bulk" or "singlecell"', required=True)
    parser.add_argument('-o', '--output', help='Please provide absolute path to output directory"', required=True)
    return vars(parser.parse_args())

if __name__ == "__main__":
    args = get_args()
    if args['type'] == 'singlecell':
        RNA_SEQ_API = 'http://www.ebi.ac.uk/fg/rnaseq/api/json/getSingleCellStudies'
    elif args['type'] == 'bulk':
        RNA_SEQ_API = 'http://www.ebi.ac.uk/fg/rnaseq/api/json/getBulkRNASeqStudiesInSRA'
    print("Processing " + args['type'] + " RNA-seq studies in ENA")
    print("Output - " + args['output'])
    data = parse_RNAseqAPI(RNA_SEQ_API)
    studies = fetch_study_ids(data)
    load_studies = exclude_atlas_loaded(AE2_ENA, studies)
    gse = convert_gse_list(studies)
    print("Number of GEO expriments loaded = %d" %(len(gse)))
    write_dataframe_to_tsv(filename='geo_' + args['type'] + '_rnaseq', object = gse, output=args['output'])
