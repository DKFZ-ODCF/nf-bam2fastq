# BamToFastq Nexflow Workflow

Convert BAM files back to FASTQ.

## Quickstart

Provided you have a working Conda installation and two BAM files, you can run workflow with

```bash
mkdir test_out/
nextflow run bam2fastq.nf \
    -profile local,conda \
    -ansi-log \
    --bamFileList=/path/to/your.bam \
    --outputDir=test_out \
    --sortFastqs=false
```

For each BAM file in the comma-separated `--bamFileList` parameter, one directory with FASTQs is created in the `outputDir`. With the `local` profile the processing jobs will be executed locally. The `conda` profile will let Nextflow create a Conda environment from the `./task-environment.yml` file (by default in the `work/` directory.

## Remarks

  * By default, the workflow sorts FASTQ files by their IDs to avoid e.g. that reads extracted from position-sorted BAMs are fed into the next processing step (possibly re-alignment) in a sorting order that may affect the processing. For instance, keeping position-based sorting order may result in systematic fluctuations of the average insert-size distributions in the FASTQ stream. Note, however, that most jobs of the workflow are actually sorting-jobs -- so you can save a lot of computation time, if the input order during alignment does not matter for you.
  * Obviously, you can only reconstitute complete original FASTQs (except for order), if the BAM was not filtered in any way, e.g. by removing duplicated reads or read trimming.  
  * Paired-end FASTQs are generated with biobambam2's `bamtofastq`.
  * Sorting is done with the UNIX coreutils tool "sort" in an efficient way (e.g. sorting per read-group; co-sorting of order-matched mate FASTQs).

## Status

Please have a look at the [project board](projects/1) for further information.

## Parameters

### Required parameters

  * `bamFileList`: Comma-separated list of input BAM-file paths.
  * `outputDir`: Output directory

### Optional parameters

  * `sortFastqs`: Whether to produce FASTQs in a similar order as in the input BAM (`false`) or sort by name (`true`). Default: `true`. Turning sorting on produces multiple sort-jobs.
  * `pairedEnd`: Data is paired-end (`true`) or single-end (`false`). Default: `true`
  * `writeUnpairedFastqs`: Reads may have lost their mate, e.g. because of filtering or truncation of the BAM. By default, we let `bamtofastq` write these reads to files marked with a "_U{1,2}.fastq.gz" suffix.
  * `excludedFlags`: Comma-separated list of flags to `bamtofastq`'s `exclude` parameter. Default: "secondary,supplementary". If you have complete, BWA-aligned BAM files then exactly the reads of the input FASTQ are reproduced. For other aligners you need to check yourself, what are the optimal parameters.
  * `outputPerReadGroup`: Whether reads from different read-groups should be written to different files. Default: true. Writing read groups into separate files reduces the time needed for sorting.
  Default: `true`.
  * Trading memory vs. IO
    * `sortMemory`: Memory used for sorting. Too large values are useless, unless you have enough memory to sort completely in-memory. Default: 100 MB.
    * `sortThreads`: Number of threads used for sorting. Default: 4.
    * `compressIntermediateFastqs`: Whether to compress FASTQs produced by `bamtofastq` when doing subsequent sorting. Default: true. This is only relevant if `sortFastq=true`.
    * `compressorThreads`: The compressor (pigz) can use multiple threads for compression. Default: 4

## More Examples

### Run with Docker

A Dockerfile is provided. You will first have to build the container with

```bash
cd nf-bam2fastq
docker build \
    --rm \
    --build-arg http_proxy=$HTTP_PROXY \
    --build-arg https_proxy=$HTTPS_PROXY \
    -t \
    nf-bam2fastq \
    ./
```

Then to run the workflow locally with Docker you can do e.g.

```bash
nextflow run bam2fastq.nf \
    -profile local,docker \
    -ansi-log \
    --bamFiles=test/test1.bam,test/test2.bam \
    --outputDir=test_out \
    --sortFastqs=true
```

### Run with Singularity

To run the workflow with singularity, convert the previously build Docker container to Singularity (no native Singularity container, yet):

```bash
# Convert the Docker image to Singularity
singularity build nf-bam2fastq.sif docker-daemon://nf-bam2fastq:latest

# Run with the singularity profile
nextflow run bam2fastq.nf \
    -profile local,singularity \
    -ansi-log \
    --bamFiles=test/test1.bam,test/test2.bam \
    --outputDir=test_out \
    --sortFastqs=true
```

## Environment and Execution

[Nextflow](https://www.nextflow.io/docs/latest/config.html#config-profiles)'s `-profile` parameter allows settinng technical options for executing the workflow. You have already seen some of the profiles and that these can be combined. We conceptually separated the predefined profiles into two types, those concerning the "environment" and those for selecting the "executor".

The following "environment" profiles that define which environment will be used for executing the jobs are predefined in the `nextflow.config`:
  * conda
  * docker
  * singularity
  * dkfzModules: This environment uses the environment modules available in the DKFZ Cluster.

Currently, there are only two "executor" profiles that define the job execution method. These are
  * local: Just execute the jobs locally on the system that executes Nextflow.
  * lsf: Submit the jobs to an LSF cluster. Nextflow must be running on a cluster node on which `bsub` is available.

Here another example, if you want to run the workflow as Singularity containers in an LSF cluster:

```bash
nextflow run bam2fastq.nf \
    -profile lsf,singularity \
    -ansi-log \
    --bamFiles=test/test1.bam,test/test2.bam \
    --outputDir=test_out \
    --sortFastqs=true
```

Please refer to the [Nextflow documentation](https://www.nextflow.io/docs/latest/executor.html) for defining other executors. Note that environments and executors cannot arbitrarily be combined. For instance, your LSF administrators may not allow Docker to be executed by normal users.

## Origins

The workflow is a port of the Roddy-based [https://github.com/TheRoddyWMS/BamToFastqPlugin](BamToFastqPlugin). Compared to the Roddy-workflow, some problems with the execution of parallel processing, resulting in potential errors, have been fixed.

## License & Contributors

See [LICENSE](LICENSE) and [CONTRIBUTORS](CONTRIBUTORS).
