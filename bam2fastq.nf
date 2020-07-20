/**
 *  Author: Philip R. Kensche
 */

/** TODO
 *  - test data to NF
 *  - run natively (w/o container)
 *  - create container
 *  - run singularity container on LSF cluster
 *  - rename Roddy variables
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


Channel.fromPath(params.bamFiles.split(',') as List<String>, checkIfExists: true).
        set { bamFiles_ch }



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
        file "**/*.fastq.gz" into readsFiles_ch

    shell:
    """
    PICARD_OPTIONS="VALIDATION_STRINGENCY=SILENT CREATE_MD5_FILE=${params.checkIntermediateFastqMd5} USE_JDK_DEFLATER=true USE_JDK_INFLATER=true" \
        pairedEnd="$params.pairedEnd" \
        outputPerReadGroup="true" \
        writeUnpairedFastq="$params.writeUnpairedFastq" \
        excludedFlags="(${params.excludedFlags.split(",").join(" ")})" \
        compressFastqs="${params.compressIntermediateFastqs || (!params.sortFastqs && params.compressFastqs)}" \
        converter="biobambam" \
        bamFile="$bamFile" \
        bam2Fastq.sh
    """

}

readsFiles_ch.view()


//process nameSortFastqs {
//    cpus params.sortingThreads
//    memory params.sortingMemory
//
//    when:
//        sortFastqs
//
//    publishDir params.outputDir
//
//    input:
//
//    output:
//
//    script:
//       compressedInputFastqs=$params.compressIntermediateFastqs
//
//}


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
    log.info "Done!"
}