#!/usr/bin/env python
"""Script to generate a list of GEO brokered ENA transcriptomics studies that have raw data"""

import argparse
import json
import logging
import re
from os import path, environ
from sys import exit

import numpy as np
import pandas as pd
import requests
import xmltodict


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('-t', '--type', help='Please provide type as "bulk" or "singlecell"', required=True)
    parser.add_argument('-o', '--output', help='Please provide absolute path to output directory', required=True)
    parser.add_argument('-l', '--limit', help="Limit for number of results returned from ENA API")
    parser.add_argument('-v', '--verbose', action="store_const", const=10, default=20,
                        help="Print more detailed logging", )
    return parser.parse_args()


# Pattern to find single cell studies
sc_regex = re.compile("single[ _-]cell|cell-to-cell|scRNA|10x|single[ _-]nucleus|snRNA-seq", re.IGNORECASE)


def is_singlecell(title):
    """Determine single cell experiments based on title"""
    return bool(title) and bool(sc_regex.search(title))


def get_geo_study_list(logger, bulk_or_singlecell, limit=""):
    """Fetch list of GEO-brokered transcriptomics studies via ENA API
    and parse study XML to read title and organism.
    Returns a Pandas data frame for the given type (bulk or single cell)."""

    # Check for env variable to overwrite URL
    # e.g. ENA_GEO_BASE_URL='https://www.ebi.ac.uk/ena/browser/api/xml/search'

    base_url = environ.get("ENA_GEO_BASE_URL") or "https://www.ebi.ac.uk/ena/browser/api/xml/search"
    params = {"result": "read_study",
              "query": f"library_source=\"TRANSCRIPTOMIC\" AND center_name=\"GEO\"",
              "gzip": "false",
              "dataPortal": "ena"
              }
    if limit:
        params["limit"] = str(limit)
    u = requests.get(base_url, params=params)

    logging.debug(u.url)
    raw_xml = u.text
    xml_dict = xmltodict.parse(raw_xml)

    bulk_studies = []
    singlecell_studies = []

    logger.debug("Start parsing results")

    for project in xml_dict.get("PROJECT_SET", {}).get("PROJECT"):
        study = {}

        ids = project.get("IDENTIFIERS", {})
        study["project"] = ids.get("PRIMARY_ID")
        study["study"] = ids.get("SECONDARY_ID")
        study["geo"] = ids.get("EXTERNAL_ID", {}).get("#text", "")

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

    base_url = environ.get("EBI_SERACH_BASE_URL") or "https://www.ebi.ac.uk/ebisearch/ws/rest/nucleotideSequences"
    params = {"query": geo_accession,
              "format": "json"}
    u = requests.get(base_url, params=params)
    logging.debug(u.url)
    result = json.loads(u.text)
    for entry in result.get("entries", []):
        if entry.get("source", "") == "sra-study":
            ena_study = entry.get("id", "")
            logging.info(f"Found ENA study accession for {geo_accession}: {ena_study}")
            return ena_study


if __name__ == "__main__":
    args = get_args()

    if args.type not in ("bulk", "singlecell"):
        print("Type is not recognised. Must be \"bulk\" or \"singlecell\".")
        exit(1)

    if not path.exists(args.output):
        print("Output path does not exist.")
        exit(1)

    if args.limit:
        try:
            int(args.limit)
        except ValueError:
            print("Limit is not a numerical value.")
            exit(1)

    logger = logging.getLogger()
    logging.basicConfig(format='%(levelname)s: %(message)s', level=args.verbose)

    logging.info("Retrieving GEO study list from ENA.")
    study_table = get_geo_study_list(logger, args.type, limit=args.limit)

    # Remove other columns for compatibility with further workflow
    try:
        study_table = study_table[["geo", "study"]]
    except KeyError:
        study_table = pd.DataFrame()

    logging.debug(f"Found {len(study_table)} raw {args.type} entries")

    # Look up the SRA study accession where it is missing
    study_table["study"] = study_table[["geo", "study"]].apply(lambda x: lookup_sra_study(x[0]) if not x[1] else x[1], axis=1)

    # Filter invalid entries with multiple or no accessions (these are mostly GEO superseries)
    study_table.replace("", np.nan, inplace=True)
    study_table.dropna(axis='index', how='any', inplace=True)
    logging.info(f"Found {len(study_table)} filtered {args.type} GEO-to-SRA study mappings")

    # The name of the output file is important for the rest of the pipeline
    output_file = path.join(args.output, "geo_{}_rnaseq.tsv".format(args.type))
    logging.info(f"Writing file {output_file}")
    study_table.to_csv(output_file, sep='\t', index=False, header=False)
