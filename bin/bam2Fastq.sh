#!/usr/bin/env bash
#
# Copyright (c) 2018 DKFZ.
#
# Distributed under the MIT License (license terms are at https://github.com/TheRoddyWMS/BamToFastqPlugin/blob/master/LICENSE.txt).
#
#
# Environment variables:
#
# bamFile:
#   input BAM file
#
# compressFastqs:
#   Temporary files during sorting are compressed or not (gz), default: true
#
# excludedFlags:
#   space delimited list flags for reads to exclude during processing of: secondary, supplementary
#
# outputPerReadGroup:
#   Write separate FASTQs for each read group into $outputDir/$basename/ directory. Otherwise
#   create $outputDir/${basename}_r{1,2}.fastq{.gz,} files.
#
# writeUnpairedFastq:
#   Additionally write a FASTQ with unpaired reads. Otherwise no such file is written.

source "workflowLib.sh"
printInfo
set -o pipefail
set -uvex

getFastqSuffix() {
    if [[ "$compressFastqs" == true ]]; then
        compressionSuffix=".gz"
    else
        compressionSuffix=""
    fi
    echo "fastq${compressionSuffix}"
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

processPairedEndWithReadGroupsBiobambam() {
    ## Only process the non-supplementary (-F 0x800), primary (-F 0x100) alignments. BWA flags chimeric alignments as supplementary while the
    ## full-length reads are exactly the ones not flagged supplementary. See http://seqanswers.com/forums/showthread.php?t=40239
    ##
    ## Biobambam bamtofastq (2.0.87)
    ##
    ## * takes care of restricting to non-supplementary, primary reads
    ## * requires collation to produce files split by read-groups
    ##
    mkdir -p "$outputDir"
    $BIOBAMBAM_BAM2FASTQ_BINARY \
        filename="$bamFile" \
        T="$bamFile.bamtofastq_tmp" \
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

# Compose a "-F $flags" string to be used for excluding reads by samtools.
samtoolsExclusions() {
    declare -la excludedFlagsArray=("${excludedFlags[@]:-}")
    checkExclusions "${excludedFlagsArray[@]}"
    local exclusionFlag=0
    local exclusionsString=$(stringJoin "," $(toLower "${excludedFlagsArray[@]}"))
    if (echo "$exclusionsString" | grep -wq "supplementary"); then
        let exclusionFlag=($exclusionFlag + 2048)
    fi
    if (echo "$exclusionsString" | grep -wq "secondary"); then
        let exclusionFlag=($exclusionFlag + 256)
    fi
    if [[ $exclusionFlag -gt 0 ]]; then
        echo "-F $exclusionFlag"
    fi
}

processPairedEndWithReadGroupsPicard() {
    local baseName=$(basename "$bamFile" .bam)

    local PICARD_OPTIONS="$PICARD_OPTIONS COMPRESS_OUTPUTS_PER_RG=$compressFastqs OUTPUT_PER_RG=true RG_TAG=${readGroupTag:-id} OUTPUT_DIR=$outputDir/"
    local JAVA_OPTIONS="${JAVA_OPTIONS:-$JAVA_OPTS}"
    ## Only process the non-supplementary (-F 0x800), primary (-F 0x100) alignments. BWA flags chimeric alignments as supplementary while the
    ## full-length reads are exactly the ones not flagged supplementary. See http://seqanswers.com/forums/showthread.php?t=40239.
    "$SAMTOOLS_BINARY" view -u $(samtoolsExclusions) "$bamFile" \
        | "$PICARD_BINARY" $JAVA_OPTIONS SamToFastq $PICARD_OPTIONS INPUT=/dev/stdin
}


processPairedEndWithoutReadGroupsPicard() {
    mkdir -p "$outputDir"

    ## Write just 2-3 FASTQs, depending on whether unpairedFastq is true.
    local PICARD_OPTIONS="$PICARD_OPTIONS COMPRESS_OUTPUTS_PER_RG=$compressFastqs FASTQ=${unsortedFastqs[0]} SECOND_END_FASTQ=${unsortedFastqs[1]}"
    if [[ "${writeUnpairedFastq:-false}" == true ]]; then
        local PICARD_OPTIONS="$PICARD_OPTIONS UNPAIRED_FASTQ=${unsortedFastqs[2]}"
    fi

    ## Only process the non-supplementary reads (-F 0x800). BWA flags all alternative alignments as supplementary while the full-length
    ## reads are exactly the ones not flagged supplementary.
    local JAVA_OPTIONS="${JAVA_OPTIONS:-$JAVA_OPTS}"
    "$SAMTOOLS_BINARY" view -u $(samtoolsExclusions) "$bamFile" \
        | "$PICARD_BINARY" $JAVA_OPTIONS SamToFastq $PICARD_OPTIONS INPUT=/dev/stdin
}

processSingleEndWithReadGroupsPicard() {
    throw 1 "processSingleEndWithReadGroups not implemented"
}

processSingleEndWithoutReadGroupsPicard() {
    throw 1 "processSingleEndWithoutReadGroups not implemented"
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

    outputDir=$(basename "$bamFile")"_fastqs"

    # Re-Array the filenames variable (outputs). Bash does not transfer arrays properly to subprocesses. Therefore Roddy encodes arrays as strings
    # with enclosing parens. That is "(a b c)", with spaces as separators.
    declare -ax excludedFlags=${excludedFlags}

    FASTQ_SUFFIX=$(getFastqSuffix)
    declare -ax readGroups=( $(getReadGroups "$bamFile") )
    declare -ax unsortedFastqs=( $(composeFastqFiles "$outputDir" "$FASTQ_SUFFIX" "${readGroups[@]}") )

    if [[ "${pairedEnd:-true}" == true ]]; then
        if [[ "${outputPerReadGroup:-true}" == true ]]; then
            if [[ "$converter" == "picard" ]]; then
                processPairedEndWithReadGroupsPicard
                ensureAllFiles "${unsortedFastqs[@]}"
            elif [[ "$converter" == "biobambam" ]]; then
                processPairedEndWithReadGroupsBiobambam
                ensureAllFiles "${unsortedFastqs[@]}"
            else
                throw 10 "Unknown bam-to-fastq converter: '$converter'"
            fi
        else
            processPairedEndWithoutReadGroupsPicard
        fi
    else
        if [[ "${outputPerReadGroup:-true}" == true ]]; then
            processSingleEndWithReadGroupsPicard
        else
            processSingleEndWithoutReadGroupsPicard
        fi
    fi
}



main
