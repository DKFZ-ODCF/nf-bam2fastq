#!/bin/bash
#
# Copyright (c) 2021 DKFZ.
#
# Distributed under the MIT License (license terms are at https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/LICENSE.txt).
#

set -ue
set -o pipefail

outDir="${1:?No outDir set}"
environmentProfile="${2:-conda}"
nextflowEnvironment="${3:-$outDir/nextflowEnv}"

workflowDir="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/..")"

readsInBam() {
  local bamFile="${1:?No BAM file given}"
  # Exclude supplementary and secondary alignments.
  samtools view -c -F 2304 "$bamFile"
}

readsInOutputDir() {
  local outputDir="${1:?No outputDir given}"
  zcat --quiet "$outputDir"/* |
    paste - - - - |
    wc -l
}

TEST_TOTAL=0
TEST_ERRORS=0

assertEqual() {
  local first="${1:?No first number given}"
  local second="${2:?No second number given}"
  local message="${3:?No message given}"
  TEST_TOTAL=$((TEST_TOTAL + 1))
  if [[ "$first" == "$second" ]]; then
    echo "Success: $message: $first == $second" >> /dev/stderr
  else
    echo "Failure: $message: $first != $second" >> /dev/stderr
    TEST_ERRORS=$((TEST_ERRORS + 1))
  fi
}

testFinished() {
  echo "" >> /dev/stderr
  echo "$TEST_ERRORS of $TEST_TOTAL tests failed." >> /dev/stderr
  if [[ $TEST_ERRORS -gt 0 ]]; then
    exit 1
  else
    exit 0
  fi
}

# Setup the test environment (nextflow, samtools for getting the read-groups).
mkdir -p "$outDir"
if [[ ! -d "$nextflowEnvironment" ]]; then
  conda env create -v -f "$workflowDir/test-environment.yml" -p "$nextflowEnvironment"
fi
set +ue
source activate "$nextflowEnvironment"
set -ue

# Keep memory footprint small
export NXF_OPTS="-Xmx128m"

# When using Conda, cache the workflow-tasks's environments in the test directory.
export NXF_CONDA_CACHEDIR="$(readlink -f "$outDir/jobEnvs")"

# Run the tests.
nextflow run "$workflowDir/main.nf" \
  -profile "test,$environmentProfile" \
  -ansi-log \
  -resume \
  -work-dir "$outDir/work" \
  --input="$workflowDir/test/test1_paired.bam,$workflowDir/test/test1_unpaired.bam" \
  --outputDir="$outDir" \
  --sortFastqs=false \
  --compressorThreads=0 \
  --sortThreads=1 \
  --sortMemory="100 MB"
assertEqual \
  "$(readsInBam "$workflowDir/test/test1_paired.bam")" \
  "$(readsInOutputDir "$outDir/test1_paired.bam_fastqs")" \
  "Read number in unsorted output FASTQs on paired-end input bam"
assertEqual \
  "$(readsInBam "$workflowDir/test/test1_unpaired.bam")" \
  "$(readsInOutputDir "$outDir/test1_unpaired.bam_fastqs")" \
  "Read number in unsorted output FASTQs on single-end input bam"

nextflow run "$workflowDir/main.nf" \
  -profile "test,$environmentProfile" \
  -ansi-log \
  -resume \
  -work-dir "$outDir/work" \
  --input="$workflowDir/test/test1_paired.bam,$workflowDir/test/test1_unpaired.bam" \
  --outputDir="$outDir" \
  --sortFastqs=true \
  --compressorThreads=0 \
  --sortThreads=1 \
  --sortMemory="100 MB"
assertEqual \
  "$(readsInBam "$workflowDir/test/test1_paired.bam")" \
  "$(readsInOutputDir "$outDir/test1_paired.bam_sorted_fastqs")" \
  "Read number in sorted output FASTQs on paired-end input bam"
assertEqual \
  "$(readsInBam "$workflowDir/test/test1_unpaired.bam")" \
  "$(readsInOutputDir "$outDir/test1_unpaired.bam_sorted_fastqs")" \
  "Read number in sorted output FASTQs on single-end input bam"

testFinished
