# Chat Session Summary

> Adapting the `wtsi-pbsc` (andersonlab/wtsi-pbsc) Nextflow pipeline to run
> already-segmented Kinnex single-cell Iso-Seq BAMs on the St. Jude HPCF (LSF)
> cluster, with a Singularity-based toolchain.

## Session Metadata

- **Date**: 2026-06-23
- **Pipeline repository (canonical path)**: `/research_jude/rgs01_jude/groups/cab/projects/automapper/common/szhang37/pulled_git_repos/wtsi-pbsc`
  - Also reachable via the symlink `/home/szhang37/CAB_workspace/pulled_git_repos/wtsi-pbsc` (same physical directory).
- **Run / working directory (project)**: `/research_jude/rgs01_jude/groups/mulligrp/projects/mulligrp_cab/common/MULLI_875886_KINNEX/CAB_10403_Fusion_detection`
- **Goal**: Make the pipeline accept already-segmented Kinnex BAMs (output of `pbskera split`), run on St. Jude LSF via `-profile stjude_master,singularity`, and provide all required bioinformatics tools through a single Singularity image so the full `full_segmented` + `run_mode: with_quant` path can execute end-to-end.
- **Nextflow**: 25.04.8 (conda env `/research_jude/.../standalone_conda_envs/nextflow_25_04_8`)
- **Singularity**: SingularityCE 4.3.5 (`module load singularity/4.3.5`)

## Update — 2026-06-24 (resource tiers, container modernization, image rebuild)

> Everything below this banner reflects fixes made **after** the original session.
> Where it conflicts with older sections, this banner wins.

### A. Runtime fixes that unblocked the run

- **lima too old → FIXED.** `lima 2.9.0` aborted on every BAM (`std::length_error`, exit 134) because the input is a 2026 Revio dataset (`pb:5.0.0`). Bumped to **`lima=2.13.0`** in `containers/wtsi_pbsc_tools.def`; verified it parses the segmented BAMs with no crash. `REMOVE_PRIMER` then completed 6/6.
- **`TAG_BAM` OOM → FIXED by relabeling (below).** With the original `tag_bam` label (memory `250.MB * attempt`), `isoseq tag` was `TERM_MEMLIMIT`-killed at **every** retry (250→500→750→1000 MB) and the run failed terminally (LSF job `295403780`, exit 1). The "~251 MB" seen earlier was the kill-point, not the true peak. The relabel to `process_medium` (36 GB) resolves it.
- **`DEDUP_READS` `No such variable: tmp_out_bam` → FIXED.** In `modules/barcodes.nf` (~line 121), the `DEDUP_READS` script assigned shell variables (`tmp_out_bam=…`, `out_bam=…`) but then *referenced* them unescaped as `${tmp_out_bam}` / `${out_bam}`. In a double-quoted Nextflow script block those are Groovy interpolations, so Nextflow tried to resolve them as pipeline variables and aborted the run (`No such variable: tmp_out_bam`). Escaped the four uses to `\${tmp_out_bam}` / `\${out_bam}`, leaving the genuine Nextflow interpolations (`${barcode_corrected_chunk_bam}`, `${task.cpus}`, `${b_size}`, `${baseDir}`, `${sample_id}`) and the assignment right-hand sides untouched. Swept every other process `script:`/`stub:` block in `modules/*.nf` + `subworkflows/**/*.nf` for the same pattern — **none found** (all other shell-variable uses, e.g. in `isoquant.nf`, `split_bam.nf`, `customPublish.nf`, were already correctly escaped).

### B. Resource model overhauled → standard nf-core tiers

The pipeline shipped ~30 bespoke per-tool labels (`tag_bam`, `micro_job`, `combine_bams`, …) tuned for a single big machine, many badly under-provisioned for LSF. **All 45 processes** across `modules/*.nf` + `subworkflows/*.nf` were relabeled to the standard nf-core tiers defined in `conf/stjude_master.config`:

| Tier             | cpus | mem   | time | count |
| ---------------- | ---- | ----- | ---- | ----- |
| `process_single` | 1    | 6 GB  | 4 h  | 29    |
| `process_low`    | 6    | 24 GB | 4 h  | 17    |
| `process_medium` | 12   | 36 GB | 8 h  | 7     |
| `process_high`   | 24   | 72 GB | 16 h | 12    |

(All scale `* task.attempt` on retry.) Active-path highlights: `REMOVE_PRIMER`/`REFINE_READS`/`PBMM2`/`BARCODE_CORRECTION`/isoquant first-pass → `process_high`; `TAG_BAM`/`DEDUP_READS` → `process_medium`; samtools/merge/index helpers → `process_low`/`process_single`. `executor='local'` tasks were moved onto LSF.

- **`conf/base.config` fully rewritten (Option A):** the bespoke `withLabel` blocks were removed and replaced with the standard `process_single/low/medium/high` (+`process_long`/`process_high_memory`/`error_*`) tiers, kept consistent with `stjude_master`. `stjude_master` still wins at runtime (loaded via the profile), so its resource config takes priority in all cases.
- **High-memory exception:** `SQANTI3_QC` (orig 150 GB) uses a `withName:SQANTI3_QC` override in `base.config` — `memory = 200.GB * attempt` (doubling per retry) on top of `process_high` cpu/time; the `stjude_master` queue selector routes it to `large_mem` automatically once a task requests >512 GB.
- Validated: `nextflow config -profile stjude_master,singularity` resolves with 0 errors; 0 custom labels remain.

### C. Container modernization — Sanger SIFs → pullable BioContainers

The only hard-wired container paths were dead Sanger `.sif` files. Replaced with Galaxy depot biocontainers (each HEAD-checked `200`), so enabling these branches later won't hard-fail:

| Process(es)                     | New container                                                                |
| ------------------------------- | ---------------------------------------------------------------------------- |
| `CELLSNP`                       | `https://depot.galaxyproject.org/singularity/cellsnp-lite:1.2.3--ha0c3a46_6` |
| `VIREO`                         | `https://depot.galaxyproject.org/singularity/vireosnp:0.5.9--pyh7e72e81_0`   |
| `SQANTI3_QC` / `SQANTI3_FILTER` | `https://depot.galaxyproject.org/singularity/sqanti3:6.0.1--hdfd78af_0`      |

- The SQANTI3 scripts hardcoded the **old** image's interpreter paths (`/conda/miniconda3/envs/sqanti3/bin/python /opt2/sqanti3/6.0.1/.../sqanti3_qc.py`); rewritten to call `sqanti3_qc.py` / `sqanti3_filter.py` directly and `python` for the helper scripts (the bioconda recipe confirms the image bundles `gffutils>=0.13`, `samtools`, `bedtools`). The now-invalid `containerOptions` PATH override was removed.

### D. Default image rebuilt to add bcftools/htslib

`MPILEUP`, `SUBSET_VCF`, and the `match_gt.nf` (gtcheck) steps need `bcftools`/`bgzip`/`tabix`, which the default `wtsi_pbsc_tools.sif` lacked. Added **`bcftools` + `htslib`** to `containers/wtsi_pbsc_tools.def` (`samtools` already present, so `MPILEUP` gets samtools+bcftools together); `%test` extended to assert them. `build_wtsi_pbsc_tools.sh` now installs the new `.sif` **atomically** (temp + `mv`) so a concurrent run never reads a half-written image. Rebuild = LSF job `295410999` — **DONE / verified** (`bcftools 1.23.1`, `bgzip`, `tabix` + all existing tools present; 510 MB).
  - *Not added (flagged):* `bedtools` (used by `find_mapped_*`/smartSplit chunked path) and `sinto` (`SPLIT_BAM_SINTO`) — add later if those branches are enabled.
  - *Version control:* `containers/wtsi_pbsc_tools.def` + `build_wtsi_pbsc_tools.sh` are force-added to git (`git add -f`); the repo's `/containers/*` ignore keeps the built `.sif`, build logs, `.nextflow*`, and `work/` out.

### E. Current run status & next step

