#
# Copyright (c) 2020 DKFZ.
#
# Distributed under the MIT License (license terms are at https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/LICENSE.txt).
#

set -ue
set -o pipefail

outDir="${1:?No outDir set}"
workflowDir=$(readlink -f "${2:-./}")

readsInBam() {
  local bamFile="${1:?No BAM file given}"
  # Exclude supplementary and secondary alignments.
  samtools view -c -F 2304 "$bamFile"
}

readsInOutputDir() {
  local outputDir="${1:?No outputDir given}"
  zcat --quiet "$outputDir"/* \
    | paste - - - - \
    | wc -l
}

assertThat() {
  local first="${1:?No first number given}"
  local second="${2:?No second number given}"
  local message="${3:?No message given}"
  if [[ "$first" == "$second" ]]; then
    echo "Success: $message: $first == $second" >> /dev/stderr
  else
    echo "Failure: $message: $first != $second" >> /dev/stderr
  fi
}

# Setup the environments (nextflow, samtools).
mkdir -p "$outDir"
if [[ ! -d "$outDir/test-environment" ]]; then
  conda env create -f "$workflowDir/test-environment.yml" -p "$outDir/test-environment"
fi
set +ue
source "$CONDA_PREFIX/bin/activate" "$outDir/test-environment"
set -ue

# Run the tests.
nextflow run "$workflowDir/bam2fastq.nf" \
  -profile test,conda \
  -ansi-log \
  -resume \
  --bamFiles="$workflowDir/test/test1_paired.bam,$workflowDir/test/test1_unpaired.bam" \
  --outputDir="$outDir" \
  --sortFastqs=false
assertThat "$(readsInBam "$workflowDir/test/test1_paired.bam")" "$(readsInOutputDir "$outDir/test1_paired.bam_fastqs")" \
  "Unsorted output FASTQs have correct number of non-supplementary and non-secondary reads for paired-end input bam"
assertThat "$(readsInBam "$workflowDir/test/test1_unpaired.bam")" "$(readsInOutputDir "$outDir/test1_unpaired.bam_fastqs")" \
  "Unsorted output FASTQs have correct number of non-supplementary and non-secondary reads for single-end input bam"

nextflow run "$workflowDir/bam2fastq.nf" \
  -profile test,conda \
  -ansi-log \
  -resume \
  --bamFiles="$workflowDir/test/test1_paired.bam,$workflowDir/test/test1_unpaired.bam" \
  --outputDir="$outDir" \
  --sortFastqs=true
assertThat "$(readsInBam "$workflowDir/test/test1_paired.bam")" "$(readsInOutputDir "$outDir/test1_paired.bam_sorted_fastqs")" \
  "Sorted output FASTQs have correct number of non-supplementary and non-secondary reads for paired-end input bam"
assertThat "$(readsInBam "$workflowDir/test/test1_unpaired.bam")" "$(readsInOutputDir "$outDir/test1_unpaired.bam_sorted_fastqs")" \
  "Sorted output FASTQs have correct number of non-supplementary and non-secondary reads for single-end input bam"

