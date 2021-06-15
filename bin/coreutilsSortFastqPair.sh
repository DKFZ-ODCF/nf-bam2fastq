#!/usr/bin/env bash
#
# Copyright (c) 2021 DKFZ.
#
# Distributed under the MIT License (license terms are at https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/LICENSE.txt).
#

source "workflowLib.sh"
printInfo
set -o pipefail
set -uvex
# export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# Read in two files/stream of paired FASTQ files and sort both together.
# Output is two name-sorted FASTQ files.
sortFastqPair() {
    local infile1="${1:?No input fastq 1 given}"
    local infile2="${2:?No input fastq 2 given}"
    local outfile1="${3:?No output fastq 1 given}"
    local outfile2="${4:?No output fastq 2 given}"

    # Ensure the output file directories exist. They are probably the same but I don't bother checking that.
    ensureDirectoryExists "$(dirname "$outfile1")"
    ensureDirectoryExists "$(dirname "$outfile2")"

    local decompressionCommand="cat"
    if [[ "${compressedInputFastqs:-true}" ]]; then
        decompressionCommand="$compressor -d"
    fi

    local linear1Fifo="$(tmpBaseFile "$infile1").linearized.fifo"
    createTmpFifo "$linear1Fifo"
    local linear2Fifo="$(tmpBaseFile "$infile2").linearized.fifo"
    createTmpFifo "$linear2Fifo"
    local sorted1Fifo="$(tmpBaseFile "$outfile1").sorted.fifo"
    createTmpFifo "$sorted1Fifo"
    local sorted2Fifo="$(tmpBaseFile "$outfile2").sorted.fifo"
    createTmpFifo "$sorted2Fifo"

    local linear1Pid
    $decompressionCommand "$infile1" \
        | fastqLinearize \
        > "$linear1Fifo" \
        & linear1Pid=$! \
        || throw 1 "Error linearization 1"

    local linear2Pid
    $decompressionCommand "$infile2" \
        | fastqLinearize \
        > "$linear2Fifo" \
        & linear2Pid=$! \
        || throw 2 "Error linearization 2"

    local compress1Pid
    cat "$sorted1Fifo" \
        | fastqDelinearize \
        | "$compressor" \
        | md5File "$outfile1.md5" \
        > "$outfile1" \
        & compress1Pid=$! \
        || throw 3 "Error delinearization 1"

    local compress2Pid
    cat "$sorted2Fifo" \
        | fastqDelinearize \
        | "$compressor" \
        | md5File "$outfile2.md5" \
        > "$outfile2" \
        & compress2Pid=$! \
        || throw 4 "Error delinearization 2"

    # Note that this temporary file directory must not be node-local. It contains too much data.
    local sortTmp="$(dirname "$outfile1")/sort_tmp"
    mkdir -p "$sortTmp"
    registerTmpFile "$sortTmp"
    registerTmpFile "$sortTmp/*"

    ## TODO Check here that the two files have the same order (just check the two ID columns 1 == 5)
    local sortPid
    paste "$linear1Fifo" "$linear2Fifo" \
        | sortLinearizedFastqStream "$sortTmp" \
        | mbuf 100m \
            -f -o >(cut -f 1-4 > "$sorted1Fifo") \
            -f -o >(cut -f 5-8 > "$sorted2Fifo") \
        & sortPid=$! \
        || throw 5 "Error sorting/splitting"

    wait "$linear1Pid" "$linear2Pid" "$compress1Pid" "$compress2Pid" "$sortPid"
}

# Read in two files/stream of paired FASTQ files and sort both together. Additionally, compare the file streams
# MD5 sum with the one saved in the existing (!) .md5 files. Throw if the MD5 sums don't match or if an MD5
# is missing for an input file.
# Output is two name-sorted FASTQ files.
sortFastqPairWithMd5Check() {
    local infile1="${1:?No input fastq 1 given}"
    local infile2="${2:?No input fastq 2 given}"
    local outfile1="${3:?No output fastq 1 given}"
    local outfile2="${4:?No output fastq 2 given}"

    local referenceMd5File1="$infile1.md5"
    local referenceMd5File2="$infile2.md5"
    if [[ -r "$referenceMd5File1" && -r "$referenceMd5File2" ]]; then

        local tmpBase1="$(tmpBaseFile "$infile1")"
        local tmpBase2="$(tmpBaseFile "$infile2")"

        local infile1Fifo="$tmpBase1.fifo"
        createTmpFifo "$infile1Fifo"
        local infile2Fifo="$tmpBase2.fifo"
        createTmpFifo "$infile2Fifo"
        local tmpMd5File1="$tmpBase1.md5.check"
        createTmpFile "$tmpMd5File1"
        local tmpMd5File2="$tmpBase2.md5.check"
        createTmpFile "tmpMd5File2"

        local md51Pid
        cat "$infile1" \
            | md5File "$tmpMd5File1.infile" \
            > "$infile1Fifo" \
            & md51Pid=$! \
            || throw 6 "Error md5 2"

        local md52Pid
        cat "$infile2" \
            | md5File "$tmpMd5File2.infile" \
            > "$infile2Fifo" \
            & md52Pid=$! \
            || throw 7 "Error md5 2"

        local sortPid
        sortFastqPair "$infile1Fifo" "$infile2Fifo" "$outfile1" "$outfile2" \
            && checkMd5Files "$referenceMd5File1" "$tmpMd5File1" \
            && checkMd5Files "$referenceMd5File2" "$tmpMd5File2" \
            & sortPid=$! \
            || throw 8 "Error sorting & md5-check"

        wait "$md51Pid" "$md52Pid" "$sortPid"
    else
        throw 100 "FASTQ '$infile1' or '$infile2' do not have both a readable MD5 file '$referenceMd5File1' or '$referenceMd5File2'"
    fi
}



setUp_BashSucksVersion

if [[ "${checkFastqMd5:-false}" == true ]]; then
    sortFastqPairWithMd5Check "$fastqFile1" "$fastqFile2" "$sortedFastqFile1" "$sortedFastqFile2" & \
      sortPid=$!
else
    sortFastqPair "$fastqFile1" "$fastqFile2" "$sortedFastqFile1" "$sortedFastqFile2" & \
      sortPid=$!
fi

wait "$sortPid"

cleanUp_BashSucksVersion