- LSF run `295403780` **EXITED** (old-config `TAG_BAM`); `.nf_run_state` is still `running` → **resumable** (cached `REMOVE_PRIMER` 6/6 + `create_genedb_fasta_perChr` 25/25 preserved).
- Rebuild `295410999` **DONE / verified** ✓.
- After the `TAG_BAM` relabel, resumed runs advanced past `TAG_BAM`/`REFINE_READS`/`SUPSET_BAM` and then hit the `DEDUP_READS` `No such variable: tmp_out_bam` Groovy error (see §A) — now **FIXED** in `modules/barcodes.nf`.
- **Next:** resubmit `bsub_wtsi_pbsc_mulligan.sh` **without** `FORCE_FRESH` to resume — the new config (generous `TAG_BAM` etc.) + superset image + the `DEDUP_READS` escaping fix carry it past the failure point.

### F. Git commits (branch `main`, local — not pushed)

- `938dfed` — *Standardize resources, modernize containers, scrub Sanger paths for St. Jude LSF* (19 files: process relabeling, `base.config` rewrite, container biocontainer swaps + SQANTI3 script fixes, `default_params.conf` scrub + `run_mode=null`, `dev/split_chr.py` + `scripts/db_subset.py` cleanups, this doc).
- *follow-up* — version-control the image recipe: force-add `containers/wtsi_pbsc_tools.def` (bcftools/htslib) + `containers/build_wtsi_pbsc_tools.sh` (atomic `.sif` swap), plus this doc update.

## Update — 2026-06-24 (two-pass IsoQuant: split guards, count collection, empty chrM)

> Continues the run past BAM processing into the chunked IsoQuant two-pass
> quantification. This banner supersedes earlier notes where they conflict.

### G. Container: Python 3.12 pin + bedtools/sinto/pybedtools/pyranges

The two-pass region path (`find_mapped_and_unmapped_regions_*`, `acrossSamples_*`,
`suggest_splits_binarySearch`, smartSplit) and `SPLIT_BAM_SINTO` need `bedtools` +
`sinto` plus the Python wrappers `pybedtools` + `pyranges` (used by
`dev/split_chr.py` and the count/GTF helpers). These were added to
`containers/wtsi_pbsc_tools.def`, resolving the two items flagged "not added" in §D.

- **Python pinned to 3.12.** The miniforge base ships 3.13, but `pyranges`/`ncls`
  have no bioconda builds for 3.13, so the mamba solve failed. Pinning
  `python=3.12` (builds exist for every tool) fixes the solve; image now runs
  **Python 3.12.13**.
- `%test` extended to `import ... pybedtools, pyranges`. Rebuilt on the `fakeroot`
  queue; verified — the split/region steps below ran inside the new image.

### H. `dev/split_chr.py` — degenerate / inverted split-interval crash FIXED

`suggest_splits_binarySearch` crashed with pysam
`ValueError: invalid coordinates: start > stop` on chromosomes whose binary search
produced a degenerate split (e.g. `[[0,0],[chrom_size, chrom_size-1]]`). Two guards
added:

- **Guard 1 (source-level, in `split_chr`):** when both halves of a split are empty,
  clamp the split end to `e`, drop empty/inverted sub-intervals, and collapse to a
  single whole-region chunk if everything degenerates.
- **Guard 2 (defense-in-depth, after `merge_splits`):** clamp every interval end to
  `chrom_size-1`, drop `start >= stop` intervals, and fall back to one
  whole-chromosome chunk if none survive.

Result: `suggest_splits_binarySearch` now **24/24** across all chromosomes; no
IndexError, no inverted-interval ValueError. (Earlier `traverse_bintree` nth clamp,
while-loop termination fallback, and `current_iter`→`curr_iter` typo fix remain.)

### I. Two-pass count collection — chunked chromosomes silently dropped FIXED

With the split crash gone, the run reached the two-pass output collection and exposed
a **latent channel bug** (never before reachable). Only `chrM`'s counts reached
`collect_*_counts_as_mtx_perChr` (ran 1 of 1); all 23 chunked chromosomes were
dropped, and `collect_gene_mtx_as_h5ad` then crashed on the empty `chrM` matrix.

- **Root cause** (`subworkflows/isoquant_recipes/isoquant_twopass.nf`,
  `isoquant_twopass_chunked_wf`): the gene/isoform count channels inner-joined the
  first-pass stream keyed `groupKey(chrom, bam_num=6)` with the second-pass stream
  keyed `groupKey(chrom, chunks=16)` via `combine(by:0)`. Nextflow's `GroupKey`
  equality **includes the size hint**, so `groupKey(chrom,6)` never matches
  `groupKey(chrom,16)` → the join is always empty → every chunked chromosome is
  dropped. (chrM survives only because it flows through the separate, non-chunked
  `isoquant_chrM` path.)
- **Fix:** replaced the brittle `combine(by:0)` join for `output_gene_counts_ch` and
  `output_isoform_counts_ch` with `mix` + `groupTuple(by:0)` — gather both per-chrom
  streams and group by plain `chrom`, robust to a variable number of split regions
  per chromosome (which the §H guards now legitimately produce).

### J. `scripts/mtx_to_hda5.py` — empty chrM matrix crash FIXED

`chrM` produces an empty 10x matrix (`genes.tsv`/`barcodes.tsv` 0 bytes,
`matrix.mtx` = `0 0 0`); `scanpy.read_10x_mtx` then raised
`pandas.errors.EmptyDataError: No columns to parse from file`. Added an
`is_empty_mtx()` check so `merge_mtx()` **skips** empty MTX dirs (and writes an empty
AnnData if all are empty) instead of crashing.

### K. Verified outcome (LSF run `295432346`, resume)

After §H–§J, the resumed run advanced through the full two-pass collection:

| Stage                              | Before fix    | After fix      |
| ---------------------------------- | ------------- | -------------- |
| `*_counts_as_mtx_perChr` (per chr) | 1 of 1 (chrM) | **25 of 25** ✔ |
| `collect_isoform_mtx_as_h5ad`      | 0 of 1 ✘      | **1 of 1** ✔   |
| `collect_gene_mtx_as_h5ad`         | 0 of 1 ✘      | **1 of 1** ✔   |

Count matrices for all 25 chromosomes + both gene/isoform H5ADs are produced;
`collect_gtfs` (final collection task) was running at the time of writing.

- **Git:** §G–§J are uncommitted working-tree edits (`containers/wtsi_pbsc_tools.def`,
  `dev/split_chr.py`, `subworkflows/isoquant_recipes/isoquant_twopass.nf`,
  `scripts/mtx_to_hda5.py`).

## Update — 2026-06-24 (collect_gtfs guards + ROOT-CAUSE read-loss diagnosis)

> This banner supersedes earlier notes where they conflict. The pipeline now
> *completes*, but the run produces **empty quantification** — traced here to a
> catastrophic upstream read loss, **not** a pipeline bug.

### L. `collect_gtfs` empty-data guards — pipeline can now COMPLETE

The §K run's final task `collect_gtfs` crashed with `pandas EmptyDataError`
(`scripts/db_subset.py` line 26, `pd.read_csv(all_features.csv)` on a 0-byte file).
This is a **downstream symptom** of the empty-data problem (§M), not a real bug — but
the pipeline should still finish gracefully. Three defensive guards were added (all
`py_compile`-clean + functionally tested end-to-end → `ALL_GUARDS_OK`):

- **`scripts/db_subset.py`** — added `import os, sys`; guard the subset read: if
  `all_features.csv` is 0 bytes (or raises `pd.errors.EmptyDataError`), write an empty
  output GTF and `sys.exit(0)` instead of crashing.
- **`scripts/create_genedb.py`** — added `_has_feature_lines()`; when the input GTF
  has no feature lines, build a **valid but empty** gffutils DB via a placeholder
  feature (`from_string=True`) then `db.delete(all_features())`. (`gffutils.create_db`
  raises `EmptyInputError: No lines parsed` on a truly empty file; the
  placeholder-then-delete trick yields a reopenable 0-feature DB.)
