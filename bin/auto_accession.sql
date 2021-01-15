DELETE FROM REFERENCE_IDS WHERE acc_prefix=:'TYPE';

insert into REFERENCE_IDS values (:'TYPE', (
    select max(to_number(replace(accession, concat(:'TYPE','-'), ''), '9999999')) from experiment where accession like concat(:'TYPE','-%') ));

-- Stored function to return the next available accession, for the prefix p_prefix
CREATE OR REPLACE FUNCTION mint_accession(p_prefix char(15), OUT p_accession varchar(255))
AS $$
BEGIN
    UPDATE reference_ids SET max_id = max_id + 1 where acc_prefix = p_prefix;
    SELECT concat(acc_prefix,'-',max_id) into p_accession from reference_ids where acc_prefix = p_prefix;
END; $$
LANGUAGE plpgsql;

\set AUTOCOMMIT off

select p_accession from mint_accession(:'TYPE');

commit;
