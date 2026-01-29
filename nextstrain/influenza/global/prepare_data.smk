ruleorder: prepare_sequences > parse_niph > parse

rule prepare_metadata:
    input:
        metadata="data/{lineage}/metadata.xlsx",
    output:
        metadata="data/{lineage}/metadata.tsv",
    params:
        old_fields=",".join(config["metadata_fields"]),
        new_fields=",".join(config["renamed_metadata_fields"]),
    conda: "../../workflow/envs/nextstrain.yaml"
    shell:
        r"""
        python3 scripts/xls2csv.py --xls {input.metadata} --output /dev/stdout \
            | csvtk cut -f {params.old_fields} \
            | csvtk rename -f {params.old_fields} -n {params.new_fields} \
            | csvtk sep -f location --na "N/A" --names region,country,division,location --merge --num-cols 4 --sep " / " \
            | csvtk replace -f strain -p " " -r "" \
            | csvtk grep -v -r -f strain -p "[\'\\\\]" \
            | csvtk sort -k strain,accession:r \
            | csvtk uniq -T -f strain > {output.metadata}
        """

rule prepare_sequences:
    input:
        sequences="data/{lineage}/raw_sequences_{segment}.fasta",
    output:
        sequences="data/{lineage}/{segment}.fasta",
    conda: "../../workflow/envs/nextstrain.yaml"
    shell:
        r"""
        # Remove bad names that will crash augur/iqtree (' and \)
        seqkit grep -n -v -r -p "[\'\\\\]" {input.sequences} \
            | seqkit replace -p " " -r "" \
            | seqkit rename \
            | seqkit sort -n -r \
            | seqkit replace -p "\|" -r " " \
            | seqkit rmdup -n > {output.sequences}
        """

rule parse_niph:
    input:
        sequences="data/{lineage}/{segment}.fasta",
        metadata="data/{lineage}/metadata.tsv",
    output:
        metadata="data/{lineage}/metadata_{segment}.tsv",
    conda: "../../workflow/envs/nextstrain.yaml"
    shell:
        r"""
        seqkit seq -n {input.sequences} > {output.metadata}.ids
        python3 scripts/filter_metadata_by_ids.py \
            --metadata {input.metadata} \
            --ids {output.metadata}.ids \
            --output {output.metadata} \
            --id-col strain
        rm -f {output.metadata}.ids
        """
