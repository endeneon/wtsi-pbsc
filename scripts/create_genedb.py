import gffutils
import argparse

parser = argparse.ArgumentParser(description='Converts GFF to gffutils database used by isoquant')

parser.add_argument('-g', '--gff',dest='gff_f',required=True,type=str)
parser.add_argument('-o', '--db',dest='output_f',required=True,type=str)
args = parser.parse_args()

gff_f=args.gff_f
output_f=args.output_f


def _has_feature_lines(path):
    """Return True if the GTF/GFF has at least one non-comment, non-blank line."""
    try:
        with open(path) as fh:
            for line in fh:
                if line.strip() and not line.startswith('#'):
                    return True
    except FileNotFoundError:
        return False
    return False


# Guard against an empty / feature-less GTF (e.g. when no isoforms were
# quantified, so transcript_models.gtf is empty). gffutils.create_db raises
# EmptyInputError on empty input; instead build a valid but empty database so
# downstream steps that open it with gffutils.FeatureDB do not fail.
if _has_feature_lines(gff_f):
    db = gffutils.create_db(gff_f, dbfn=output_f, force=True, keep_order=True, merge_strategy='merge', sort_attribute_values=True,disable_infer_genes=True,disable_infer_transcripts=True)
else:
    print(f"WARNING: input GTF '{gff_f}' has no feature lines; creating an empty gffutils database '{output_f}'.", flush=True)
    _placeholder = 'chrPLACEHOLDER\tsrc\ttranscript\t1\t2\t.\t+\t.\tgene_id "_ph"; transcript_id "_ph";'
    db = gffutils.create_db(_placeholder, dbfn=output_f, force=True, from_string=True, keep_order=True, merge_strategy='merge', sort_attribute_values=True,disable_infer_genes=True,disable_infer_transcripts=True)
    db.delete(list(db.all_features()))
