import pyranges as pr
import pandas as pd
import argparse
import os

def is_valid_gtf(file_path):
    """Check if the GTF file contains non-comment lines."""
    if not os.path.exists(file_path) or os.path.getsize(file_path) == 0:
        return False
    with open(file_path, 'r') as f:
        for line in f:
            if not line.startswith("#"):  # Check for at least one non-comment line
                return True
    return False
def load_ref_gtf(ref_gtf_f):
    if ref_gtf_f is None:
        return []
    if not is_valid_gtf(ref_gtf_f):
        print('WARNING: Skipping empty reference GTF:', ref_gtf_f)
        return []
    df = pr.read_gtf(ref_gtf_f, as_df=True)
    print('Loaded reference GTF: {0}'.format(ref_gtf_f))
    return [df]
def load_gtfs(query_gtf_fs):
    dfs = []
    for query_gtf_f in query_gtf_fs:
        if is_valid_gtf(query_gtf_f):
            df = pr.read_gtf(query_gtf_f, as_df=True)
            dfs.append(df)
            print('Loaded {0}'.format(query_gtf_f))
        else:
            print('WARNING: Skipping empty GTF file:', query_gtf_f)
    return dfs


def recount_gene_transcripts(df):
    counts = (
        df[df['Feature'] == 'transcript']
        .groupby('gene_id')['transcript_id']
        .nunique()
        .rename('transcript_count')
    )
    df = df.merge(counts, on='gene_id', how='left')
    mask = df['Feature'] == 'gene'
    df.loc[mask, 'transcripts'] = df.loc[mask, 'transcript_count'].astype(str)
    df = df.drop(columns='transcript_count')
    return df

def backfill_gene_name(df):
    gene_names = (
        df[df['Feature'] == 'gene'][['gene_id', 'gene_name']]
        .drop_duplicates('gene_id')
        .dropna(subset=['gene_name'])
    )
    df = df.drop(columns=['gene_name'], errors='ignore')
    return df.merge(gene_names, on='gene_id', how='left')

def merge_dfs(dfs):
    combined = pd.concat(dfs, ignore_index=True)

    # deduplicate genes: keep first occurrence of each gene_id
    gene_rows = combined[combined['Feature'] == 'gene'].drop_duplicates(subset='gene_id', keep='first')

    # deduplicate transcripts: first occurrence of each transcript_id (transcript row) wins
    kept_transcript_ids = (
        combined[combined['Feature'] == 'transcript']
        .drop_duplicates(subset='transcript_id', keep='first')['transcript_id']
    )

    # keep all non-gene rows (transcript + exons + CDS etc.) for kept transcript_ids only
    non_gene_rows = combined[combined['Feature'] != 'gene']
    non_gene_rows = non_gene_rows[non_gene_rows['transcript_id'].isin(kept_transcript_ids)]

    return pd.concat([gene_rows, non_gene_rows], ignore_index=True)

GTF_FIXED_COLS = {'Chromosome', 'Source', 'Feature', 'Start', 'End', 'Score', 'Strand', 'Frame'}
FEATURE_ORDER = {'gene': 0, 'transcript': 1}

def format_gtf_output(df):
    df = df.copy()
    df['_feat_order'] = df['Feature'].map(FEATURE_ORDER).fillna(2).astype(int)
    df = df.sort_values(['gene_id', '_feat_order', 'transcript_id', 'Start'])
    df = df.drop(columns='_feat_order')

    attr_cols = [c for c in df.columns if c not in GTF_FIXED_COLS]
    lines = []
    for _, row in df.iterrows():
        attrs = ' '.join(
            '{0} "{1}";'.format(k, row[k])
            for k in attr_cols
            if pd.notna(row[k]) and row[k] != ''
        )
        lines.append('\t'.join([
            str(row['Chromosome']), str(row['Source']), str(row['Feature']),
            str(int(row['Start']) + 1), str(int(row['End'])),
            str(row['Score']), str(row['Strand']), str(row['Frame']),
            attrs
        ]))
    return '\n'.join(lines) + '\n'



