

db_f=None
subset_f=None


import gffutils
import pandas as pd
import argparse

# Set up argument parser
parser = argparse.ArgumentParser(description='Process GFF database and subset file.')
parser.add_argument('-d','--database_file', dest="database_file",required=True, help='Path to the GFF database file')
parser.add_argument('-i','--isoform_file', dest="isoform_file",required=True, help='Path to the subset file')
parser.add_argument('-o','--output',dest="output_file", required=True, help='Path to the output file')

# Parse arguments
args = parser.parse_args()

# Get file paths from arguments
db_f = args.database_file
subset_f = args.isoform_file
output_f = args.output_file

# Read subset data
subset_dat = pd.read_csv(subset_f, header=None, sep='\t')

# Connect to database
db = gffutils.FeatureDB(db_f)

msg_counter = 0

# Open output file for writing
recorded_genes=[]
with open(output_f, 'w') as out_file:
    for isoform in subset_dat[0].tolist():
        transcript = db[isoform]

        # Write parents (should be one parent)
        num_parents=0
        for parent in db.parents(transcript):
            if parent.id in recorded_genes:
                gene_id=parent.id
                print(f"SKIPPING gene record {gene_id}. Recorded already...")
            if (parent.id!=transcript.id) and (parent.id not in recorded_genes):
                out_file.write(str(parent) + '\n')
                recorded_genes.append(parent.id)
                num_parents+=1
                if num_parents > 1:
                    print('WARNING: more than one parent',flush=True)

        # Write transcript
        out_file.write(str(transcript) + '\n')

        # Write children (exons first)
        for child in db.children(transcript, featuretype='exon',order_by='start'):
            if child.id != transcript.id:
                out_file.write(str(child) + '\n')

        for child in db.children(transcript,order_by=['featuretype','start']):
            if child.featuretype!='exon':
                if child.id != transcript.id:
                    out_file.write(str(child) + '\n')

        msg_counter += 1
        if msg_counter % 100==0:
            print(f"Finished {msg_counter} transcripts..",flush=True)
