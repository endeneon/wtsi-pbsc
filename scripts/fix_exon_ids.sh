#!/usr/bin/env bash
# Prefix novel exon_ids in a GTF with a region/sample tag.
#
# IMPORTANT: keep this script mawk-compatible. The pipeline container
# (wtsi_pbsc_tools.sif) ships only mawk, which does NOT support gawk's
# 3-argument match(s, r, arr). Using it makes awk abort with
# "syntax error at or near ," and emit nothing, which previously emptied every
# chunk's transcript_models.gtf / extended_annotation.gtf. Use the portable
# 2-argument match() (sets RSTART/RLENGTH) + substr() instead.
set -euo pipefail

# Check if correct number of arguments is provided
if [ "$#" -ne 3 ]; then
	echo "Usage: $0 input.gtf output.gtf prefix"
	exit 1
fi

input_gtf="$1"
output_gtf="$2"
prefix="$3"

awk -v prefix="$prefix" '{
    if ($0 ~ /exon_id "[^"]+"/) {
        # Matched span is exon_id "VALUE"; strip the 9-char `exon_id "` prefix
        # and the trailing `"` (10 chars total) to recover VALUE.
        match($0, /exon_id "[^"]+"/);
        exon = substr($0, RSTART + 9, RLENGTH - 10);

        if (exon ~ /^ENSE/) {
            # Skip known exons that start with "ENSE"
            print;
            next;
        }

        if (exon ~ /^[^0-9]/) {
            # Already has a prefix, replace it with given prefix
            gsub(/^.*\./, prefix ".", exon);
        } else {
            # No prefix, add given prefix
            exon = prefix "." exon;
        }

        gsub(/exon_id "[^"]+"/, "exon_id \"" exon "\"");
    }
    print;
}' "$input_gtf" >"$output_gtf"

echo "Modified GTF saved to $output_gtf" >&2