def main():
    parser = argparse.ArgumentParser(description="Process multiple GTF files with a reference GTF and selected transcripts.")

    parser.add_argument(
        "-q", "--query_gtf_files",
        dest="query_gtf_fs",
        nargs="+",  # Allows multiple files
        required=False,
        default=None,
        help="Input query GTF files (multiple allowed)"
    )
    parser.add_argument(
        "-Q", "--query_gtf_fofn",
        dest="query_gtf_fofn",
        required=False,
        default=None,
        help="Path to file listing input query GTF files"
    )

    parser.add_argument(
        "-o", "--output_gtf_file",
        dest="output_gtf_f",
        required=True,
        help="Output GTF file"
    )

    parser.add_argument(
        "-r", "--ref_gtf_file",
        dest="ref_gtf_f",
        required=False,
        default=None,
        help="Reference GTF file"
    )
    parser.add_argument(
        "-S", "--select_transcripts_f",
        dest="select_transcripts_f",
        required=False,
        default=None,
        help="File containing selected reference transcript IDs"
    )

    parser.add_argument(
        "-s", "--select_transcripts",
        dest="select_transcripts_list",
        required=False,
        default=None,
        nargs='+',
        help="List of selected reference transcript IDs"
    )



    args = parser.parse_args()

    print("Output GTF file:", args.output_gtf_f)

    if args.query_gtf_fs is not None:
        print("Query GTF files:",','.join(args.query_gtf_fs) )
    if args.query_gtf_fofn is not None:
        print("Query FOFN:",args.query_gtf_fofn)
    if args.ref_gtf_f is not None:
        print("Reference GTF file:", args.ref_gtf_f)
    if args.select_transcripts_f is not None:
        print("Select reference transcripts file:", args.select_transcripts_f)
    if args.select_transcripts_list is not None:
        print("Select reference transcripts list:", ', '.join(args.select_transcripts_list))


    query_gtf_fs = args.query_gtf_fs
    query_gtf_fofn = args.query_gtf_fofn
    output_gtf_f = args.output_gtf_f
    ref_gtf_f = args.ref_gtf_f
    select_transcripts_f = args.select_transcripts_f
    select_transcripts_list = args.select_transcripts_list

    ref_given = ref_gtf_f is not None
    subset_given = (select_transcripts_f is not None) or (select_transcripts_list is not None)
    query_given = (query_gtf_fs is not None) or (query_gtf_fofn is not None)

    if not query_given:
        raise ValueError('Query not given either as list or FOFN')
    if query_gtf_fs is None:
        query_gtf_fs = pd.read_csv(query_gtf_fofn, sep='\t', header=None)[0].tolist()

    query_dfs = load_gtfs(query_gtf_fs)
    ref_dfs = load_ref_gtf(ref_gtf_f) if ref_given and not subset_given else []

    all_dfs = ref_dfs + query_dfs
    if len(all_dfs) == 0:
        # No non-empty input GTFs (e.g. every query GTF was empty and no usable
        # reference). Emit an empty output GTF instead of crashing in pd.concat.
        print('WARNING: no non-empty input GTFs; writing empty output GTF:', output_gtf_f, flush=True)
        open(output_gtf_f, 'w').close()
        return

    merged_df = merge_dfs(all_dfs)
    merged_df = backfill_gene_name(merged_df)
    merged_df = recount_gene_transcripts(merged_df)
    output_str = format_gtf_output(merged_df)
    with open(output_gtf_f, 'w') as out_f:
        out_f.write(output_str)


if __name__=='__main__':
    main()


#USAGE: python collect_gtfs.py -q file1.gtf file2.gtf -r gencode.v48.annotation.sorted.gtf -o merge.gtf
#USAGE: python collect_gtfs.py -Q gtf_files.txt -r gencode.v48.annotation.sorted.gtf -o merge.gtf
