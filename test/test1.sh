#
# Copyright (c) 2020 DKFZ.
#
# Distributed under the MIT License (license terms are at https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/LICENSE.txt).
#

set -ue
set -o pipefail

outDir="${1:?No outDir set}"
environmentDir="${2:-"$outDir/test-environment"}"

workflowDir="$(readlink -f $(readlink -f $(dirname "$BASH_SOURCE")"/.."))"

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

assertThat() {
  local first="${1:?No first number given}"
  local second="${2:?No second number given}"
  local message="${3:?No message given}"
  let TEST_TOTAL=($TEST_TOTAL + 1)
  if [[ "$first" == "$second" ]]; then
    echo "Success: $message: $first == $second" >>/dev/stderr
  else
    echo "Failure: $message: $first != $second" >>/dev/stderr
    let TEST_ERRORS=($TEST_ERRORS + 1)
  fi
}

testFinished() {
  echo "" >>/dev/stderr
  echo "$TEST_ERRORS of $TEST_TOTAL tests failed." >>/dev/stderr
  if [[ $TEST_ERRORS > 0 ]]; then
    exit 1
  else
    exit 0
  fi
}

# Setup the environments (nextflow, samtools).
mkdir -p "$outDir"
if [[ ! -d "$environmentDir" ]]; then
  conda env create -f "$workflowDir/test-environment.yml" -p "$environmentDir"
fi
set +ue
source activate "$environmentDir"
set -ue

# Run the tests.
nextflow run "$workflowDir/bam2fastq.nf" \
  -profile test,conda \
  -ansi-log \
  -resume \
  --bamFiles="$workflowDir/test/test1_paired.bam,$workflowDir/test/test1_unpaired.bam" \
  --outputDir="$outDir" \
  --sortFastqs=false \
  --compressorThreads=1 \
  --sortThreads=1 \
  --sortMemory="100 MB"
assertThat $(readsInBam "$workflowDir/test/test1_paired.bam") $(( $(readsInOutputDir "$outDir/test1_paired.bam_fastqs") + 265 )) \
  "Read number in unsorted output FASTQs on paired-end input bam (accounting for 265 missing reads due to biobambam2 2.0.87 bug)"
assertThat $(readsInBam "$workflowDir/test/test1_unpaired.bam") $(readsInOutputDir "$outDir/test1_unpaired.bam_fastqs") \
  "Read number in unsorted output FASTQs on single-end input bam"

nextflow run "$workflowDir/bam2fastq.nf" \
  -profile test,conda \
  -ansi-log \
  -resume \
  --bamFiles="$workflowDir/test/test1_paired.bam,$workflowDir/test/test1_unpaired.bam" \
  --outputDir="$outDir" \
  --sortFastqs=true \
  --compressorThreads=1 \
  --sortThreads=1 \
  --sortMemory="100 MB"
assertThat $(readsInBam "$workflowDir/test/test1_paired.bam") $(( $(readsInOutputDir "$outDir/test1_paired.bam_sorted_fastqs") + 265 )) \
  "Read number in sorted output FASTQs on paired-end input bam (accounting for 265 missing reads due to biobambam2 2.0.87 bug)"
assertThat $(readsInBam "$workflowDir/test/test1_unpaired.bam") $(readsInOutputDir "$outDir/test1_unpaired.bam_sorted_fastqs") \
  "Read number in sorted output FASTQs on single-end input bam"

testFinished