- **`scripts/collect_gtfs.py`** — in `main()`, if `ref_dfs + query_dfs` is empty,
  write an empty output GTF and return (avoids the `pd.concat([])` crash). It already
  skipped individually-empty GTFs via `is_valid_gtf()`.

- **Resubmitted:** LSF job **`295432462`** (resume; `.nf_run_state=running`, the failed
  `collect_gtfs` is not cached → re-runs with the fixed scripts).
- **Git:** these 3 `.py` edits are **uncommitted** working-tree changes.

### M. ROOT CAUSE — catastrophic read loss at `isoseq refine` (THE REAL PROBLEM)

The guards let the pipeline finish, but **every quantification output is empty**
because the data is essentially gone before quantification. Per-stage read counts for
**Sample_875886_3461363** (counted directly with `samtools view -c`, samtools 1.22.1;
cross-checked against PacBio JSON reports):

| Stage                   | Command / file                                                        |       Reads | Δ                     |
| ----------------------- | --------------------------------------------------------------------- | ----------: | --------------------- |
| Segmented input         | `875886_3461363_segmented.bam` (lima input)                           |  91,210,089 | —                     |
| **lima** (5′/3′ demux)  | `lima … 10x_3kit_primers.fasta --isoseq` → `*.5p--3p.bam`             |  89,587,471 | ✅ 98.2 % pass         |
| **isoseq tag**          | `isoseq tag --design T-12U-16B` → `flt.bam` (50.5 GB)                 |  89,586,411 | ✅                     |
| refine → FL             | `isoseq refine … --require-polya --min-polya-length 20`               |  89,586,411 | —                     |
| refine → **FLNC**       | (chimera removal)                                                     | **580,010** | ❌ **−99.35 %**        |
| refine → **FLNC+polyA** | (`--require-polya`)                                                   |     **978** | ❌ **−99.83 %**        |
| correct                 | `isoseq correct --barcodes 3M-february-2018-REVERSE-COMPLEMENTED.txt` |         978 | ✅                     |
| dedup (combined)        | `isoseq groupdedup` ×10 chunks                                        |         436 | ✅ 2.24 reads/UMI      |
| bcstats                 | `isoseq bcstats --method percentile --percentile 98`                  |      419 BC | maxUMI=2, **0 cells** |

Source reports: `fltnc.filter_summary.report.json` → `num_reads_fl=89,586,411`,
`num_reads_flnc=580,010`, `num_reads_flnc_polya=978`. `dedup.json` → 419 barcodes,
431 UMIs, 436 reads, **0 cells**, `fraction_reads_in_cells=0`. `bcstats` `.command.err`:
*"WARNING: no cell barcodes were determined to be cells"* (max UMIs/barcode = 2 ≪
`min_umi=1000`).

**Conclusion:** dedup is healthy (978→436); the read loss is **entirely inside
`isoseq refine`**, via two independent filters. lima passes 98 % with proper 5′/3′
pairs, so the primers/orientation at the primer level are fine — the **read content
itself** is the problem:

1. **~99.35 % chimeric** → reads contain *internal* primers, i.e. behave like
   un-segmented concatemers → suspected **skera segmentation / MAS-adapter mismatch**
   when the `*_segmented.bam` was produced.
2. **~99.83 % lack a poly-A tail** → for 10x **3′** chemistry every molecule should
   carry poly-A; near-total absence suggests the library may actually be **10x 5′
   chemistry** (no internal poly-A) or otherwise mis-specified.

lima summary (`*.lima.summary`): input 91,210,089; passed 89,587,471; below thresholds
1,622,618 (5p--5p 258,830; 3p--3p 169,685; below-min-end-score 1,390,981;
below-min-ref-span 462,772). Pipeline commands captured verbatim:

```text
lima  -j 24 875886_3461363_segmented.bam .../10x_3kit_primers.fasta Sample_875886_3461363.bam --isoseq
isoseq tag -j 12 Sample_875886_3461363.5p--3p.bam Sample_875886_3461363.flt.bam --design T-12U-16B
isoseq refine Sample_875886_3461363.flt.bam .../10x_3kit_primers.fasta Sample_875886_3461363.fltnc.bam -j 24 --require-polya --min-polya-length 20
isoseq correct -j 24 --method percentile --percentile 98 --barcodes 3M-february-2018-REVERSE-COMPLEMENTED.txt fltnc.bam corrected.bam
```

Key work dirs (run `wtsi-pbsc.2026-06-24.10:11:55`, Sample_875886_3461363):
`lima dc/a72d2dee…`, `tag 00/fbf68387…`, `refine fd/b23c2a7a…`, `correct 1b/ae211798…`,
`bcstats 52/4bca5b8f…`, `dedup b6/18651980…`
(under `/lustre_scratch/user_scratch/szhang37/nextflow_work/wtsi-pbsc.2026-06-24.10:11:55/`).

### N. HANDOFF — read-content investigation plan (resumable)

> If interrupted, resume from here. Goal: identify (1) which internal primer set is
> actually present and (2) whether this is 10x 5′ (no poly-A) vs 3′ chemistry.

**Inputs / fixtures**

- 50.5 GB tag output (FL reads): `…/00/fbf683873e3c809c7c36a6c24f58b6/Sample_875886_3461363.flt.bam`
- lima demux (proper 5p--3p): `…/dc/a72d2dee7282a6fbc3111f6785f161/`
- Pipeline primers FASTA: `/research_jude/.../scKinnex/data/10x_3kit_primers.fasta`
- Barcode whitelist: `3M-february-2018-REVERSE-COMPLEMENTED.txt`
- Tools: `module load samtools/1.22.1`; container `containers/wtsi_pbsc_tools.sif`.

**TODO (1) — chimeric reads / internal primers**

- [ ] Pull ~20–50 reads from `flt.bam` → FASTA (`samtools view … | head`).
- [ ] Print the pipeline primer seqs from `10x_3kit_primers.fasta`.
- [ ] grep each read for *internal* occurrences of the 5′/3′ primer (and revcomp).
- [ ] Search online for candidate internal adapter sets — **MAS-seq / Kinnex array
      adapters** (skera), 10x TSO / partial Read1 / Read2 — and match.
- [ ] Decide: segmentation wrong (concatemers remain) vs internal primers from a
      different kit.

**TODO (2) — 5′ vs 3′ chemistry / poly-A**

- [ ] Quantify poly-A: count `flt.bam` sample reads with a ≥20 nt 3′ A-run.
- [ ] Inspect read structure vs `--design T-12U-16B` (T-cDNA, 12 nt UMI, 16 nt BC).
- [ ] Compare `10x_3kit_primers.fasta` to the **10x 5′** primer/TSO set.
- [ ] If 5′: refine must run **without** `--require-polya`, and the design/primers
      switch to the 5′ kit.

**Findings (RESOLVED — 2026-06-24):**

- **Chemistry: confirmed 10x Genomics 5′ v3 (GEM-X 5′), not 3′.** The pipeline was
  configured for the 3′ kit, which is why `isoseq refine --require-polya` discarded
  ~99.8 % of reads.
- **(1) chimeric / internal primers:** NOT a real chimera/internal-primer problem.
  Read-structure analysis of a 1,000-read sample (`flt.bam`) showed **zero** internal
  10x primer hits. 86 % of reads carried a constant 13 bp tail `CCCATATAAGAAA` =
  revcomp of `TTTCTTATATGGG`, the 10x **5′ TSO** (the `13X` clipped by the 5′ design).
  Its appearance reverse-complemented at the 3′ end shows the reads were simply
  **flipped** because lima was given the 3′ primers (≈ revcomp of the 5′ primers).
  FLNC chimera rate with the correct 5′ primers is only **0.36 %** (normal).
- **(2) 5′ vs 3′ / poly-A:** Leading T-run (5′) median 28, **987/1000 ≥ 20** (poly-A
  present, as poly-T on the flipped strand); trailing A-run (3′) max 7, **0/1000 ≥ 20**.
  So poly-A IS present — the earlier note "5′ ⇒ drop `--require-polya`" was wrong.
  With the correct 5′ primers + design the read orients 5′→3′ with poly-A at the 3′
  end, so **`--require-polya` is KEPT**.

