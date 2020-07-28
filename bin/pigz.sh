#!/usr/bin/env bash
#
# Copyright (c) 2020 DKFZ.
#
# Distributed under the MIT License (license terms are at https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/LICENSE.txt).
#

pigz -p "${compressorThreads:-1}" -c "$@"
