#!/usr/bin/env bash
#
# Copyright (c) 2020 DKFZ.
#
# Distributed under the MIT License (license terms are at https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/LICENSE.txt).
#
#
# Environment variables:
#
# bamFile:
#   input BAM file
#
# compressFastqs:
#   Output files are compressed or not (gz), default: true
#
# excludedFlags:
#   space delimited list flags for reads to exclude during processing of: secondary, supplementary
#
# writeUnpairedFastq:
#   Additionally write a FASTQ with unpaired reads. Otherwise no such file is written.

source "workflowLib.sh"
printInfo
set -o pipefail
set -uvex

getFastqSuffix() {
    if [[ "$compressFastqs" == true ]]; then
        echo "fastq.gz"
    else
        echo "fastq"
    fi
}

fastqForGroupIndex() {
    local fgindex="${1:?No filegroup index}"
    declare -a files=$(for fastq in ${unsortedFastqs[@]}; do
        echo "$fastq"
    done | grep --color=no "$fgindex")
    if [[ ${#files[@]} != 1 ]]; then
        throw 10 "Expected to find exactly 1 FASTQ for file-group index '$fgindex' -- found ${#files[@]}: ${files[@]}"
    fi
    echo "${files[0]}"
}

biobambamCompressFastqs() {
    if [[ "$compressFastqs" == true ]]; then
        echo 1
    else
        echo 0
    fi
}

checkExclusions() {
    declare -la flagList=($@)
    for flag in "${flagList[@]}"; do
       if [[ $(toLower "$flag") != "secondary" && $(toLower "$flag") != "supplementary" ]]; then
          throw 20 "Cannot set '$flag' flag."
       fi
    done
}

bamtofastqExclusions() {
    declare -la _excludedFlags=("${excludedFlags[@]:-}")
    checkExclusions "${_excludedFlags[@]}"
    toUpper $(stringJoin "," "${_excludedFlags[@]}")
}

processPairedEndWithReadGroups() {
    local bamFile="${1:?No BAM file given}"
    local outputDir="${2:?No outputDir given}"
    ## BWA flags chimeric alignments as supplementary while the full-length reads are the ones not flagged
    ## supplementary (http://seqanswers.com/forums/showthread.php?t=40239). To get the full set of reads back from a
    ## (complete) BWA use only non-supplementary (-F 0x800) and primary (-F 0x100) alignments.
    ##
    ## Biobambam bamtofastq (2.0.87)
    ##
    ## * takes care of restricting to non-supplementary, primary reads
    ## * requires collation to produce files split by read-groups
    ##
    mkdir -p "$outputDir"
    local tempFile="$outputDir/"$(basename ""$bamFile"")".bamtofastq_tmp"
    $BIOBAMBAM_BAM2FASTQ_BINARY \
        filename="$bamFile" \
        T="$tempFile" \
        outputperreadgroup=1 \
        outputperreadgrouprgsm=0 \
        outputdir="$outputDir/" \
        collate=1 \
        colsbs=268435456 \
        colhlog=19 \
        gz=$(biobambamCompressFastqs) \
        outputperreadgroupsuffixF=_R1."$FASTQ_SUFFIX" \
        outputperreadgroupsuffixF2=_R2."$FASTQ_SUFFIX" \
        outputperreadgroupsuffixO=_U1."$FASTQ_SUFFIX" \
        outputperreadgroupsuffixO2=_U2."$FASTQ_SUFFIX" \
        outputperreadgroupsuffixS=_S."$FASTQ_SUFFIX" \
        exclude="$(bamtofastqExclusions)"
}


ensureAllFiles() {
    declare -a files=( "$@" )
    for f in "${files[@]}"; do
        if [[ ! -f "$f" ]]; then
            cat /dev/null | gzip -c - > "$f"
        fi
    done
}


main() {
    "$SAMTOOLS_BINARY" quickcheck "$bamFile"

    outputDir=${outputDir:-$(basename "$bamFile")"_fastqs"}

    # Re-Array the filenames variable (outputs). Bash <= 4 does not transfer arrays properly to subprocesses. Therefore
    # we encode arrays as strings with enclosing parens. That is "(a b c)", with spaces as separators.
    declare -ax excludedFlags=${excludedFlags}

    FASTQ_SUFFIX=$(getFastqSuffix)
    declare -ax readGroups=( $(getReadGroups "$bamFile") )
    declare -ax unsortedFastqs=( $(composeFastqFiles "$outputDir" "$FASTQ_SUFFIX" "${readGroups[@]}") )

    processPairedEndWithReadGroups "$bamFile" "$outputDir"
    ensureAllFiles "${unsortedFastqs[@]}"
}



main