**Empirical validation (30,000-read subset of `875886_3461363_segmented.bam`):**

| Config                                                            | lima pass | tagged | FLNC   | **FLNC + polyA**    |
| ----------------------------------------------------------------- | --------- | ------ | ------ | ------------------- |
| **5′ (new):** `10x_5kit_primers.fasta` + `--design 16B-12U-13X-T` | 29,791    | 29,790 | 29,682 | **29,515 (98.4 %)** |
| **3′ (old):** `10x_3kit_primers.fasta` + `--design T-12U-16B`     | 29,454    | 29,454 | —      | **0 (0 %)**         |

Barcode orientation check (5′ tagged `XC` tags vs whitelist, 3,839 sampled):
**FORWARD = 3,568 (93 %)** vs revcomp = 1 (0.03 %) ⇒ use the 5′ whitelist
**forward / not reverse-complemented**.

**Fix applied (4 changes):**

1. `params.tenx_primers` → `assets/10x_5kit_primers.fasta`
   (`>5p CTACACGACGCTCTTCCGATCT`, `>3p GTACTCTGCGTTGATACCACTGCTT`).
2. New `params.tenx_design` (parameterizes the previously hardcoded
   `isoseq tag --design` in `modules/fltnc.nf`); repo default stays `T-12U-16B`
   (3′), run `params.yaml` sets **`16B-12U-13X-T`** (5′: 16 bp BC, 12 bp UMI, 13 bp TSO).
3. `params.threeprime_whitelist` → `assets/3M-5pgex-jan-2023.txt`
   (GEM-X 5′ v3, 3,686,400 barcodes, **forward** orientation; decompressed from
   Cell Ranger 9.0.1 `lib/python/cellranger/barcodes/3M-5pgex-jan-2023.txt.gz`).
4. `isoseq refine --require-polya` **kept** (5′ data has poly-A once oriented).

**Resubmitted with 5′ config — 2026-06-24:**

- Verified params.yaml is fully wired: all three asset files exist at the canonical
  `/research_jude/.../wtsi-pbsc/assets/` path, `modules/fltnc.nf` consumes
  `${params.tenx_design}`, and `conf/default_params.conf` defines the `T-12U-16B`
  default.
- Prior run state was `completed` (the empty-output 3′ run), so the submit script
  started a **fresh** run (new `/lustre_scratch/.../wtsi-pbsc.<timestamp>` work dir)
  rather than resuming.
- Submitted via `bsub -J "run_bsub_nextflow_wtsi-pbsc_mulligan.$(date +%F.%T)" < bsub_wtsi_pbsc_mulligan.sh`
  → **LSF job `295432635`** (queue `priority`), RUNNING on `noderome111`.
- Expectation: refine should now retain ~98 % of reads (vs ~0 %), so barcode
  correction / dedup / bcstats should produce real cells. **Next check:** the per-sample
  `fltnc.filter_summary.report.json` (`num_reads_flnc_polya`) and the bcstats cell counts.

## Update — 2026-06-25 (`fix_exon_ids.sh` mawk crash silently emptied every model GTF)

> The 5′ config run advanced all the way through read processing + two-pass
> IsoQuant quantification, then died in the final `collect_gtfs` step. Root-caused
> to a portability bug, **not** a data problem. This banner supersedes earlier
> notes where they conflict.

### O. Failure — `db_subset.py` FeatureNotFoundError

LSF run **`295432635`** (fresh, 5′ config) EXITED 1 at the `collect_gtfs` process
(work dir `c5/95e7d2be0c9a145884092408f514ff`):

```text
File ".../scripts/db_subset.py", line 51, in <module>
    transcript = db[isoform]
gffutils.exceptions.FeatureNotFoundError: transcript1.chr10_102503943_112944799.nnic
```

`db_subset.py` iterates the feature IDs in `all_features.csv` (built from the
IsoQuant isoform-count TSVs — **325,774** IDs, of which **264,571 are novel,
non-ENST** transcripts) and looks each up in `extended_annotation.gtf.db`. The
first novel ID isn't in the DB, so it raises.

### P. ROOT CAUSE — gawk-only `match()` in `fix_exon_ids.sh` + mawk container

The two rename processes in `modules/isoquant.nf` (`replace_novel_names` for the
chunked path, `replace_novel_names_firsPass_singlenovelname` for the per-sample
chrM path) call `scripts/fix_exon_ids.sh` to prefix novel `exon_id`s. That script
used gawk's **3-argument** `match($0, /re/, arr)` — a GNU-awk-only extension. The
container (`wtsi_pbsc_tools.sif`, miniforge base) ships **only mawk, no gawk**, so
awk aborted with `syntax error at or near ,` and wrote **nothing**. The rename
script then blindly ran `rm orig; mv empty-tmp orig`, replacing the real GTF with
an empty one. Because `fix_exon_ids.sh` ended with an always-`0` `echo`, `set -e`
never fired → **silent** data loss.

Verified the damage is systemic:

| Check                                                   | Result                                   |
| ------------------------------------------------------- | ---------------------------------------- |
| chunk `*.transcript_models.gtf` empty (0 bytes)         | **368 / 368** ✘                          |
| novel `transcript[0-9]+\.` in `extended_annotation.gtf` | **0** (3.24 M ref lines only) ✘          |
| `.command.err` of every rename task                     | `awk: line 3: syntax error at or near ,` |

So every novel transcript that has counts was missing from the collected GTF DB.

### Q. Fix (3 edits — validated in-container)

1. **`scripts/fix_exon_ids.sh`** — rewrote the awk to portable **2-arg
   `match()` + `substr()`** (`exon = substr($0, RSTART + 9, RLENGTH - 10)`, since
   the matched span is `exon_id "VALUE"`), added `set -euo pipefail`, and sent the
   success message to **stderr**. Logic is otherwise byte-identical to the old
   gawk version.
2. **Both rename processes** (`modules/isoquant.nf`) — added a guard right after
   the `fix_exon_ids.sh` call: if the source GTF is non-empty but the produced
   `.tmp` is empty, `echo ERROR … >&2; exit 1` **before** the destructive
   `rm; mv`. This (a) permanently prevents the silent-emptying footgun and
   (b) changes the task hash so `-resume` actually **re-runs** the cached rename
   tasks — necessary because `fix_exon_ids.sh` is invoked by absolute path and its
   *content* is **not** part of Nextflow's resume hash.

**Validation (container `wtsi_pbsc_tools.sif`):**

- Real source GTF (`chr10_102503943_112944799.transcript_models.gtf`, 3,747 lines):
  fixed script → **3,747 lines out**, no awk error, exon_ids prefixed
  (`"1"` → `"chr10_102503943_112944799.1"`).
- Synthetic 3-line test (`PFX`): `ENSE00001.1` → unchanged (known exon skipped);
  `5` → `PFX.5` (numeric, add prefix); `transcript1.foo.nnic` → `PFX.nnic`
  (re-prefix). All three branches match the original gawk behaviour.

### R. Recovery

`-resume` keeps the expensive isoseq + IsoQuant quantification cached; only the
rename + collect steps re-run (their hashes changed via §Q.2). Resubmit **without**
`FORCE_FRESH`:

```bash
bsub -J "run_bsub_nextflow_wtsi-pbsc_mulligan.$(date +%F.%T)" < bsub_wtsi_pbsc_mulligan.sh
```

- **Git:** §Q edits are **uncommitted** working-tree changes
  (`scripts/fix_exon_ids.sh`, `modules/isoquant.nf`).

## Update — 2026-06-25 (bigWig coverage tracks + work-dir cache preservation)

> Two additions while the `fix_exon_ids.sh` recovery run was in flight: a new
> bigWig-generation step off the final BAMs, and a temporary disabling of the
> post-run work-dir cleanup so cached intermediates can be reused later.

### S. New `BAM_TO_BIGWIG` process — genome-browser coverage tracks

