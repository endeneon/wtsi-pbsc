#! /bin/bash

#BSUB -n 2
#BSUB -R "rusage[mem=16G]"

#BSUB -q "priority"
#BSUB -J "run_bsub_nextflow_wtsi-pbsc_mulligan"

#BSUB -o log/out.wtsi-pbsc.mulligan.%J
#BSUB -e log/err.wtsi-pbsc.mulligan.%J

# To submit this script to LSF, use the following command in the terminal to
# add the date and time to the job name for easier tracking:
# bsub -J "run_bsub_nextflow_wtsi-pbsc_mulligan.$(date +%F.%T)" < bsub_wtsi_pbsc_mulligan.sh

# Note: #BSUB directives are only parsed when the script is fed via stdin.
# When you pass the script as a positional argument (bsub script.sh),
# LSF just executes it as a command and ignores all #BSUB lines.
# The -J on the command line overrides the #BSUB -J in the script,
# while < ensures all other #BSUB directives (-n, -R, -q, -o, -e) are still read.
# The same pattern applies for --force-fresh — it cannot be passed as a positional arg this way.
# If you ever need both simultaneously, you'd need a thin wrapper script
# or to temporarily edit FORCE_FRESH=true directly in the file.

mkdir -p log

# Parse optional arguments: --force-fresh to discard any interrupted run and start over
# Can be activated two ways:
#   1. Positional arg (only works when script is run directly, NOT via stdin redirect):
#        bsub script.sh --force-fresh
#   2. Environment variable (works with stdin redirect, preferred):
#        FORCE_FRESH=true bsub -J "..." < script.sh
FORCE_FRESH=${FORCE_FRESH:-false}
for arg in "$@"; do
	[[ "${arg}" == "--force-fresh" ]] && FORCE_FRESH=true
done

pipeline_dir="/research_jude/rgs01_jude/groups/cab/projects/automapper/common/szhang37/pulled_git_repos/wtsi-pbsc"
[[ ! -d "${pipeline_dir}" ]] && echo "Error: Pipeline directory not found: ${pipeline_dir}" >&2 && exit 1

work_dir="/research_jude/rgs01_jude/groups/mulligrp/projects/mulligrp_cab/common/MULLI_875886_KINNEX/CAB_10403_Fusion_detection"
cd "${work_dir}" || exit 1

module load conda3/202402
# this env runs Nextflow 25.04.8
# Source conda's shell hook so `conda activate` works in a non-interactive batch
# shell. Without this, the job intermittently dies with
#   "CondaError: Run 'conda init' before 'conda activate'"
# depending on whether the execution host happened to source the hook via .bashrc.
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate /research_jude/rgs01_jude/groups/cab/projects/automapper/common/szhang37/standalone_conda_envs/nextflow_25_04_8 || exit 1
# this is the alternate 25.10 environment
# conda activate /research_jude/rgs01_jude/groups/cab/projects/automapper/common/szhang37/projects/yang2grp/CANCER_SPLICEOSOME/nfcore_static_conda

module load singularity/4.3.5

# stjude_master is registered as a named profile in the pipeline's nextflow.config
# CUSTOM_CONFIG="${pipeline_dir}/conf/stjude_master.config"

WORK_DIR_RECORD="${work_dir}/.nf_workdir"
RUN_STATE_FILE="${work_dir}/.nf_run_state"

# Auto-detect resume: if a previous run started but did not complete successfully
# Pass --force-fresh to bsub submission to discard the interrupted run and start over
if [[ "${FORCE_FRESH}" == "true" ]]; then
	echo "--force-fresh specified: discarding any previous interrupted run and starting fresh."
	rm -f "${RUN_STATE_FILE}" "${WORK_DIR_RECORD}"
fi

# TEMP(2026-06-25): accept "completed" as well as "running" so that after a
# successful run the next submission still RESUMES the same work dir and reuses
# cached intermediates (needed while adding more modules). Revert to == "running"
# to restore normal behaviour (a completed run then starts fresh).
if [[ -f "${RUN_STATE_FILE}" && $(cat "${RUN_STATE_FILE}") == "running" && -f "${WORK_DIR_RECORD}" ]]; then
	NF_WORK_DIR=$(cat "${WORK_DIR_RECORD}")
	RESUME_FLAG="-resume"
	echo "Detected resumable previous run. Resuming with work dir: ${NF_WORK_DIR}"
else
	NF_WORK_DIR="/lustre_scratch/user_scratch/${USER}/nextflow_work/wtsi-pbsc.$(date +%F.%T)"
	echo "${NF_WORK_DIR}" >"${WORK_DIR_RECORD}"
	RESUME_FLAG=""
	echo "Starting fresh run, work dir: ${NF_WORK_DIR}"
fi

# Mark run as in-progress before launching
echo "running" >"${RUN_STATE_FILE}"
nextflow run "${pipeline_dir}/isoseq2.nf" \
	-w "${NF_WORK_DIR}" \
	${RESUME_FLAG} \
	-entry full_segmented \
	-params-file assets/params.yaml \
	-profile stjude_master,singularity

NF_EXIT_CODE=$?
if [[ ${NF_EXIT_CODE} -eq 0 ]]; then
	echo "completed" >"${RUN_STATE_FILE}"
	# TEMP(2026-06-25): keep the work dir record so the next submission resumes and
	# reuses cached intermediates instead of starting fresh. Restore the rm below to
	# re-enable normal post-run cleanup.
	# rm -f "${WORK_DIR_RECORD}"
	echo "Pipeline completed successfully (work dir kept for -resume; cleanup temporarily disabled)."
else
	echo "Pipeline exited with code ${NF_EXIT_CODE}. Resubmit this script to resume." >&2
	exit ${NF_EXIT_CODE}
fi
