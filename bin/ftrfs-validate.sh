#!/bin/bash
#
# ftrfs-validate.sh -- full pre-push validation chain.
#
# Runs the static invariants check first (fast, no VM), then the HPC
# cluster benchmark (slower, full deploy + Slurm jobs). Use this as the
# canonical pre-push gate:
#
#   ftrfs-validate.sh && git push
#
# If invariants fail, the benchmark is not run -- fixing invariants
# always takes priority over performance regressions.
#
# Audit rationale: a layered validation pipeline (static -> dynamic) is
# the recommended pattern for safety-critical software (DO-178C 6.4.3,
# IEC 61508-3 7.4.6). Static checks catch class-of-bug issues cheaply;
# dynamic checks catch behavioural regressions.
#

set -e

BIN_DIR="$(dirname "$(readlink -f "$0")")"

echo "================================================================"
echo " FTRFS validate -- $(date)"
echo "================================================================"
echo ""

echo "--- Stage 1/2: static invariants ---"
"${BIN_DIR}/ftrfs-invariants.sh"

echo ""
echo "--- Stage 2/2: HPC cluster benchmark ---"
"${BIN_DIR}/hpc-benchmark.sh"

echo ""
echo "================================================================"
echo " ftrfs-validate: all stages passed."
echo "================================================================"
