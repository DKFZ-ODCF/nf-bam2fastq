/**
 *  Copyright (c) 2021 DKFZ.
 *
 *  Distributed under the MIT License (license terms are at https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/LICENSE.txt).
 *
 *  Author: Philip R. Kensche
 */

/** Comma-separated list of input BAMs */
params.input

/** Path to which data should be written. One subdirectory per input BAM. */
params.outputDir

/** Whether to sort the output FASTQs. */
params.sortFastqs = true

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
params.sortMemory = "1 GB"

/** The number of parallel threads used for sorting. */
params.sortThreads = 4

/** Produce more output for debugging. */
params.debug = false

/** The Nextflow publish mode. See https://www.nextflow.io/docs/latest/process.html#publishdir */
params.publishMode = "rellink"


/** Parameter checking and casting code */
allowedParameters = ['input', 'outputDir',
                     'sortFastqs', 'sortMemory', 'sortThreads',
                     'compressIntermediateFastqs', 'compressorThreads',
                     'excludedFlags', 'checkIntermediateFastqMd5',
                     'debug', 'publishMode']

checkParameters(params, allowedParameters)

// The sorting memory is used as MemoryUnit in the code below.
sortMemory = new MemoryUnit(params.sortMemory)

/** See https://www.nextflow.io/docs/latest/process.html#publishdir */
enum PublishMode {
    symlink, // Absolute symbolic link in the published directory for each process output file.
    rellink, // Relative symbolic link in the published directory for each process output file.
    link,    // Hard link in the published directory for each process output file.
    copy,    // Copies the output files into the published directory.
    copyNoFollow, // Copies the output files into the published directory without following
                  // symlinks ie. copies the links themselves.
    move;     // Moves the output files into the published directory. Note: this is only supposed
              // to be used for a terminating process i.e. a process whose output is not consumed
              // by any other downstream process.

    static PublishMode fromString(String str) throws IllegalArgumentException {
        return str.toLowerCase() as PublishMode
    }
}

publishMode = PublishMode.fromString(params.publishMode)


log.info """
==================================
= nf-bam2fastq                   =
==================================
${allowedParameters.collect { "$it = ${params.get(it)}" }.join("\n")}

"""


String fastqSuffix(Boolean compressed) {
    if (compressed)
        return "fastq.gz"
    else
        return "fastq"
}


String sortedFastqFile(String outDir, Path unsortedFastq, Boolean compressed) {
    String result = outDir + "/" + unsortedFastq.getFileName().toString().replaceFirst(/\.fastq(?:\.gz)?$/, ".sorted.fastq")
    if (compressed)
        return result + ".gz"
    else
        return result
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

/** Workflow supplementary code */

/** Convert the configured sort memory from Nextflow's MemoryUnit to a string for the `sort` tool.
 *
 *  @param mem
 * */
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

/** The actual workflow */
bamFiles_ch = Channel.
        fromPath(params.input.split(',') as List<String>,
                 checkIfExists: true)


Boolean compressBamToFastqOutput = params.sortFastqs ? params.compressIntermediateFastqs : true

process bamToFastq {
    // Just bamtofastq
    cpus 1
    // The biobambam paper states something like 133 MB.
    memory 1.GB
    time { 48.hours * 2**(task.attempt - 1) }
    maxRetries 2

    publishDir params.outputDir, enabled: !params.sortFastqs, mode: publishMode.toString()

    input:
        file bamFile from bamFiles_ch

    output:
        tuple file(bamFile), file("**/*.${fastqSuffix(compressBamToFastqOutput)}") into readsFiles_ch

    shell:
    """
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


// Unpaired FASTQs are unmatched or orphaned paired-reads (1 or 2) and singletons, i.e. unpaired reads.
unpairedFastqs_ch = readsFilesB_ch.flatMap {
    def (bam, fastqs) = it
    fastqs.
            grep { it.getFileName() =~ /.+_(U[12]|S)\.fastq(?:\.[^.]*)?$/ }.
            collect { [bam, it] }
}


process nameSortUnpairedFastqs {
    cpus { params.sortThreads + (params.compressIntermediateFastqs ? params.compressorThreads : 0 )  }
    memory { (sortMemory + 100.MB) * params.sortThreads * 1.2 }
    // TODO Make runtime dependent on file-size.
    time { 24.hour * 2**(task.attempt - 1) }
    maxRetries 2

    publishDir params.outputDir, mode: publishMode.toString()

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
        sortMemory="${toSortMemoryString(sortMemory)}"	\
        fastqFile="$fastq" \
        sortedFastqFile="$sortedFastqFile" \
        coreutilsSortFastqSingle.sh
    """

}


process nameSortPairedFastqs {
    cpus { params.sortThreads + (params.compressIntermediateFastqs ? params.compressorThreads * 2 : 0) }
    memory { (sortMemory + 100.MB) * params.sortThreads * 1.2 }
    // TODO Make runtime dependent on file-size.
    time { 24.hours * 2**(task.attempt - 1) }
    maxRetries 2

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
        sortMemory="${toSortMemoryString(sortMemory)}"	\
        fastqFile1="$fastq1" \
        fastqFile2="$fastq2" \
        sortedFastqFile1="$sortedFastqFile1" \
        sortedFastqFile2="$sortedFastqFile2" \
        coreutilsSortFastqPair.sh
    """

}


workflow.onComplete {
    println "Workflow run $workflow.runName completed at $workflow.complete with status " +
            "${ workflow.success ? 'success' : 'failure' }"
}