The pipeline previously produced **no** coverage/bigWig output. Added
[modules/bigwig.nf](../modules/bigwig.nf) (`process BAM_TO_BIGWIG`) and wired it
into both the `full` and `full_segmented` entry workflows in
[isoseq2.nf](../isoseq2.nf).

| Aspect        | Choice                                                                                                                                                                           |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Input         | `BAM_PROCESSING(_SEGMENTED).out.mapped_reads` = `${sample_id}.mapped.realcells_only.bam` (+ `.bai`) — the final genome-aligned, dedup, real-cells-only BAM from `COMBINE_MUPPED` |
| Tool          | deeptools `bamCoverage`                                                                                                                                                          |
| Normalisation | `--normalizeUsing RPKM`                                                                                                                                                          |
| Bin size      | `--binSize 20`                                                                                                                                                                   |
| Output        | `${sample_id}.mapped.realcells_only.rpkm.bw` → `results/bigwig/`                                                                                                                 |
| Container     | `https://depot.galaxyproject.org/singularity/deeptools:3.5.6--pyhdfd78af_0` (per-process override)                                                                               |
| Label         | `process_medium`                                                                                                                                                                 |

- The default container (`wtsi_pbsc_tools.sif`) ships only samtools + bedtools
  (no `bedGraphToBigWig`/deeptools), so the process pulls a dedicated deeptools
  image — the same per-process container pattern SQANTI3 uses. `bamCoverage`
  reads chrom sizes from the BAM header, so no external `hg38.chrom.sizes` is
  needed. First use pulls the image from the Galaxy depot (config allows a 3 h
  `pullTimeout`).
- **Resume note:** because `mapped_reads`/`COMBINE_MUPPED` is already cached, a
  resumed run runs only the cheap new bigWig tasks — no re-mapping/re-quant.

### T. Temporarily disabled post-run cleanup (preserve cache for future modules)

To allow adding more modules later and reusing cached intermediates via
`-resume` (instead of re-running the whole pipeline), the run-completion cleanup
was disabled in three places, all tagged `TEMP(2026-06-25)`:

1. **`conf/stjude_master.config`** — `cleanup = true` → **`cleanup = false`**.
   This was the critical one: Nextflow's `cleanup = true` **physically deletes
   the entire work dir on successful completion**, which would destroy the cache.
2. **`bsub_wtsi_pbsc_mulligan.sh` resume guard** — now accepts `completed` as
   well as `running` (`=~ ^(running|completed)$`), so a *successful* run still
   auto-`-resume`s the same work dir instead of starting fresh.
3. **`bsub_wtsi_pbsc_mulligan.sh` success branch** — no longer `rm -f`s
   `.nf_workdir`, so the work-dir pointer survives a successful run.

> **Revert** all three back (`cleanup = true`, `== "running"`, restore the `rm`)
> once the extra modules are in and the cache is no longer needed.

### U. Relaunched the recovery run under `cleanup = false`

The in-flight run `295432635`→`295438755` had already read `cleanup = true` at
launch, so its work dir would still be wiped on success. To guarantee cache
preservation, killed `295438755` (+ one orphaned child task) and resubmitted as
**`295439599`**. Because no success-cleanup had occurred, the existing work dir
(`…/wtsi-pbsc.2026-06-24.21:02:59`) was intact, so the new run `-resume`s from it
— now with `cleanup = false` and the `BAM_TO_BIGWIG` step in the DAG.

- **Git:** §S–T edits are **uncommitted** working-tree changes
  (`modules/bigwig.nf`, `isoseq2.nf`, `conf/stjude_master.config`,
  `bsub_wtsi_pbsc_mulligan.sh`).

## Update — 2026-06-25 (GTF collection dropped regions past the sample count — FIXED + committed)

> After the §Q `fix_exon_ids.sh` recovery, the rename step produced valid novel
> GTFs, but `collect_gtfs`/`db_subset.py` *still* failed with
> `FeatureNotFoundError` — first on `chrY`, then (after a partial fix) on `chr10`.
> Root-caused to an inherited `groupKey` size hint capping the GTF-collection
> channels. This banner supersedes earlier notes where they conflict.

### V. Failure — `db_subset.py` FeatureNotFoundError (chrY, then chr10)

The resumed run EXITED 1 at `collect_gtfs` with
`gffutils.exceptions.FeatureNotFoundError`. `db_subset.py` iterates every feature
ID in `all_features.csv` (built from the IsoQuant isoform counts) and looks it up
in `extended_annotation.gtf.db`; the lookup raised because the collected GTF was
**missing whole regions** that the counts still referenced:

- A first attempt (dropping the `groupKey(chrom, chunks)` size hint → plain
  `chrom`) fixed **chrY** but the run then failed on
  `transcript1.chr10_102503943_112944799.nnic` — chr10's **region #13**.
- Diagnosis: the GTF FOFN held only **288** chunk GTFs (exactly **12 per chrom**,
  chrY **6**), while `all_features.csv` (counts) carried the full set. Every
  chromosome was capped at its **sample count**, silently dropping all regions
  beyond it (e.g. `chr10_102503943_112944799`, which exists upstream as a valid
  3,747-line renamed GTF but never reached `collect_gtfs`).

### W. ROOT CAUSE — inherited `groupKey(chrom, sample_size)` on the GTF channels

The `chrom` value emitted by `run_isoquant_chunked` / `replace_novel_names` is **not
a plain string** — it is a `groupKey(chrom, sample_size)` object inherited from the
upstream second-pass grouping (the `groupKey(chrom, chrom_sample_size)` keys built in
`isoquant_twopass_chunked_wf`). `GroupKey` carries a size hint, and
`groupTuple(by:0)` **honours that hint**, emitting each chromosome's group as soon as
`sample_size` items (≈12; chrY 6) arrive — so any chromosome split into **more**
regions than there are samples loses every region past the cap.

The **counts** channels (`output_isoform_counts_ch` / `output_gene_counts_ch`) escape
this because they `.mix()` in the first-pass stream, which is keyed by a **plain
String** `chrom`; the mixed plain key defeats the early-emit cap, so `groupTuple`
waits for channel completion and keeps all regions. That asymmetry is exactly why the
counts were complete but the GTFs were truncated → `db_subset.py` mismatch.

### X. Fix (1 edit — verified end-to-end)

`subworkflows/isoquant_recipes/isoquant_twopass.nf` — coerce the key to a plain
`String` (`"${chrom}".toString()`) when building **both** GTF-collection channels
(`output_existing_gtf_ch`, `output_extended_gtf_ch`), stripping the inherited
`groupKey` size hint so `groupTuple(by:0)` collects **all** regions per chromosome.

**Verified outcome (LSF run `295440400`, resume → DONE):**

| Check                              | Before fix             | After fix                         |
| ---------------------------------- | ---------------------- | --------------------------------- |
| GTF FOFN entries                   | 288 (12/chrom; chrY 6) | **385** (16/chrom; chrY 11) ✔     |
| `chr10_102503943_112944799` in GTF | absent ✘               | **present** (3,658 lines) ✔       |
| `collect_gtfs` exitcode            | 1 (FeatureNotFound)    | **0**, all 4 "Finished" markers ✔ |
| Pipeline                           | EXIT                   | **completed successfully** ✔      |

- **Git:** committed as **`d1340f6`** on `main`
  (`subworkflows/isoquant_recipes/isoquant_twopass.nf` only).
- **Latent (not yet fixed):** the read channels (`output_corrected_reads_ch`,
  `output_assignment_reads_ch`, `output_transcriptmodel_reads_ch`) still re-key with
  `groupKey(chrom, chunks)` — same class of defect, but they feed deconvolution
  (currently OFF). The §T `cleanup = false` + bsub resume-guard edits remain TEMP and
  should be reverted once the modules are finalized.

---

## Tasks Completed

