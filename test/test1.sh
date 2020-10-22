#
# Copyright (c) 2020 DKFZ.
#
# Distributed under the MIT License (license terms are at https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/LICENSE.txt).
#

set -ue
shopt -p pipefail

outDir="${1:?No outDir set}"
workflowDir="${2:-./}"

readsInBam() {
  local bamFile="${1:?No BAM file given}"
  # Exclude supplementary and secondary alignments.
  samtools view -c -f 2304 "$bamFile"
}

readsInOutputDir() {
  local outputDir="${1:?No outputDir given}"
  for i in $(readlink -f test_out/test1_paired*/*); do
    zcat "$i" |
      paste - - - - |
      wc -l
  done |
    perl -e 'BEGIN { my $sum = 0; } while ($line = <>) { chomp $line; $sum += $line; }; END { print $sum . "\n"; }'
}

assertThat() {
  local first="${1:?No first number given}"
  local second="${2:?No second number given}"
  local message="${3:-"Numbers don't match"}"
  if [[ $first == $second ]]; then
    echo "Failed: $message: $first != $second" >> /dev/stderr
    exit 1
  else
    echo "Success: $message"
  fi
}

mkdir -p "$outDir"

nextflow run "$workflowDir/bam2fastq.nf" \
  -profile test,conda \
  -ansi-log \
  --bamFiles="$workflowDir/test/test1_paired.bam,$workflowDir/test/test1_unpaired.bam" \
  --outputDir="$outDir" \
  --sortFastqs=false
assertThat $(readsInBam "$workflowDir/test/test1_paired.bam") $(readsInOutputDir "$outDir/test1_paired.bam.../") \
  "Unsorted output FASTQs have same number of non-supplementary and non-secondary reads as paired-end input bam."
assertThat $(readsInBam "$workflowDir/test/test1_unpaired.bam") $(readsInOutputDir "$outDir/test1_unpaired.bam.../") \
  "Unsorted output FASTQs have same number of non-supplementary and non-secondary reads as single-end input bam."

nextflow run "$workflowDir/bam2fastq.nf" \
  -profile test,conda \
  -ansi-log \
  --bamFiles="$workflowDir/test/test1_paired.bam,$workflowDir/test/test1_unpaired.bam" \
  --outputDir="$outDir" \
  --sortFastqs=true
assertThat $(readsInBam "$workflowDir/test/test1_paired.bam") $(readsInOutputDir "$outDir/test1_paired.bam.sorted.../") \
  "Sorted output FASTQs have same number of non-supplementary and non-secondary reads as paired-end input bam."
assertThat $(readsInBam "$workflowDir/test/test1_unpaired.bam") $(readsInOutputDir "$outDir/test1_unpaired.bam.sorted.../") \
  "Sorted output FASTQs have same number of non-supplementary and non-secondary reads as single-end input bam."
