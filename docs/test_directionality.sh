#!/bin/bash
set -eu
# Empirical validation: does 10x 5' config recover reads that 3' config discards at refine?
SIF=$(realpath /home/szhang37/CAB_workspace/pulled_git_repos/wtsi-pbsc/containers/wtsi_pbsc_tools.sif)
SEG=/research_jude/rgs01_jude/groups/mulligrp/projects/mulligrp_cab/common/MULLI_875886_KINNEX/scKinnex_simple/Segmented_Bam_Prepare/875886_3461363/875886_3461363_segmented.bam
P5=$(realpath /home/szhang37/CAB_workspace/pulled_git_repos/wtsi-pbsc/assets/10x_5kit_primers.fasta)
P3=$(realpath /home/szhang37/CAB_workspace/pulled_git_repos/wtsi-pbsc/assets/10x_3kit_primers.fasta)
N=${1:-30000}
DESIGN5=${2:-16B-12U-13X-T}

cd /tmp/test5p
module load singularity/4.3.5 samtools/1.22.1
export SINGULARITY_BIND="/research_jude,/research,/lustre_scratch,/tmp"

echo "### Subsetting first $N reads from segmented BAM ..."
samtools view -H "$SEG" >hdr.sam
samtools view "$SEG" 2>/dev/null | head -n "$N" >body.sam || true
cat hdr.sam body.sam | samtools view -b -o sub.bam -
echo "subset reads: $(samtools view -c sub.bam)"

run_path() {
	local tag=$1 primers=$2 design=$3
	echo
	echo "========================================================"
	echo "### PATH=$tag  primers=$(basename "$primers")  design=$design"
	echo "========================================================"
	singularity exec "$SIF" lima -j 8 sub.bam "$primers" "${tag}.demux.bam" --isoseq 2>&1 | tail -3 || {
		echo "[lima failed]"
		return
	}
	local demux
	demux=$(ls ${tag}.demux*.bam 2>/dev/null | grep -v 'json\|xml' | head -1)
	echo "lima output bam: $demux  reads=$(samtools view -c "$demux" 2>/dev/null)"
	singularity exec "$SIF" isoseq tag -j 8 "$demux" "${tag}.flt.bam" --design "$design" 2>&1 | tail -2 || {
		echo "[tag failed]"
		return
	}
	echo "tagged reads=$(samtools view -c ${tag}.flt.bam 2>/dev/null)"
	singularity exec "$SIF" isoseq refine "${tag}.flt.bam" "$primers" "${tag}.fltnc.bam" -j 8 --require-polya --min-polya-length 20 2>&1 | tail -2 || {
		echo "[refine failed]"
		return
	}
	echo ">>> $tag FLNC+polyA reads=$(samtools view -c ${tag}.fltnc.bam 2>/dev/null)"
	echo "--- refine summary json ---"
	cat ${tag}.fltnc.filter_summary.report.json 2>/dev/null | tr ',' '\n' | grep -i 'num_reads' || true
}

run_path FIVEPRIME "$P5" "$DESIGN5"
run_path THREEPRIME "$P3" "T-12U-16B"

echo
echo "### DONE"
