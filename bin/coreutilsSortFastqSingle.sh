#!/usr/bin/env bash
#
# Copyright (c) 2020 DKFZ.
#
# Distributed under the MIT License (license terms are at https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/LICENSE.txt).
#

# fastqFile: Path of the input FASTQ to process.
# sortedFastqFile: Path of the unsorted output FASTQ.
# checkFastqMd5: Create MD5 file of output FASTQs. true/false. Default: false
# compressor: An executable with the interface:
#             * "$compressor < uncompressed > compressed"
#             * "$compressor -d < compressed > uncompressed"
# compressIntermediateFastqs: true/false. Default: true. $compressor is used for decompression.

source $(dirname $(readlink -f "$0"))/"workflowLib.sh"

printInfo
set -o pipefail
set -uvex
# export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

sortFastq() {
    local infile="${1:-/dev/stdin}"
    local outfile="${2:-/dev/stdout}"

    ensureDirectoryExists $(dirname "$outfile")

    local decompressionCommand="cat"
    if [[ "${compressIntermediateFastqs:-true}" ]]; then
        decompressionCommand="$compressor -d"
    fi

    ($decompressionCommand "$infile" \
        | fastqLinearize \
        | sortLinearizedFastqStream $(basename "$infile") \
        | fastqDelinearize \
        | $compressor \
        | md5File "$outfile.md5" \
        > "$outfile") \
        || throw 1 "Error linearization/sorting/delinearization"
}

sortFastqWithMd5Check() {
    local infile="${1:?No input FASTQ file to sort}"
    local outfile="${2:?No output FASTQ file}"
    local referenceMd5File="$infile.md5"
    if [[ ! -r "$referenceMd5File" ]]; then
        throw 50 "Cannot read MD5 file '$referenceMd5File'"
    else
        local tmpInputMd5=$(createTmpFile $(tmpBaseFile "$infile")".md5.check")
        (cat "$infile" \
            | md5File "$tmpInputMd5" \
            | sortFastq /dev/stdin "$outfile" \
            && \
            checkMd5Files "$referenceMd5File" "$tmpInputMd5") \
            || throw 8 "Error sorting & md5 check"
    fi
}

setUp_BashSucksVersion

if [[ "${checkFastqMd5:-false}" == true ]]; then
    sortFastqWithMd5Check "$fastqFile" "$sortedFastqFile" \
      & sortPid=$!
else
    sortFastq "$fastqFile" "$sortedFastqFile" \
      & sortPid=$!
fi

# Wait for network filesystem delays and processes to start up.
sleep 15

wait "$sortPid"
cleanUp_BashSucksVersion
