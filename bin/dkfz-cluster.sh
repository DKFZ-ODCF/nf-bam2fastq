#!/usr/bin/env bash

module load bash/4.4.18
module load samtools/1.5
module load picard/2.13.2
module load java/1.8.0_131
module load mbuffer/20160613
module load biobambam2/2.0.87

export SAMTOOLS_BINARY=samtools
export PICARD_BINARY=picard
export JAVA_BINARY=java
export MBUFFER_BINARY=mbuffer
export CHECKSUM_BINARY=md5sum
export PERL_BINARY=perl
export BIOBAMBAM_BAM2FASTQ_BINARY=bamtofastq