1. **Input-compatibility assessment**
   - Input BAMs listed in `assets/Kinnex_875886_samplesheet.csv` are **already segmented** (named `*_segmented.bam`, i.e. the output of `pbskera split`).
   - The standard `BAM_PROCESSING` workflow begins with `SPLIT_READS` (skera), so feeding segmented BAMs there would double-segment / fail.
   - The original samplesheet columns (`sample,bam,pbi`) do **not** match the pipeline's expected header (`sample_id,long_read_path,nr_samples_multiplexed`).
   - Outcome: decided to add a new entry that starts **after** skera (at `REMOVE_PRIMER`).

2. **New subworkflow `BAM_PROCESSING_SEGMENTED`**
   - File: `subworkflows/bam_processing/bam_processing.nf`
   - Mirrors `BAM_PROCESSING` but **skips `SPLIT_READS`** and feeds segmented BAMs directly into `REMOVE_PRIMER` → `TAG_BAM` → `REFINE_READS` → `BARCODE_CORRECTION` → barcode chunking → `DEDUP_READS` → `COMBINE_DEDUPS` → `BAM_STATS` → `PBMM2` → `COMBINE_MUPPED*`.
   - Emits `mapped_reads`, `supplementary_reads`, `nosupplementary_reads` (same shape as `BAM_PROCESSING`).

3. **New workflow entry points in `isoseq2.nf`**
   - Added `BAM_PROCESSING_SEGMENTED` to the include from `bam_processing.nf`.
   - Added `workflow bam_processing_segmented_wf` (BAM processing only).
   - Added `workflow full_segmented` (mirrors `full`: BAM processing → optional deconvolution → optional IsoQuant when `run_mode == 'with_quant'`).

4. **Correctly-formatted samplesheet**
   - File: `<project>/assets/wtsi_pbsc_segmented_samplesheet.csv`
   - Header `sample_id,long_read_path,nr_samples_multiplexed`; six samples; `nr_samples_multiplexed = 1` (single donor; deconvolution path skipped).

5. **`params.yaml`**
   - File: `<project>/assets/params.yaml`
   - Populated from the bsub reference + pipeline defaults; user subsequently localized paths to St. Jude (`/research/...` genome/gtf/primers, local SQANTI3 dir, `nf_basedir` → local checkout, deconvolution toggles set to `FALSE`).
   - `run_mode: pre_quant` currently set (switch to `with_quant` for quantification).

6. **St. Jude profile integration**
   - File: `nextflow.config` — added a `profiles {}` block registering `stjude_master` (via `includeConfig 'conf/stjude_master.config'`) and a minimal `singularity` profile, so `-profile stjude_master,singularity` works.

7. **Singularity bind mounts**
   - File: `conf/stjude_master.config` — `runOptions` now binds **both** `/research` and `/research_jude` (plus `/lustre_scratch`, `/home`, `$TMPDIR`). On HPCF, `/research/...` paths are symlinks onto `/research_jude/rgs01_jude/...`; binding both avoids LSF/Singularity symlink-resolution failures.

8. **Resume / cleanup analysis** (no code change required)
   - `cleanup = true` in `conf/stjude_master.config` only triggers on **successful** completion; interrupted/failed runs keep their work dir and remain resumable.
   - The bsub script wires `-w "${NF_WORK_DIR}"` + `${RESUME_FLAG}` and a `.nf_run_state` / `.nf_workdir` mechanism for auto-resume.

9. **`workdir` param clarification** (no code change)
   - `params.workdir` (`workdir: "./work"`) is **inert** — no `.nf` reads it. Nextflow's real work dir is set only by `-w` / `NXF_WORK` / `workDir`. It cannot override `-w /lustre_scratch/...`.

10. **Container / tool-availability analysis**
    - The pipeline declares containers in only two places, both **non-existent Sanger `.sif` paths**: `withLabel:sqanti3`/`sqanti3_filter` (`conf/base.config`) and `CELLSNP`/`DECONVOLUTION` (`modules/deconvolution.nf`).
    - All other processes have **no container** and run natively; the active env contains only `nextflow` (no `isoseq`, `lima`, `pbmm2`, `pbskera`, `samtools`, `isoquant`).
    - Tool versions confirmed from the sibling `nf-core/isoseq` pipeline: **lima 2.9.0**, **isoseq 4.0.0**, **samtools 1.20**.
    - BioContainers facts: PacBio tool images are **single static binaries with no `samtools`**; **no prebuilt mulled** `isoseq+samtools` / `pbmm2+samtools` images exist; the **IsoQuant** image bundles `samtools`/`pysam`/`gffutils`/`pandas`/`scipy` but **not** `anndata`/`scanpy`.
    - Several wtsi-pbsc processes call a PacBio tool **and** `samtools`/python in one script (`REFINE_READS`, `BARCODE_CORRECTION`, `DEDUP_READS`, `PBMM2`, `BAM_STATS`, h5ad steps) → a single combined image is required.

11. **Chosen solution — one combined Singularity image (Option 2)** and build infrastructure
    - Verified local build capability: `--fakeroot` on the login node fails (no `/etc/subuid` mapping), `proot` missing, no remote builder; **but an LSF queue named `fakeroot` exists and is Open:Active**.
    - Created `containers/wtsi_pbsc_tools.def` (combined image) and `containers/build_wtsi_pbsc_tools.sh` (`#BSUB -q fakeroot`).
    - First build (job `295393855`) **failed**: `singularity build --fakeroot` runs in a user namespace mapped to a sub-UID that is neither the owner nor in the owning group, so it hits "other" permissions and could not traverse the root-owned restrictive parents of `/research_jude` (`.../common/automapper` is `dr-xr-x---`) to read the `.def`. `/lustre_scratch/user_scratch/$USER` has the same problem (`drwxrwx--- root:root`). Only `/tmp` is world-traversable (`drwxrwxrwt`, 60 GB free).
    - **Fixed** `build_wtsi_pbsc_tools.sh` to stage the def, `SINGULARITY_TMPDIR`/`CACHEDIR`, and the output `.sif` under node-local `/tmp/wtsi_build.<jobid>/`, then copy the finished image back to `/research_jude/.../containers/` as the real user. Resubmitted as **job `295400359`**.
    - Wired a **global `process.container`** in `conf/stjude_master.config` pointing at `${projectDir}/containers/wtsi_pbsc_tools.sif`. Validated with `nextflow config` that it resolves for all processes (sqanti3/deconvolution keep their own overrides).

## Key Decisions & Rationale

- **Start segmented input at `REMOVE_PRIMER`**: the BAMs are post-skera, so re-running `pbskera split` is wrong; a dedicated `BAM_PROCESSING_SEGMENTED` workflow cleanly skips it.
- **Keep pipeline column convention** (`sample_id,long_read_path,nr_samples_multiplexed`) for the new samplesheet instead of the original `sample,bam,pbi`, for consistency with all other entries.
- **Bind both `/research` and `/research_jude`**: data is reachable via either prefix; binding both avoids container symlink-resolution issues under LSF.
- **Option 2 (single combined image)** over Seqera Wave or per-tool biocontainers, because: PacBio biocontainers lack `samtools`, no mulled combos exist, and several processes mix tools in one script. A single image is offline-robust at runtime (no Wave network dependency).
- **Global `process.container` instead of per-process directives**: with exactly one image, a single default is DRY and equivalent; per-process stamping across ~20 modules would be redundant.
- **Tool version pins**: `isoseq=4.3.0`, `lima=2.9.0`, `pbmm2=1.17.0`, `pbskera=1.4.0`, `isoquant=3.13.1`, plus `samtools`/`scanpy`/`anndata`/`gffutils` — sourced from the sibling nf-core/isoseq pipeline and current BioContainers tags.

## Code Changes

### 1. `subworkflows/bam_processing/bam_processing.nf` — new `BAM_PROCESSING_SEGMENTED`

