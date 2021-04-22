[![Build Status - Travis](https://travis-ci.org/DKFZ-ODCF/nf-bamtofastq.svg?branch=master)](https://travis-ci.org/DKFZ-ODCF/nf-bamtofastq)

# BamToFastq Nextflow Workflow

Convert BAM files back to FASTQ.

## Quickstart

Provided you have a working [Conda](https://docs.conda.io/en/latest/) installation, you can run the workflow with

```bash
mkdir test_out/
nextflow run main.nf \
    -profile local,conda \
    -ansi-log \
    --input=/path/to/your.bam \
    --outputDir=test_out \
    --sortFastqs=false
```

For each BAM file in the comma-separated `--input` parameter, one directory with FASTQs is created in the `outputDir`. With the `local` profile the processing jobs will be executed locally. The `conda` profile will let Nextflow create a Conda environment from the `task-environment.yml` file. By default the conda environment will be created in the execution directory (see [nextflow.config](https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/nextflow.config)).

## Remarks

  * By default, the workflow sorts FASTQ files by their IDs to avoid e.g. that reads extracted from position-sorted BAMs are fed into the next processing step (possibly re-alignment) in a sorting order that may affect the processing. For instance, keeping position-based sorting order may result in systematic fluctuations of the average insert-size distributions in the FASTQ stream. Note, however, that most jobs of the workflow are actually sorting-jobs -- so you can save a **lot** of computation time, if the input order during alignment does not matter for you. And if you don't worry about such problems during alignment, you may save a lot of additional time during sorting of the already almost-sorted alignment output.
  * Obviously, you can only reconstitute complete original FASTQs (except for order), if the BAM was not filtered in any way, e.g. by removing duplicated reads, read trimming, of if the input file is truncated.
  * Paired-end FASTQs are generated with [biobambam2](https://gitlab.com/german.tischler/biobambam2)'s `bamtofastq`.
  * Sorting is done with the UNIX coreutils tool "sort" in an efficient way (e.g. sorting per read-group; co-sorting of order-matched mate FASTQs).

## Status

Please have a look at the [project board](https://github.com/DKFZ-ODCF/nf-bam2fastq/projects/1) for further information.

## Parameters

### Required parameters

  * `input`: Comma-separated list of input BAM-file paths.
  * `outputDir`: Output directory

### Optional parameters

  * `sortFastqs`: Whether to produce FASTQs in a similar order as in the input BAM (`false`) or sort by name (`true`). Default: `true`. Turning sorting on produces multiple sort-jobs.
  * `excludedFlags`: Comma-separated list of flags to `bamtofastq`'s `exclude` parameter. Default: "secondary,supplementary". If you have complete, BWA-aligned BAM files then exactly the reads of the input FASTQ are reproduced. For other aligners you need to check yourself, what are the optimal parameters.
  * Trading memory vs. I/O
    * `sortMemory`: Memory used for sorting. Too large values are useless, unless you have enough memory to sort completely in-memory. Default: "100 MB".
    * `sortThreads`: Number of threads used for sorting. Default: 4.
    * `compressIntermediateFastqs`: Whether to compress FASTQs produced by `bamtofastq` when doing subsequent sorting. Default: true. This is only relevant if `sortFastq=true`.
    * `compressorThreads`: The compressor (pigz) can use multiple threads. Default: 4. If you set this value to zero, then no additional CPUs are required by Nextflow to be present. However, a single thread still will be used by pigz.

### Output

In the `outputDir` the workflow creates a sub-directory for each input BAM file. These are named like the BAM with one of the suffixes `_fastqs` or `_sorted_fastqs` added, dependent on the value for `sortFastqs` you selected. Each of these directories contains a set of FASTQ files, whose names follow the pattern

```
${readGroupName}_${readType}.fastq.gz
```

The read-group name is the name of the "@RG" attribute the reads in the file were found to be connected to. For reads in your BAM that don't have a read-group assigned the "default" read-group is used. Consequently, your BAMs should not contain a read-group "default"! The read-type is one of the following:

  * R1, R2: paired-reads 1 or 2
  * U1, U2: orphaned reads, i.e. first or second reads marked as paired but with a missing mate.
  * S: single-end reads

These files are all always produced, independent of whether your data is actually single-end or paired-end. If no reads of any of these groups are present in the input BAM file, empty compressed files are produced. Note further that these files are produced for each read-group in your input BAM, plus the "default" read-group. If you have a BAM in which none of the reads are assigned to a read-group, then all reads can be found in the "default" read-group.

## Using Containers

Sometimes, it is easiest to run the workflow in Docker or Singularity containers. We provide ready-made containers at [Github Container Registry](https://github.com/orgs/DKFZ-ODCF/packages).

### Run with Docker

You can run the workflow locally with Docker you can do e.g.

```bash
nextflow run main.nf \
    -profile local,docker \
    -ansi-log \
    --input=test/test1_paired.bam,test/test1_unpaired.bam \
    --outputDir=test_out \
    --sortFastqs=true
```

This will automatically download the container from [Github Container Registry](https://github.com/orgs/DKFZ-ODCF/packages).

### Run with Singularity

To run the workflow with [Singularity](https://singularity.lbl.gov/), convert the Docker container to Singularity:

```bash
# Convert the Docker image to Singularity.
# Note that the image is stored in the current directory where it is then also expected by the "singularity" profile.
singularity \
  build \
  nf-bam2fastq.sif \
  docker-daemon://ghcr.io/dkfz-odcf/nf-bam2fastq:latest

# Run with the "singularity" profile
nextflow run main.nf \
    -profile local,singularity \
    -ansi-log \
    --input=test/test1_paired.bam,test/test1_unpaired.bam \
    --outputDir=test_out \
    --sortFastqs=true
```

## Environment and Execution

[Nextflow](https://www.nextflow.io/docs/latest/config.html#config-profiles)'s `-profile` parameter allows setting technical options for executing the workflow. You have already seen some of the profiles and that these can be combined. We conceptually separated the predefined profiles into two types -- those concerning the "environment" and those for selecting the "executor".

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
nextflow run main.nf \
    -profile lsf,singularity \
    -ansi-log \
    --input=test/test1_paired.bam,test/test1_unpaired.bam \
    --outputDir=test_out \
    --sortFastqs=true
```

Please refer to the [Nextflow documentation](https://www.nextflow.io/docs/latest/executor.html) for defining other executors. Note that environments and executors cannot arbitrarily be combined. For instance, your LSF administrators may not allow Docker to be executed by normal users.

## Origins

The workflow is a port of the Roddy-based [https://github.com/TheRoddyWMS/BamToFastqPlugin](BamToFastqPlugin). Compared to the Roddy-workflow, some problems with the execution of parallel processing, resulting in potential errors, have been fixed.

## Development

The integration tests can be run with

```bash
test/test1.sh test-results/ $profile
```

This will create a test Conda environment in `test-results/nextflowEnv` and then run the tests. For the tests itself you can use a local Conda environment or a Docker container, dependent on whether you set `$profile` to "conda" or "docker", respectively. These integration tests are also run in Travis CI.

## Manual container release

The container includes a Conda installation and is pretty big. It should only be released if its content is actually changed. For instance, it would be perfectly fine to have a workflow version 1.6.5 but still refer to an old container for 1.2.7.

This is an outline of the procedure to release the container to [Github Container Registry](https://github.com/orgs/DKFZ-ODCF/packages):

1. Set the version that you want to release as variable. For the later commands you can set the Bash variable
   ```bash
   versionTag=1.0.0
   ```
2. Build the container.
  ```bash
   docker \
      build \
      -t ghcr.io/dkfz-odcf/nf-bam2fastq:$versionTag \
      --build-arg HTTP_PROXY=$HTTP_PROXY \
      --build-arg HTTPS_PROXY=$HTTPS_PROXY \
      ./
   ```
3. Edit the version-tag for the docker container in the "docker"-profile in the nextflow.config to match `$versionTag`. 
4. Run the integration test with the new container
   ```bash
   test/test1.sh docker-test docker-test/test-environment docker
   ```
5. If the test succeeds, push the container to Github container registry. Set the CR_PAT variable to your personal access token (PAT):
   ```bash
   echo $CR_PAT | docker login ghcr.io -u vinjana --password-stdin
   docker image push ghcr.io/dkfz-odcf/nf-bam2fastq:$versionTag
   ```

## Release Notes

* 1.0.0 (?., 2021)

  * Adapted resource expressions to conservative values.
  * Reduced resources for integration tests (threads and memory).
  * Bugfix: Set sorting memory.
  * Update to biobambam 2.0.179 to fix its orphaned second-reads bug
  * Changes to make workflow more nf-core conformant  
    * Rename `bam2fastq.nf` to `main.nf` (similar to nf-core projects)
    * Rename `--bamFiles` to `--input` parameter

* 0.2.0 (November 17., 2020)

  * Added integration tests
  * CI via travis-ci
  * **NOTE**: Due to a bug in the used biobambam version 2.0.87 the orphaned second-read file is not written. See [here](https://gitlab.com/german.tischler/biobambam2/-/issues/94). An update to 2.0.177+ is necessary. 

* 0.1.0 (August 26., 2020)

  * Working but not deeply tested base version 


## License & Contributors

See [LICENSE.txt](LICENSE.txt) and [CONTRIBUTORS](CONTRIBUTORS).
