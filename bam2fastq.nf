/**
 *  Author: Philip R. Kensche
 */

/** TODO
 *  - test data to NF
 *  - create container
 *  - run singularity container on LSF cluster
 */

params.bamFiles                    // Comma-separated list of input BAMs
params.outputDir                   // Path to which data should be written. One subdirectory per input BAM.
params.sortFastqs = true           // Whether to sort the output FASTQs.
params.pairedEnd = true            // Whether the BAM files contain paired-end reads.
params.writeUnpairedFastq = false  // Write a file with unpaired reads.
params.excludedFlags = "secondary,supplementary"   // Alignments with these flags are excluded. Comma delimited list (interpreted as bash array) of the following values: secondary, supplementary.
params.checkIntermediateFastqMd5 = true     // While reading in intermediate (yet unsorted) FASTQs, check that the MD5 is the same as in the accompanied '.md5' file. Only available for Picard, as Biobambam does not produce MD5 files for output files.
params.compressIntermediateFastqs = true    // Whether to compress intermediate (yet unsorted) FASTQs.
params.compressor = "pigz.sh"   // Compression binary or script used for (de)compression of sorted output FASTQs. gzip, ${TOOL_PIGZ}.
params.compressorThreads = 4    // Number of threads for compression and decompression by the sortCompressor and compressor. Used by ${TOOL_PIGZ}.
params.sortMemory = "1g"        // Memory used for storing data while sorting. Is passed to the sorting tool and should follow its required syntax. WARNING: Also adapt the job requirements!
params.sortThreads = 4          // The number of parallel threads used for sorting."

params.debug = false

allowedParameters = ['bamFiles', 'outputDir', 'sortFastqs',
                     'compressIntermediateFastqs', 'pairedEnd',
                     'writeUnpairedFastq',
                     'excludedFlags', 'checkIntermediateFastqMd5', 'compressIntermediateFastqs',
                     'compressor', 'compressorThreads', 'sortMemory', 'sortThreads',
                     'debug']

checkParameters(params, allowedParameters)

log.info """
==================================
= Bam2Fastq                      =
==================================
${allowedParameters.collect { "$it = ${params.get(it)}" }.join("\n")}

"""


bamFiles_ch = Channel.
        fromPath(params.bamFiles.split(',') as List<String>,
                 checkIfExists: true)


def bamToFastqCpus(params) {
    Double pairFactor = params.pairedEnd ? 2 : 1
    Double unpairedFastqSummand = params.writeUnpairedFastq ? 1 : 0
    Double checkMd5Summand = params.checkIntermediateFastqMd5 ? 1 : 0
    Double compressIntermediate = params.compressIntermediateFastqs ? 1 : 0
    Double compressThreadsFactor = params.compressorThreads
    return 2
}

def bamToFastqMemory(params) {
    return 15.GB
}

process bamToFastq {
    cpus { bamToFastqCpus(params) }
    memory { bamToFastqMemory(params) }

    publishDir params.outputDir, enabled: !params.sortFastqs

    input:
        file bamFile from bamFiles_ch

    output:
        tuple file(bamFile), file("**/*.fastq.gz") into readsFiles_ch

    shell:
    """
    PICARD_OPTIONS="VALIDATION_STRINGENCY=SILENT CREATE_MD5_FILE=${params.checkIntermediateFastqMd5} USE_JDK_DEFLATER=true USE_JDK_INFLATER=true" \
        pairedEnd="$params.pairedEnd" \
        writeUnpairedFastq="$params.writeUnpairedFastq" \
        excludedFlags="(${params.excludedFlags.split(",").join(" ")})" \
        compressor="$params.compressor" \
        compressorThreads="$params.compressorThreads" \
        compressFastqs="${params.compressIntermediateFastqs || (!params.sortFastqs && params.compressFastqs)}" \
        bamFile="$bamFile" \
        outputPerReadGroup="true" \
        converter="biobambam" \
        outputDir="${bamFile}_fastqs" \
        bam2Fastq.sh
    """

}

// Create two channels of matched paired-end and unmatched or single-end reads, each of tuples of (bam, fastq).
readsFiles_ch.into { readsFilesA_ch; readsFilesB_ch}
pairedFastqs_ch = readsFilesA_ch.flatMap {
    def (bam, fastqs) = it
    fastqs.grep { it.getFileName() =~ /.+_R[12]\.fastq(?:\.[^.]*)$/ }.
            groupBy { fastq -> fastq.getFileName().toString().replaceFirst("_R[12].fastq.gz\$", "") }.
            collect { key, files ->
                assert files.size() == 2
                files.sort()
                [bam, files[0], files[1]]
            }
}

unpairedFastqs_ch = readsFilesB_ch.flatMap {
    def (bam, fastqs) = it
    fastqs.
            grep { it.getFileName() =~ /.+_(U[12]|S)\.fastq(?:\.[^.]*)$/ }.
            collect { [bam, it] }
}


process nameSortUnpairedFastqs {
    cpus params.sortThreads
    memory params.sortMemory

    publishDir params.outputDir

    when:
        params.sortFastqs

    input:
        tuple file(bam), file(fastq) from unpairedFastqs_ch

    output:
        tuple file(bam), file("**/*.sorted.fastq.gz") into sortedUnpairedFastqs_ch

    script:
    bamFileName = bam.getFileName().toString()
    outDir = "${bamFileName}_sorted_fastqs"
    """
    mkdir -p "$outDir"
    compressedInputFastqs="$params.compressIntermediateFastqs" \
        converter="biobambam" \
        compressor="$params.compressor" \
        compressorThreads="$params.compressorThreads" \
        sortThreads="$params.sortThreads" \
        sortMemory="$params.sortMemory" \
        fastqFile="$fastq" \
        sortedFastqFile="${sortedFastqFile(outDir, fastq)}" \
        coreutilsSortFastqSingle.sh
    """

}

process nameSortPairedFastqs {
    cpus params.sortThreads
    memory params.sortMemory

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
    sortedFastqFile1 = outDir + "/" + fastq1.getFileName().toString().replaceFirst(/\.fastq\.gz$/, ".sorted.fastq.gz")
    sortedFastqFile2 = outDir + "/" + fastq2.getFileName().toString().replaceFirst(/\.fastq\.gz$/, ".sorted.fastq.gz")
    """
    mkdir -p "$outDir"
    compressedInputFastqs="$params.compressIntermediateFastqs" \
        converter="biobambam" \
        compressor="$params.compressor" \
        compressorThreads="$params.compressorThreads" \
        sortThreads="$params.sortThreads" \
        sortMemory="$params.sortMemory" \
        fastqFile1="$fastq1" \
        fastqFile2="$fastq2" \
        sortedFastqFile1="${sortedFastqFile(outDir, fastq1)}" \
        sortedFastqFile2="${sortedFastqFile(outDir, fastq2)}" \
        coreutilsSortFastqPair.sh
    """

}

def sortedFastqFile(String outDir, Path unsortedFastq) {
    outDir + "/" + unsortedFastq.getFileName().toString().replaceFirst(/\.fastq\.gz$/, ".sorted.fastq.gz")
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


workflow.onComplete {
    log.info "Success!"
}
