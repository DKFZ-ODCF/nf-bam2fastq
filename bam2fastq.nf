/**
 *  Copyright (c) 2020 DKFZ.
 *
 *  Distributed under the MIT License (license terms are at https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/LICENSE.txt).
 *
 *  Author: Philip R. Kensche
 */

/** Comma-separated list of input BAMs */
params.bamFiles

/** Path to which data should be written. One subdirectory per input BAM. */
params.outputDir

/** Whether to sort the output FASTQs. */
params.sortFastqs = true

/** Whether the BAM files contain paired-end reads. */
params.pairedEnd = true

/** Write a file with unpaired reads. */
params.writeUnpairedFastq = false

/** Alignments with these flags are excluded. Comma delimited list (interpreted as bash array) of the following values:
 *  secondary, supplementary. */
params.excludedFlags = "secondary,supplementary"

/** While reading in intermediate (yet unsorted) FASTQs, check that the MD5 is the same as in the accompanied '.md5'
 *  file. Only available for Picard, as Biobambam does not produce MD5 files for output files. */
params.checkIntermediateFastqMd5 = true

/** Whether to compress intermediate (yet unsorted) FASTQs. Applies only when sortFastqs = true.
 *  Note that the final FASTQs are always compressed. */
params.compressIntermediateFastqs = true

/** Compression binary or script used for (de)compression of sorted output FASTQs. gzip, ${TOOL_PIGZ}.
 *  API for $compressor:
 *      * $compressor < uncompressed > compressed
 *      * $compressor -d < compressed > uncompressed
 *      * compressorThreads=$threads $compressor # change number of threads
 */
String compressor = "pigz.sh"
params.compressorThreads = 4

/** Memory used for storing data while sorting. Is passed to the sorting tool and should follow its required syntax.
 *  WARNING: Also adapt the job requirements! */
params.sortMemory = 1.GB

/** The number of parallel threads used for sorting. */
params.sortThreads = 4

/** Produce more output for debugging. */
params.debug = false



allowedParameters = ['bamFiles', 'outputDir',
                     'sortFastqs', 'sortMemory', 'sortThreads',
                     'pairedEnd', 'writeUnpairedFastq',
                     'compressIntermediateFastqs', 'compressorThreads',
                     'excludedFlags', 'checkIntermediateFastqMd5',
                     'debug']

checkParameters(params, allowedParameters)


def fastqSuffix(Boolean compressed) {
    if (compressed)
        return "fastq.gz"
    else
        return "fastq"
}


def sortedFastqFile(String outDir, Path unsortedFastq, Boolean compressed) {
    String result = outDir + "/" + unsortedFastq.getFileName().toString().replaceFirst(/\.fastq(?:\.gz)?$/, ".sorted.fastq")
    if (compressed)
        return result + ".gz"
    else
        return result
}


log.info """
==================================
= Bam2Fastq                      =
==================================
${allowedParameters.collect { "$it = ${params.get(it)}" }.join("\n")}

"""


bamFiles_ch = Channel.
        fromPath(params.bamFiles.split(',') as List<String>,
                 checkIfExists: true)


Boolean compressBamToFastqOutput = params.sortFastqs ? params.compressIntermediateFastqs : true

process bamToFastq {
    // Just bamtofastq
    cpus 1
    // The biobambam paper states something like 133 MB.
    memory { 300.MB * task.attempt }
    time { 1.hour * task.attempt }
    maxRetries 3

    publishDir params.outputDir, enabled: !params.sortFastqs

    input:
        file bamFile from bamFiles_ch

    output:
        tuple file(bamFile), file("**/*.${fastqSuffix(compressBamToFastqOutput)}") into readsFiles_ch

    shell:
    """
    pairedEnd="$params.pairedEnd" \
        writeUnpairedFastq="$params.writeUnpairedFastq" \
        excludedFlags="(${params.excludedFlags.split(",").join(" ")})" \
        compressor="$compressor" \
        compressorThreads="$params.compressorThreads" \
        compressFastqs="$compressBamToFastqOutput" \
        bamFile="$bamFile" \
        converter="biobambam" \
        outputDir="${bamFile}_fastqs" \
        bam2Fastq.sh
    """

}

