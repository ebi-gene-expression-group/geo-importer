"""Script to generate a list of GEO brokered ENA transcriptomics studies that have raw data"""

import argparse
import json
import re
from os import path
from sys import exit

import pandas as pd
import requests
import xmltodict


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('-t', '--type', help='Please provide type as "bulk" or "singlecell"', required=True)
    parser.add_argument('-o', '--output', help='Please provide absolute path to output directory"', required=True)
    return parser.parse_args()


# Pattern to find single cell studies
sc_regex = re.compile("single[ _-]cell|cell-to-cell|scRNA|10x|single[ _-]nucleus|snRNA-seq", re.IGNORECASE)


def is_singlecell(title):
    """Determine single cell experiments based on title"""
    if title:
        if sc_regex.search(title):
            return True
    return False


def get_geo_study_list(bulk_or_singlecell):
    """Fetch list of GEO-brokered transcriptomics studies via ENA API
    and parse study XML to read title and organism.
    Returns a Pandas data frame for the given type (bulk or single cell)."""

    limit = "100000"
    library_source = "TRANSCRIPTOMIC"

    ena_query = f"https://www.ebi.ac.uk/ena/browser/api/xml/search?result=read_study&query=library_source%3D%22{library_source}%22%20AND%20center_name%3D%22GEO%22&limit={limit}&gzip=false&dataPortal=ena&includeMetagenomes=false"

    u = requests.get(ena_query)
    raw_xml = u.text
    xml_dict = xmltodict.parse(raw_xml)

    bulk_studies = []
    singlecell_studies = []

    for project in xml_dict.get("PROJECT_SET", {}).get("PROJECT"):
        study = {}

        ids = project.get("IDENTIFIERS", {})
        study["project"] = ids.get("PRIMARY_ID")
        study["study"] = ids.get("SECONDARY_ID")
        study["geo"] = ids.get("EXTERNAL_ID", {}).get("#text", "")

        # For some studies the ENA study accession is missing, let's look it up
        if study["geo"] and not study["study"]:
            study["study"] = lookup_sra_study(study["geo"])

        study["title"] = project.get("TITLE", "")
        study["taxonomy"] = project.get("SUBMISSION_PROJECT", {}).get("ORGANISM", {}).get("SCIENTIFIC_NAME", "")

        # Sort by single cell
        if is_singlecell(study["title"]):
            singlecell_studies.append(study)
        else:
            bulk_studies.append(study)

    if bulk_or_singlecell == "singlecell":
        return pd.DataFrame.from_records(singlecell_studies)

    elif bulk_or_singlecell == "bulk":
        return pd.DataFrame.from_records(bulk_studies)


def lookup_sra_study(geo_accession):
    """Use EBI search API to retrieve the SRA study accession for a given GEO study accession
    if it is not found in the study XML"""

    ebi_query = f"https://www.ebi.ac.uk/ebisearch/ws/rest/nucleotideSequences?query={geo_accession}&format=json"

    u = requests.get(ebi_query)
    result = json.loads(u.text)
    for entry in result.get("entries", []):
        if entry.get("source", "") == "sra-study":
            return entry.get("id", "")


if __name__ == "__main__":
    args = get_args()

    if args.type not in ("bulk", "singlecell"):
        print("Type is not recognised. Must be \"bulk\" or \"singlecell\".")
        exit(1)

    if not path.exists(args.output):
        print("Output path does not exist.")
        exit(1)

    output_file = path.join(args.output, "geo_{}_rnaseq.tsv".format(args.type))
    study_table = get_geo_study_list(args.type)
    # This contains the full table, need to trim it to GEO/SRA accession only to match expected output for pipeline
    study_table.to_csv(output_file, sep='\t', index=False, header=False)
