# Nextflow 25.04 Syntax Conformance — Lint Findings

## Purpose

Audit of all `.nf` and `.config` files in the `wtsi-pbsc` pipeline against the
**Nextflow 25.04 strict language parser**. Goal: every line must be parseable
(no hard errors). Warnings (e.g. unused closure parameters) are **not** treated
as failures.

> Status: findings recorded — **no fixes applied yet**. Revise the lines below,
> then re-run the lint command to confirm.

## How to reproduce

```bash
module load conda3/202402
conda activate /research_jude/rgs01_jude/groups/cab/projects/automapper/common/szhang37/standalone_conda_envs/nextflow_25_04_8
# Nextflow 25.04.8 build 5956
cd /home/szhang37/CAB_workspace/pulled_git_repos/wtsi-pbsc
nextflow lint .
```

## Result summary

- ❌ **9 files** had **21 errors**
- ✅ **19 files** had no errors

| Category                                      | Count | Files                                                                      |
| --------------------------------------------- | ----- | -------------------------------------------------------------------------- |
| Top-level statements outside process/workflow | 3     | `isoseq2.nf`                                                               |
| Shell vs Groovy `${}` interpolation           | 5     | `modules/barcodes.nf`, `modules/matching_barcodes.nf`                      |
| Reserved `_` identifier                       | 4     | `modules/match_gt.nf`, `subworkflows/deconvolution/deconvolution.nf`       |
| Misplaced `label` after `output:` block       | 2     | `modules/match_gt.nf`                                                      |
| Genuinely undefined symbols                   | 3     | `modules/match_gt.nf`, `subworkflows/isoquant_recipes/isoquant_twopass.nf` |
| Config-structure rules                        | 6     | `conf/base.config`, `conf/stjude_master.config`, `nextflow.config`         |

---

## Errors by file

### `isoseq2.nf` — 3 errors
Top-level statements aren't allowed in strict syntax; they must live inside a
`process` or `workflow`.

| Line | Code                                                          | Error                                               |
| ---- | ------------------------------------------------------------- | --------------------------------------------------- |
| 20   | `if(!params.barcode_correction_percentile) {`                 | Statements cannot be mixed with script declarations |
| 23   | `if(!params.min_polya_length) {`                              | Statements cannot be mixed with script declarations |
| 32   | `assert params.run_mode in ['with_quant', 'pre_quant'] : ...` | Statements cannot be mixed with script declarations |

### `modules/barcodes.nf` — 4 errors
Bash shell variables referenced with `${...}` are parsed as Groovy interpolation
(would need `\${...}` to defer to the shell).

| Line          | Symbol        | Error                        |
| ------------- | ------------- | ---------------------------- |
| 122 (col 118) | `tmp_out_bam` | `tmp_out_bam` is not defined |
| 123 (col 38)  | `tmp_out_bam` | `tmp_out_bam` is not defined |
| 124 (col 51)  | `tmp_out_bam` | `tmp_out_bam` is not defined |
| 124 (col 163) | `out_bam`     | `out_bam` is not defined     |

### `modules/match_gt.nf` — 4 errors

| Line | Code                      | Error                                                                                            |
| ---- | ------------------------- | ------------------------------------------------------------------------------------------------ |
| 163  | `(_, pool_id) = (...)`    | `_` is reserved and not allowed as an identifier                                                 |
| 203  | `label 'gtcheck_summary'` | Placed after `output:` block → "Unrecognized process output qualifier `label`"                   |
| 223  | `tag "${pool_id}"`        | `pool_id` is not defined — process `COMBINE_ASSIGN` only declares `input: path assignment_table` |
| 244  | `label 'gtcheck_summary'` | Same misplaced-`label` issue as line 203                                                         |

### `modules/matching_barcodes.nf` — 1 error
Inside a `"""` script string the `//` is literal text (not a Groovy comment), so
`${donors_to_remove}` is parsed as a Groovy variable.

| Line         | Code                                                                       | Error                             |
| ------------ | -------------------------------------------------------------------------- | --------------------------------- |
| 122 (col 56) | `//remove_donor_assignments.py ${donor_asignment} ${donors_to_remove} ...` | `donors_to_remove` is not defined |

### `subworkflows/deconvolution/deconvolution.nf` — 2 errors

| Line         | Code                                      | Error                                            |
| ------------ | ----------------------------------------- | ------------------------------------------------ |
| 33 (col 111) | `.map { experiment, bam, bai, _ -> ... }` | `_` is reserved and not allowed as an identifier |
| 34 (col 111) | `.map { experiment, bam, bai, _ -> ... }` | `_` is reserved and not allowed as an identifier |

### `subworkflows/isoquant_recipes/isoquant_twopass.nf` — 1 error

| Line | Code                                                | Error                                                              |
| ---- | --------------------------------------------------- | ------------------------------------------------------------------ |
| 49   | `run_isoquant_perChr(isoquant_secondpass_input_ch)` | `run_isoquant_perChr` is not defined (not `include`d in this file) |

### `conf/base.config` — 3 errors
`check_max` is defined in `nextflow.config` but isn't visible here under strict
config parsing.

| Line | Code                                                      | Error                      |
| ---- | --------------------------------------------------------- | -------------------------- |
| 5    | `cpus   = { check_max( 1    * task.attempt, 'cpus'   ) }` | `check_max` is not defined |
| 6    | `memory = { check_max( 2.GB * task.attempt, 'memory' ) }` | `check_max` is not defined |
| 7    | `time   = { check_max( 1.h  * task.attempt, 'time'   ) }` | `check_max` is not defined |

### `conf/stjude_master.config` — 2 errors

| Line | Code                                      | Error                                                          |
| ---- | ----------------------------------------- | -------------------------------------------------------------- |
| 191  | `jobName = { ... }` (in `executor` scope) | Dynamic config options are only allowed in the `process` scope |
| 192  | `task.name`                               | `task` is not defined                                          |

### `nextflow.config` — 1 error

| Line | Code                                                                                            | Error                                                                                 |
| ---- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| 7    | `includeConfig "https://raw.githubusercontent.com/nf-core/configs/master/nfcore_custom.config"` | "Unexpected input: 'includeConfig'" — cannot be nested inside a `try { } catch` block |

---

## Notes for the fix pass

- **Reserved `_`** (match_gt L163, deconvolution L33/L34): strict-syntax only —
  rename to a real identifier or use a non-reserved placeholder.
- **Shell `${}`** (barcodes L122–124, matching_barcodes L122): likely needs `\$`
  escaping so the value resolves in the shell, not Groovy.
- **Misplaced `label`** (match_gt L203/L244): move the `label` directive above
  the `output:` block.
- **Undefined symbols**: match_gt L223 `pool_id` (add to input or fix `tag`),
  isoquant_twopass L49 `run_isoquant_perChr` (missing `include`), and the
  `check_max` visibility across config files.
- **Config-structure**: `jobName` dynamic closure, nested `includeConfig`, and
  `check_max` need to follow strict config scoping rules.

After revising, re-run `nextflow lint .` and aim for **0 errors** (warnings OK).
