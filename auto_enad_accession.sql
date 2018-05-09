DELETE FROM REFERENCE_IDS WHERE acc_prefix='E-ENAD';

-- Initialise the table (based on the output of the following query in AE2 PROD: select max(to_number(replace(accession,'E-ENAD-',''), '99')) from experiment where accession like 'E-ENAD-%';
insert into REFERENCE_IDS values ( 'E-ENAD', (
        select max(to_number(replace(accession,'E-ENAD-',''), '99')) from experiment where accession like 'E-ENAD-%' ));



-- Stored function to return the next available accession, for the prefix p_prefix
CREATE OR REPLACE FUNCTION mint_accession(p_prefix char(15), OUT p_accession varchar(255))
AS $$
BEGIN
    UPDATE reference_ids SET max_id = max_id + 1 where acc_prefix = p_prefix;
    SELECT concat(acc_prefix,'-',max_id) into p_accession from reference_ids where acc_prefix = p_prefix;
END; $$
LANGUAGE plpgsql;

\set AUTOCOMMIT off


select p_accession from mint_accession('E-ENAD');

commit;
