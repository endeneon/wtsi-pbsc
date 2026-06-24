#!/bin/bash
#BSUB -q fakeroot
#BSUB -n 4
#BSUB -R "rusage[mem=32G]"
#BSUB -J build_wtsi_pbsc_tools
#BSUB -o build_wtsi_pbsc_tools.out
#BSUB -e build_wtsi_pbsc_tools.err
# ----------------------------------------------------------------------------
# Build the combined wtsi-pbsc tools image on the fakeroot LSF queue.
# Submit with:
#   cd <pipeline>/containers && bsub < build_wtsi_pbsc_tools.sh
# ----------------------------------------------------------------------------
set -euo pipefail

module load singularity/4.3.5

DEF_DIR="/research_jude/rgs01_jude/groups/cab/projects/automapper/common/szhang37/pulled_git_repos/wtsi-pbsc/containers"
DEF="${DEF_DIR}/wtsi_pbsc_tools.def"
SIF="${DEF_DIR}/wtsi_pbsc_tools.sif"

# ----------------------------------------------------------------------------
# IMPORTANT: `singularity build --fakeroot` runs in a user namespace mapped to a
# sub-UID that is neither the file owner nor in the owning group. It therefore
# hits "other" permissions, and CANNOT traverse the root-owned restrictive
# parents of /research_jude (.../automapper is dr-xr-x---) or /lustre_scratch
# (.../user_scratch/$USER is drwxrwx--- root:root). Only /tmp is world-traversable
# (drwxrwxrwt). So stage the def + build entirely under node-local /tmp, then copy
# the finished .sif back to /research_jude as the real user (who owns that dir).
# ----------------------------------------------------------------------------
BUILD_DIR="/tmp/wtsi_build.${LSB_JOBID:-$$}"
cleanup() { rm -rf "${BUILD_DIR}"; }
trap cleanup EXIT

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/tmp" "${BUILD_DIR}/cache"
chmod -R 777 "${BUILD_DIR}"

cp "${DEF}" "${BUILD_DIR}/wtsi_pbsc_tools.def"
chmod a+r "${BUILD_DIR}/wtsi_pbsc_tools.def"

export SINGULARITY_TMPDIR="${BUILD_DIR}/tmp"
export SINGULARITY_CACHEDIR="${BUILD_DIR}/cache"

LOCAL_SIF="${BUILD_DIR}/wtsi_pbsc_tools.sif"

echo "Host: $(hostname)"
echo "Staging build under ${BUILD_DIR} (local /tmp, fakeroot-traversable)"
echo "Building ${LOCAL_SIF}"
echo "  from ${BUILD_DIR}/wtsi_pbsc_tools.def"

singularity build --fakeroot "${LOCAL_SIF}" "${BUILD_DIR}/wtsi_pbsc_tools.def"

echo "Installing image to ${SIF} (atomic temp + mv, so a concurrent run never reads a partial .sif)"
TMP_SIF="${SIF}.tmp.${LSB_JOBID:-$$}"
cp -f "${LOCAL_SIF}" "${TMP_SIF}"
mv -f "${TMP_SIF}" "${SIF}"

echo "BUILD COMPLETE -> ${SIF}"
ls -lh "${SIF}"