```groovy
workflow BAM_PROCESSING_SEGMENTED {
    main:
      /// Obtaining (sample_id, segmented_bam) tuples from the input_samples.csv file.
      /// Input BAMs are ALREADY segmented (i.e. the output of `pbskera split`), so the
      /// SPLIT_READS (skera) step is skipped and processing starts from REMOVE_PRIMER (lima).
      Channel
        .fromPath(params.input_samples_path)
        .splitCsv(sep: ',', header: true)
        .map { it -> [it.sample_id, file(it.long_read_path)] }
        .set { segmented_bam_tuples }

      REMOVE_PRIMER(segmented_bam_tuples, params.tenx_primers)
      TAG_BAM(REMOVE_PRIMER.out.removed_primer_tuple)
      REFINE_READS(TAG_BAM.out.tagged_tuple, params.tenx_primers, params.min_polya_length)
      BARCODE_CORRECTION(REFINE_READS.out.refined_reads, params.threeprime_whitelist, params.barcode_correction_method, params.barcode_correction_percentile)
      GET_BARCODES(BARCODE_CORRECTION.out.barcode_corrected_tuple, params.number_of_chunks)
      barcode_channel=GET_BARCODES.out.barcodes_tuple.transpose()
      combined_ch = BARCODE_CORRECTION.out.barcode_corrected_tuple.combine(barcode_channel, by: 0)
      SUPSET_BAM(combined_ch)
      DEDUP_READS(SUPSET_BAM.out.chunk_tuple, params.dedup_batch_size)
      deduped_chunks_ch = DEDUP_READS.out.dedup_tuple.groupTuple(size: params.number_of_chunks)
      COMBINE_DEDUPS(deduped_chunks_ch)
      BAM_STATS(COMBINE_DEDUPS.out.dedup_tuple, params.barcode_correction_method, params.barcode_correction_percentile, params.min_umi_barcodes ?: null)

      if (params.min_umi_barcodes) {
          pbmm2_ch = DEDUP_READS.out.dedup_tuple
              .combine(BAM_STATS.out.min_umi_barcodes_txt, by: 0)
              .multiMap { sid, bam, bc ->
                  bam_tuple: tuple(sid, bam)
                  barcodes:  bc
              }
          PBMM2(pbmm2_ch.bam_tuple, params.genome_fasta_f, pbmm2_ch.barcodes)
      } else {
          PBMM2(DEDUP_READS.out.dedup_tuple, params.genome_fasta_f, [])
      }

      mapped_chunks_ch=PBMM2.out.map_tuple.groupTuple(size: params.number_of_chunks)
      COMBINE_MUPPED(mapped_chunks_ch)
      supplementary_chunks_ch = PBMM2.out.supplementary_tuple.groupTuple(size: params.number_of_chunks)
      COMBINE_MUPPED_SUPPLEMENTARY(supplementary_chunks_ch)
      nosupplementary_chunks_ch = PBMM2.out.nosupplementary_tuple.groupTuple(size: params.number_of_chunks)
      COMBINE_MUPPED_NOSUPPLEMENTARY(nosupplementary_chunks_ch)
    emit:
    mapped_reads = COMBINE_MUPPED.out.combined_bam_tuple
    supplementary_reads = COMBINE_MUPPED_SUPPLEMENTARY.out.combined_supplementary_tuple
    nosupplementary_reads = COMBINE_MUPPED_NOSUPPLEMENTARY.out.combined_nosupplementary_tuple
}
```

### 2. `isoseq2.nf` — include + entry workflows

```groovy
include {BAM_PROCESSING; BAM_PROCESSING_SEGMENTED; MAPPING_ONLY; DEDUP_ONLY} from './subworkflows/bam_processing/bam_processing.nf'

workflow full_segmented{
  // Same as `full` but input BAMs are already segmented (skera SPLIT_READS skipped).
  BAM_PROCESSING_SEGMENTED()
  mapped_reads=BAM_PROCESSING_SEGMENTED.out.mapped_reads
  if (params.run_deconvolution == 'TRUE') {
    DECONVOLUTION(mapped_reads)
    mapped_reads=DECONVOLUTION.out.fullBam_ch
  }
  mapped_reads.view()
  if (params.run_mode == 'with_quant'){
    ISOQUANT_TWOPASS_PROCESS(mapped_reads)
  }
}

workflow bam_processing_segmented_wf {
    // Independent entry for already-segmented input BAMs (skips skera SPLIT_READS)
    BAM_PROCESSING_SEGMENTED()
}
```

### 3. `nextflow.config` — profiles block

```groovy
profiles {
    // St. Jude HPCF (LSF) execution + Singularity bind-mount settings.
    stjude_master {
        includeConfig 'conf/stjude_master.config'
    }
    // Minimal Singularity enable so `-profile stjude_master,singularity` also works.
    singularity {
        singularity.enabled = true
    }
}
```

### 4. `conf/stjude_master.config` — bind mounts + global container

```groovy
singularity {
    envWhitelist = "SINGULARITY_TMPDIR,TMPDIR,CUDA_VISIBLE_DEVICES"
    enabled      = true
    autoMounts   = false
    // Bind BOTH /research and /research_jude (HPCF symlink resolution safety).
    runOptions   = '-B /lustre_scratch -B /research -B /research_jude -B /home -B "$TMPDIR"'
    pullTimeout  = "3.h"
}
```

```groovy
process {
    // ...
    executor       = 'lsf'

    // ── Default container ────────────────────────────────────────────────────
    // Single combined image with the full PacBio Iso-Seq + IsoQuant toolchain.
    // Built on the `fakeroot` LSF queue from containers/wtsi_pbsc_tools.def.
    container      = "${projectDir}/containers/wtsi_pbsc_tools.sif"
    // ...
}
```

### 5. `containers/wtsi_pbsc_tools.def` — combined image definition

```singularity
Bootstrap: docker
From: condaforge/miniforge3:latest

%post
    set -eux
    export MAMBA_NO_BANNER=1
    mamba install -y -n base -c conda-forge -c bioconda \
        isoseq=4.3.0 \
        lima=2.9.0 \
        pbmm2=1.17.0 \
        pbskera=1.4.0 \
        isoquant=3.13.1 \
        samtools \
        scanpy \
        anndata \
        gffutils
    mamba clean -afy

%environment
    export PATH=/opt/conda/bin:$PATH
    export LC_ALL=C.UTF-8
    export LANG=C.UTF-8

%runscript
    exec "$@"

%test
    set -e
    for t in isoseq lima pbmm2 pbskera samtools; do command -v "$t"; done
    command -v isoquant.py || command -v isoquant
    python -c "import scanpy, anndata, gffutils, pandas, scipy, numpy, pysam; print('python deps OK')"
```

### 6. `containers/build_wtsi_pbsc_tools.sh` — fakeroot build job

```bash
#!/bin/bash
#BSUB -q fakeroot
#BSUB -n 4
#BSUB -R "rusage[mem=32G]"
#BSUB -J build_wtsi_pbsc_tools
#BSUB -o build_wtsi_pbsc_tools.out
#BSUB -e build_wtsi_pbsc_tools.err
set -euo pipefail
module load singularity/4.3.5

DEF_DIR="/research_jude/rgs01_jude/groups/cab/projects/automapper/common/szhang37/pulled_git_repos/wtsi-pbsc/containers"
DEF="${DEF_DIR}/wtsi_pbsc_tools.def"
SIF="${DEF_DIR}/wtsi_pbsc_tools.sif"

# NOTE: fakeroot maps to a sub-UID that only has "other" permissions on host
# files, and cannot traverse the root-owned parents of /research_jude or
# /lustre_scratch. So stage + build under node-local /tmp (world-traversable),
# then copy the finished .sif back to /research_jude as the real user.
BUILD_DIR="/tmp/wtsi_build.${LSB_JOBID:-$$}"
trap 'rm -rf "${BUILD_DIR}"' EXIT
mkdir -p "${BUILD_DIR}/tmp" "${BUILD_DIR}/cache"; chmod -R 777 "${BUILD_DIR}"
cp "${DEF}" "${BUILD_DIR}/wtsi_pbsc_tools.def"; chmod a+r "${BUILD_DIR}/wtsi_pbsc_tools.def"
export SINGULARITY_TMPDIR="${BUILD_DIR}/tmp"
export SINGULARITY_CACHEDIR="${BUILD_DIR}/cache"
singularity build --fakeroot "${BUILD_DIR}/wtsi_pbsc_tools.sif" "${BUILD_DIR}/wtsi_pbsc_tools.def"
cp -f "${BUILD_DIR}/wtsi_pbsc_tools.sif" "${SIF}"
ls -lh "${SIF}"
```