// Create two channels of matched paired-end and unmatched or single-end reads, each of tuples of (bam, fastq).
readsFiles_ch.into { readsFilesA_ch; readsFilesB_ch }
pairedFastqs_ch = readsFilesA_ch.flatMap {
    def (bam, fastqs) = it
    fastqs.grep { it.getFileName() =~ /.+_R[12]\.fastq(?:\.[^.]*)?$/ }.
            groupBy { fastq -> fastq.getFileName().toString().replaceFirst("_R[12].fastq(?:.gz)?\$", "") }.
            collect { key, files ->
                assert files.size() == 2
                files.sort()
                [bam, files[0], files[1]]
            }
}


unpairedFastqs_ch = readsFilesB_ch.flatMap {
    def (bam, fastqs) = it
    fastqs.
            grep { it.getFileName() =~ /.+_(U[12]|S)\.fastq(?:\.[^.]*)?$/ }.
            collect { [bam, it] }
}


process nameSortUnpairedFastqs {
  cpus { (params.sortThreads + (params.compressIntermediateFastqs ? params.compressorThreads : 0 )) * task.attempt; 1 }
    memory { (params.sortMemory * params.sortThreads + 50.MB) * task.attempt }
    time 1.hour
    maxRetries 3

    publishDir params.outputDir

    when:
        params.sortFastqs

    input:
        tuple file(bam), file(fastq) from unpairedFastqs_ch

    output:
        tuple file(bam), file(sortedFastqFile) into sortedUnpairedFastqs_ch

    script:
    bamFileName = bam.getFileName().toString()
    outDir = "${bamFileName}_sorted_fastqs"
    sortedFastqFile = sortedFastqFile(outDir, fastq, true)
    """
    mkdir -p "$outDir"
    compressedInputFastqs="$compressBamToFastqOutput" \
        compressor="$compressor" \
        compressorThreads="$params.compressorThreads" \
        sortThreads="$params.sortThreads" \
        sortMemory="${toSortMemoryString(params.sortMemory)}"	\
        fastqFile="$fastq" \
        sortedFastqFile="$sortedFastqFile" \
        coreutilsSortFastqSingle.sh
    """

}


process nameSortPairedFastqs {
    cpus { (params.sortThreads + (params.compressIntermediateFastqs ? params.compressorThreads * 2 : 0)) * task.attempt; 1 }
    memory { (params.sortMemory * params.sortThreads + 200.MB) * task.attempt }
    time 1.hour
    maxRetries 3

    publishDir params.outputDir

    when:
    params.sortFastqs

    input:
    tuple file(bam), file(fastq1), file(fastq2) from pairedFastqs_ch

    output:
    tuple file(bam), file(sortedFastqFile1), file(sortedFastqFile2) into sortedPairedFastqs_ch

    script:
    bamFileName = bam.getFileName().toString()
    outDir = "${bamFileName}_sorted_fastqs"
    sortedFastqFile1 = sortedFastqFile(outDir, fastq1, true)
    sortedFastqFile2 = sortedFastqFile(outDir, fastq2, true)
    """
    mkdir -p "$outDir"
    compressedInputFastqs="$compressBamToFastqOutput" \
        compressor="$compressor" \
        compressorThreads="$params.compressorThreads" \
        sortThreads="$params.sortThreads" \
        sortMemory="${toSortMemoryString(params.sortMemory)}"	\
        fastqFile1="$fastq1" \
        fastqFile2="$fastq2" \
        sortedFastqFile1="$sortedFastqFile1" \
        sortedFastqFile2="$sortedFastqFile2" \
        coreutilsSortFastqPair.sh
    """

}


/** Check whether parameters are correct (names and values)
 *
 * @param parameters
 * @param allowedParameters
 */
void checkParameters(parameters, List<String> allowedParameters) {
    Set<String> unknownParameters = parameters.
            keySet().
            grep {
              !it.contains('-') // Nextflow creates hyphenated versions of camel-cased parameters.
            }.
            minus(allowedParameters)
    if (!unknownParameters.empty) {
        log.error "There are unrecognized parameters: ${unknownParameters}"
        exit(1)
    }
}


String toSortMemoryString(MemoryUnit mem) {
    def splitted = mem.toString().split(" ")
    String size = splitted[0]
    switch(splitted[1]) {
        case "B":
            return size + "b"
            break
        case "KB":
            return size + "k"
            break
        case "MB":
            return size + "m"
            break
        case "GB":
            return size + "g"
            break
        case "PB":
            return size + "p"
            break
        case "EB":
            return size + "e"
            break
        case "ZB":
            return size + "z"
            break
        default:
           throw new RuntimeException("MemoryUnit produced unknown unit in '${mem.toString()}")
    }
}


workflow.onComplete {
    log.info "Success!"
}
