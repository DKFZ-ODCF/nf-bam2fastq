#!/usr/bin/env bash
#
# Copyright (c) 2021 DKFZ.
#
# Distributed under the MIT License (license terms are at https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/LICENSE.txt).
#

# Required for the integration tests. Travis-CI VMs have only two CPUs. With 
# compressorThreads=1 the integration tests fail because Nextflow checks the 
# number of CPUs.
if [[ ! -v compressorThreads || "$compressorThreads" -lt 1 ]]; then
	compressorThreads=1
fi
pigz -p "${compressorThreads:-1}" -c "$@"