### 7. Run script (in project dir): `bsub_wtsi_pbsc_mulligan.sh`

Active invocation (resume-enabled, St. Jude profile):

```bash
nextflow run "${pipeline_dir}/isoseq2.nf" \
    -w "${NF_WORK_DIR}" \
    ${RESUME_FLAG} \
    -entry bam_processing_segmented_wf \
    -params-file assets/params.yaml \
    -profile stjude_master,singularity
```

## Outstanding Issues / Next Steps

0. **RUNTIME FIX IN PROGRESS — lima too old for the Revio BAMs.** The first full run (`full_segmented` + `with_quant`, LSF job `295401777`) failed at `REMOVE_PRIMER`: `lima 2.9.0` aborted on every BAM with `std::length_error: cannot create std::vector larger than max_size()` (exit 134). Diagnosis (via `singularity exec wtsi_pbsc_tools.sif` on a segmented BAM) showed the input is a 2026 Revio dataset with BAM spec `pb:5.0.0`, written by on-instrument `lima 2.11.0` / `skera 1.5.0` / `ccs 8.2.0` — newer than the container's `lima 2.9.0`. Fix: bumped `lima=2.9.0` -> `lima=2.13.0` in `containers/wtsi_pbsc_tools.def` and rebuilt (job `295403042`). `isoseq` (4.3.0, the newest biocontainer) and `pbmm2` (1.17.0) are recent enough; only `lima` needed bumping. After the rebuild completes, verify lima parses a BAM, then resume the run by resubmitting `bsub_wtsi_pbsc_mulligan.sh` WITHOUT `FORCE_FRESH` (the completed `create_genedb_fasta_perChr` tasks are cached; the failed `REMOVE_PRIMER` tasks re-run with the new lima).

1. **Image build: DONE** — job `295400398` produced `containers/wtsi_pbsc_tools.sif` (487 MB) and passed `%test`. `singularity exec` verification confirmed isoseq 4.3.0, lima 2.9.0, pbmm2 1.17.0, skera 1.4.0 (+`pbskera` alias), samtools 1.23.1, and a clean runtime `import scanpy/anndata/gffutils/pysam`. Build history: `295393855` failed on a fakeroot permission-traversal issue (fixed by staging under `/tmp`); `295400359` failed `%test` because the `pbskera` binary is `skera` (fixed with a `pbskera -> skera` symlink); `295400367` failed `%test` because `import scanpy` triggered `numba @njit(cache=True)` with no writable cache (fixed by `NUMBA_CACHE_DIR=/tmp` + `MPLCONFIGDIR=/tmp` in `%environment`). A further gap was found: IsoQuant installs as `isoquant` but the pipeline calls `isoquant.py`. A first attempt added an `isoquant.py -> isoquant` **symlink** (rebuild `295400419`), but that broke BOTH commands: a file named `isoquant.py` in `/opt/conda/bin` shadows the `isoquant` python package on `sys.path` (`ImportError: cannot import name 'main_entry' from 'isoquant'`). Fixed by replacing the symlink with a thin **bash wrapper** `/opt/wrappers/isoquant.py` (`exec isoquant "$@"`) on `PATH` but not on `sys.path`, and prepending `/opt/wrappers` to `PATH`; the `%test` now runs `isoquant.py --help`. **Rebuilt as job `295400454` — DONE and verified**: `singularity exec` confirms all 7 tools resolve and `isoquant.py --help` exits 0 / reports `IsoQuant 3.13.1`. This is the final image used for the run.
2. **The run is set for full quantification** — `assets/params.yaml` has `run_mode: "with_quant"` and `bsub_wtsi_pbsc_mulligan.sh` uses `-entry full_segmented`. The run script otherwise needs no changes (container applied via the `stjude_master` profile's global `process.container`).
   - Monitor: `bjobs 295393855`
   - Logs: `containers/build_wtsi_pbsc_tools.out` and `containers/build_wtsi_pbsc_tools.err`
   - Success artifact: `containers/wtsi_pbsc_tools.sif`
   - If the conda solve conflicts, loosen pins in `containers/wtsi_pbsc_tools.def` (e.g., relax `isoquant`/`samtools`) and resubmit `bsub < containers/build_wtsi_pbsc_tools.sh`.
2. **After the `.sif` exists**, verify: `singularity test containers/wtsi_pbsc_tools.sif` (the `%test` checks all tools + python imports).
3. **Run the segmented BAM processing**: submit `bsub_wtsi_pbsc_mulligan.sh` (currently `-entry bam_processing_segmented_wf`).
4. **For quantification**: change the run to `-entry full_segmented` and set `run_mode: with_quant` in `<project>/assets/params.yaml`.
5. **`sqanti3` / `deconvolution` stages** still reference non-existent Sanger `.sif` paths (`/nfs/team152/...`, `/software/hgi/...`). They are NOT used by `full_segmented` + `with_quant`, but must be re-pointed (e.g., to the combined image or local images) before running SQANTI3 or deconvolution.
6. **Verify resource paths in `params.yaml`** exist on St. Jude (notably `threeprime_whitelist`, SQANTI3 reference beds, `pfam_db`) before enabling the steps that consume them.

## Context for LLM Handoff

The `wtsi-pbsc` Nextflow pipeline (PacBio long-read single-cell Iso-Seq, Kinnex) is being adapted to run already-segmented Kinnex BAMs on the St. Jude HPCF LSF cluster. A new `BAM_PROCESSING_SEGMENTED` subworkflow plus `bam_processing_segmented_wf` and `full_segmented` entry points were added so segmented BAMs (post-`pbskera split`) enter at `REMOVE_PRIMER` rather than skera. A St. Jude execution profile (`stjude_master`) was registered in `nextflow.config`, and `conf/stjude_master.config` binds both `/research` and `/research_jude` for Singularity. Analysis showed the pipeline ships almost no usable container definitions and the cluster env lacks the bioinformatics tools, and that PacBio biocontainers are single static binaries without `samtools` (with no prebuilt mulled combos), while several processes need a PacBio tool plus `samtools`/python together. The chosen fix (Option 2) is a single combined Singularity image built from `containers/wtsi_pbsc_tools.def` (isoseq 4.3.0, lima 2.9.0, pbmm2 1.17.0, pbskera 1.4.0, isoquant 3.13.1, samtools, scanpy, anndata, gffutils). Local builds on the login node were impossible (no fakeroot subuid mapping, no proot, no remote builder), but a dedicated LSF `fakeroot` queue exists. Build iterations: `295393855` failed because `--fakeroot` maps to a sub-UID with only "other" permissions that cannot traverse the root-owned parents of `/research_jude` or `/lustre_scratch` (fixed by staging the def/build under node-local `/tmp` and copying the `.sif` back as the real user); `295400359` installed all 139 conda packages but failed the `%test` because the `pbskera` package's binary is named `skera` (fixed by adding a `pbskera -> skera` symlink in `%post`); resubmitted as job `295400367`. The image is wired as the global `process.container` in `conf/stjude_master.config` via `${projectDir}/containers/wtsi_pbsc_tools.sif`, with `sqanti3`/`deconvolution` keeping their own (currently broken) container overrides. The immediate next action when resuming: the image is built and verified at `containers/wtsi_pbsc_tools.sif` (job `295400454`, with the working `isoquant.py` wrapper). Submit `bsub_wtsi_pbsc_mulligan.sh`, which is already set to `-entry full_segmented` with `run_mode: with_quant` in `assets/params.yaml`, for the full end-to-end run. NOTE: `NUMBA_CACHE_DIR=/tmp` and `MPLCONFIGDIR=/tmp` are set in the image `%environment` so the scanpy import in `mtx_to_h5ad` works at runtime inside the read-only container.
