# coding=utf-8
import requests
import pandas as pd
import os
__author__ = 'Suhaib Mohammed'

BASE_URL = 'http://eutils.ncbi.nlm.nih.gov/entrez/eutils/'
BULK_RNA_SEQER_API='http://www.ebi.ac.uk/fg/rnaseq/api/json/getBulkRNASeqStudiesInSRA'
AE2_ENA = 'https://www.ebi.ac.uk/fg/rnaseq/api/json/getAE2ToENAMapping'

def parse_RNAseqAPI(api_url):
    try:
        response = requests.get(api_url)
        """status code of the response"""
        if response.status_code == 200:
            print "API response successful"
            json_data = response.json()
            return (json_data)
        elif response.status_code == 403:
            print "resource you’re trying to access is forbidden"
        elif response.status_code == 404:
            print "resource you tried to access wasn’t found on the server."
        else:
            print 'Got an error code:', response.status_code
    except Exception:
        pass


def fetch_study_ids(response_data):
    if (type(response_data) is list):
        sc_studies = []
        for ids in response_data:
            sc_studies.append([(ids['STUDY_ID']),ids['ORGANISM']])
        # retrieve all the single cell RNA-seq experiments in ENA.
        df = pd.DataFrame(sc_studies, columns=['study_ids', 'organism'])
        print "RNA-seq studies in ENA = %d " % (df.study_ids.count())
        return (df)

def fetch_gse_ids(sraid):
    url = BASE_URL + 'esearch.fcgi'
    sra=sraid+'[ACCN]'
    data = {'db': 'gds', 'term': sra, 'retmode': 'json'}
    r = requests.get(url, params=data)
    if 'Error 503' in r.text:
      print 'eutils gave Error 503. Waiting 20 secs then trying again'
      time.sleep(20)
      return fetch_gse_ids(sraid)
    r_id=r.json()['esearchresult']['idlist']
    if len(r_id) == 1:
        r_id = r_id[0].encode('utf-8')
        gse_id = "GSE" + str(int(r_id[1:]))
        return gse_id
    elif len(r_id) == 0:
        print 'Not in GEO - %s' % sraid
    elif len(r_id) == 2:
        print '2 GEO ids - %s' % sraid


def convert_gse_list(studies):
     gse_ids = []
     for idx, ids in enumerate(studies.study_ids):
         gse_ids.append((fetch_gse_ids(ids),ids))
     gse_ids = [x for x in gse_ids if x[0] is not None]
     gse_ids = pd.DataFrame(gse_ids)
     return gse_ids

def exclude_atlas_loaded(AE2_ENA,studies):
    ae2_df = pd.read_json(AE2_ENA)
    df_load = studies[studies['study_ids'].isin(ae2_df.STUDY_ID) == False]
    return(df_load)

def write_file_output(filename,object):
    file_path = os.path.join('/nfs/production3/ma/home/atlas3-production/GEO_import/geo_import_supporting_files/', filename)
    file_name = file_path + '.tsv'
    with open(file_name, 'w') as fh:
        for id in object:
            fh.write(''.join(id) + '\n')

def write_dataframe_to_tsv(filename,object):
    file_path = os.path.join('/nfs/production3/ma/home/atlas3-production/GEO_import/geo_import_supporting_files/', filename)
    file_name = file_path + '.tsv'
    object.to_csv(file_name, sep='\t', index=False, header=None)


if __name__ == "__main__":
    data = parse_RNAseqAPI(BULK_RNA_SEQER_API)
    studies = fetch_study_ids(data)
    load_studies = exclude_atlas_loaded(AE2_ENA, studies)
    gse = convert_gse_list(studies)
    print  "Number of GEO expriments loaded = %d" %(len(gse))
    write_dataframe_to_tsv(filename='geo_rnaseq', object = gse)

