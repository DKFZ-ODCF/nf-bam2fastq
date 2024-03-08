[![Build Status - CircleCI](https://circleci.com/gh/DKFZ-ODCF/nf-bam2fastq/tree/master.svg?style=svg)](https://circleci.com/gh/DKFZ-ODCF/nf-bam2fastq/tree/master)

# BamToFastq Nextflow Workflow

Convert BAM files back to FASTQ.

## Quickstart with Docker

Dependent on the version of the workflow that you want to run it might not be possible to re-build the Conda environment. Therefore, to guarantee reproducibility we create [container images](https://github.com/orgs/DKFZ-ODCF/packages) of the task environment.

For instance, if you want to run the workflow locally with Docker you can do e.g.

```bash
nextflow run main.nf \
    -profile local,docker \
    -ansi-log \
    --input=integration-tests/test1_paired.bam,integration-tests/test1_unpaired.bam \
    --outputDir=test_out \
    --sortFastqs=true
```

## Quickstart with Singularity

In your cluster, you may not have access to Docker. In this situation you can use [Singularity](https://singularity.lbl.gov/), if it is installed in your cluster. Note that unfortunately, Nextflow will fail to convert the Docker image into a Singularity image, unless Docker is available. But you can get the Singularity image yourself:

You can run the workflow with the "singularity" profile, e.g. on an LSF cluster:

```bash
nextflow run $repoDir/main.nf \
 -profile lsf,singularity \
 --input=$repoDir/integration-tests/test1_paired.bam,$repoDir/integration-tests/test1_unpaired.bam \
 --outputDir=test_out \
 --sortFastqs=true
```

Nextflow will automatically pull the Docker image, convert it into a Singularity image, put it at `$repoDir/cache/singularity/ghcr.io-dkfz-odcf-nf-bam2fastq-$containerVersion.img`, and then run the workflow.

> WARNING: Downloading the cached container is probably *not* concurrency-safe. If you run multiple workflows at the same time, all of them trying to cache the Singularity container, you will probably end up with a mess. In that case, download the container manually with following command to pull the container:
> ```bash
>  containerVersion=1.3.0
>  repoDir=/path/to/nf-bam2fastq
>   
>  singularity build \
>    "$repoDir/cache/singularity/ghcr.io-dkfz-odcf-nf-bam2fastq-$containerVersion.img" \
>    "docker://ghcr.io/dkfz-odcf/nf-bam2fastq:$containerVersion"
>  ```

## Quickstart with Conda

> NOTE: Conda is a decent tool for building containers, although these containers tend to be rather big. However, we do *not* recommend you use Conda for reproducibly running workflows. The Conda solution proposed here really is mostly for development. We will not give support for this. 

We do not recommend Conda for running the workflow. It may happen that packages are not available in any channels anymore and that the environment is broken. For reproducible research, please use containers.

Provided you have a working [Conda](https://docs.conda.io/en/latest/) installation, you can run the workflow with

```bash
mkdir test_out/
nextflow run main.nf \
    -profile local,conda \
    --input=/path/to/your.bam \
    --outputDir=test_out \
    --sortFastqs=false
```

For each BAM file in the comma-separated `--input` parameter, one directory with FASTQs is created in the `outputDir`. With the `local` profile the processing jobs will be executed locally. The `conda` profile will let Nextflow create a Conda environment from the `task-environment.yml` file. By default, the conda environment will be created in the source directory of the workflow (see [nextflow.config](https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/nextflow.config)).


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
  * `publishMode`: Nextflow's [publish mode](https://www.nextflow.io/docs/latest/process.html#publishdir). Allowed values are `symlink` , `rellink`, `link`, `copy`, `copyNoFollow`, `move`. Default is `rellink`, which produces relative links from the publish dir (in the `outputDir`) to the directories in the `work/` directory. This is to support an invocation of Nextflow in a "run" directory in which all files (symlinked input data, output data, logs) are stored together (e.g. with `nextflow run --outputDir ./`).
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

Note that Nextflow creates the `work/` directory, the `.nextflow/` directory, and the `.nextflow.log*` files in the directory in which it is executed.

#### Example

For instance, the output for the two test BAMs in the `integration-tests/reference/` directory would look as follows. Note that these files contain multiple read groups:

```bash
$ samtools view -H | grep -P '^@RG'
@RG     ID:run4_gerald_D1VCPACXX_4      LB:tumor_gms    PL:ILLUMINA     SM:sample_tumor_gms
@RG     ID:run5_gerald_D1VCPACXX_5      LB:tumor_gms    PL:ILLUMINA     SM:sample_tumor_gms
@RG     ID:run1_gerald_D1VCPACXX_1      LB:tumor_gms    PL:ILLUMINA     SM:sample_tumor_gms
@RG     ID:run3_gerald_D1VCPACXX_3      LB:tumor_gms    PL:ILLUMINA     SM:sample_tumor_gms
@RG     ID:run2_gerald_D1VCPACXX_2      LB:tumor_gms    PL:ILLUMINA     SM:sample_tumor_gms
```

Consequently, there will be a lot of output files:

```bash
test1_paired.bam
test1_paired.bam_fastqs/
├── default_R1.fastq.gz
├── default_R2.fastq.gz
├── default_S.fastq.gz
├── default_U1.fastq.gz
├── default_U2.fastq.gz
├── run1_gerald_D1VCPACXX_1_R1.fastq.gz
├── run1_gerald_D1VCPACXX_1_R2.fastq.gz
├── run1_gerald_D1VCPACXX_1_S.fastq.gz
├── run1_gerald_D1VCPACXX_1_U1.fastq.gz
├── run1_gerald_D1VCPACXX_1_U2.fastq.gz
├── run2_gerald_D1VCPACXX_2_R1.fastq.gz
├── run2_gerald_D1VCPACXX_2_R2.fastq.gz
├── run2_gerald_D1VCPACXX_2_S.fastq.gz
├── run2_gerald_D1VCPACXX_2_U1.fastq.gz
├── run2_gerald_D1VCPACXX_2_U2.fastq.gz
├── run3_gerald_D1VCPACXX_3_R1.fastq.gz
├── run3_gerald_D1VCPACXX_3_R2.fastq.gz
├── run3_gerald_D1VCPACXX_3_S.fastq.gz
├── run3_gerald_D1VCPACXX_3_U1.fastq.gz
├── run3_gerald_D1VCPACXX_3_U2.fastq.gz
├── run4_gerald_D1VCPACXX_4_R1.fastq.gz
├── run4_gerald_D1VCPACXX_4_R2.fastq.gz
├── run4_gerald_D1VCPACXX_4_S.fastq.gz
├── run4_gerald_D1VCPACXX_4_U1.fastq.gz
├── run4_gerald_D1VCPACXX_4_U2.fastq.gz
├── run5_gerald_D1VCPACXX_5_R1.fastq.gz
├── run5_gerald_D1VCPACXX_5_R2.fastq.gz
├── run5_gerald_D1VCPACXX_5_S.fastq.gz
├── run5_gerald_D1VCPACXX_5_U1.fastq.gz
└── run5_gerald_D1VCPACXX_5_U2.fastq.gz
test1_paired.bam_sorted_fastqs/
├── default_R1.sorted.fastq.gz
├── default_R2.sorted.fastq.gz
├── default_S.sorted.fastq.gz
├── default_U1.sorted.fastq.gz
├── default_U2.sorted.fastq.gz
├── run1_gerald_D1VCPACXX_1_R1.sorted.fastq.gz
├── run1_gerald_D1VCPACXX_1_R2.sorted.fastq.gz
├── run1_gerald_D1VCPACXX_1_S.sorted.fastq.gz
├── run1_gerald_D1VCPACXX_1_U1.sorted.fastq.gz
├── run1_gerald_D1VCPACXX_1_U2.sorted.fastq.gz
├── run2_gerald_D1VCPACXX_2_R1.sorted.fastq.gz
├── run2_gerald_D1VCPACXX_2_R2.sorted.fastq.gz
├── run2_gerald_D1VCPACXX_2_S.sorted.fastq.gz
├── run2_gerald_D1VCPACXX_2_U1.sorted.fastq.gz
├── run2_gerald_D1VCPACXX_2_U2.sorted.fastq.gz
├── run3_gerald_D1VCPACXX_3_R1.sorted.fastq.gz
├── run3_gerald_D1VCPACXX_3_R2.sorted.fastq.gz
├── run3_gerald_D1VCPACXX_3_S.sorted.fastq.gz
├── run3_gerald_D1VCPACXX_3_U1.sorted.fastq.gz
├── run3_gerald_D1VCPACXX_3_U2.sorted.fastq.gz
├── run4_gerald_D1VCPACXX_4_R1.sorted.fastq.gz
├── run4_gerald_D1VCPACXX_4_R2.sorted.fastq.gz
├── run4_gerald_D1VCPACXX_4_S.sorted.fastq.gz
├── run4_gerald_D1VCPACXX_4_U1.sorted.fastq.gz
├── run4_gerald_D1VCPACXX_4_U2.sorted.fastq.gz
├── run5_gerald_D1VCPACXX_5_R1.sorted.fastq.gz
├── run5_gerald_D1VCPACXX_5_R2.sorted.fastq.gz
├── run5_gerald_D1VCPACXX_5_S.sorted.fastq.gz
├── run5_gerald_D1VCPACXX_5_U1.sorted.fastq.gz
└── run5_gerald_D1VCPACXX_5_U2.sorted.fastq.gz
test1_unpaired.bam
test1_unpaired.bam_fastqs/
├── default_R1.fastq.gz
├── default_R2.fastq.gz
├── default_S.fastq.gz
├── default_U1.fastq.gz
├── default_U2.fastq.gz
├── run1_gerald_D1VCPACXX_1_R1.fastq.gz
├── run1_gerald_D1VCPACXX_1_R2.fastq.gz
├── run1_gerald_D1VCPACXX_1_S.fastq.gz
├── run1_gerald_D1VCPACXX_1_U1.fastq.gz
├── run1_gerald_D1VCPACXX_1_U2.fastq.gz
├── run2_gerald_D1VCPACXX_2_R1.fastq.gz
├── run2_gerald_D1VCPACXX_2_R2.fastq.gz
├── run2_gerald_D1VCPACXX_2_S.fastq.gz
├── run2_gerald_D1VCPACXX_2_U1.fastq.gz
├── run2_gerald_D1VCPACXX_2_U2.fastq.gz
├── run3_gerald_D1VCPACXX_3_R1.fastq.gz
├── run3_gerald_D1VCPACXX_3_R2.fastq.gz
├── run3_gerald_D1VCPACXX_3_S.fastq.gz
├── run3_gerald_D1VCPACXX_3_U1.fastq.gz
├── run3_gerald_D1VCPACXX_3_U2.fastq.gz
├── run4_gerald_D1VCPACXX_4_R1.fastq.gz
├── run4_gerald_D1VCPACXX_4_R2.fastq.gz
├── run4_gerald_D1VCPACXX_4_S.fastq.gz
├── run4_gerald_D1VCPACXX_4_U1.fastq.gz
├── run4_gerald_D1VCPACXX_4_U2.fastq.gz
├── run5_gerald_D1VCPACXX_5_R1.fastq.gz
├── run5_gerald_D1VCPACXX_5_R2.fastq.gz
├── run5_gerald_D1VCPACXX_5_S.fastq.gz
├── run5_gerald_D1VCPACXX_5_U1.fastq.gz
└── run5_gerald_D1VCPACXX_5_U2.fastq.gz
test1_unpaired.bam_sorted_fastqs/
├── default_R1.sorted.fastq.gz
├── default_R2.sorted.fastq.gz
├── default_S.sorted.fastq.gz
├── default_U1.sorted.fastq.gz
├── default_U2.sorted.fastq.gz
├── run1_gerald_D1VCPACXX_1_R1.sorted.fastq.gz
├── run1_gerald_D1VCPACXX_1_R2.sorted.fastq.gz
├── run1_gerald_D1VCPACXX_1_S.sorted.fastq.gz
├── run1_gerald_D1VCPACXX_1_U1.sorted.fastq.gz
├── run1_gerald_D1VCPACXX_1_U2.sorted.fastq.gz
├── run2_gerald_D1VCPACXX_2_R1.sorted.fastq.gz
├── run2_gerald_D1VCPACXX_2_R2.sorted.fastq.gz
├── run2_gerald_D1VCPACXX_2_S.sorted.fastq.gz
├── run2_gerald_D1VCPACXX_2_U1.sorted.fastq.gz
├── run2_gerald_D1VCPACXX_2_U2.sorted.fastq.gz
├── run3_gerald_D1VCPACXX_3_R1.sorted.fastq.gz
├── run3_gerald_D1VCPACXX_3_R2.sorted.fastq.gz
├── run3_gerald_D1VCPACXX_3_S.sorted.fastq.gz
├── run3_gerald_D1VCPACXX_3_U1.sorted.fastq.gz
├── run3_gerald_D1VCPACXX_3_U2.sorted.fastq.gz
├── run4_gerald_D1VCPACXX_4_R1.sorted.fastq.gz
├── run4_gerald_D1VCPACXX_4_R2.sorted.fastq.gz
├── run4_gerald_D1VCPACXX_4_S.sorted.fastq.gz
├── run4_gerald_D1VCPACXX_4_U1.sorted.fastq.gz
├── run4_gerald_D1VCPACXX_4_U2.sorted.fastq.gz
├── run5_gerald_D1VCPACXX_5_R1.sorted.fastq.gz
├── run5_gerald_D1VCPACXX_5_R2.sorted.fastq.gz
├── run5_gerald_D1VCPACXX_5_S.sorted.fastq.gz
├── run5_gerald_D1VCPACXX_5_U1.sorted.fastq.gz
└── run5_gerald_D1VCPACXX_5_U2.sorted.fastq.gz
```

## Environment and Execution

[Nextflow](https://www.nextflow.io/docs/latest/config.html#config-profiles)'s `-profile` parameter allows setting technical options for executing the workflow. You have already seen some of the profiles and that these can be combined. We conceptually separated the predefined profiles into two types -- those concerning the "environment" and those for selecting the "executor".

The following "environment" profiles that define which environment will be used for executing the jobs are predefined in the `nextflow.config`:
* conda
* mamba
* docker
* singularity

Currently, there are only two "executor" profiles that define the job execution method. These are
* local: Just execute the jobs locally on the system that executes Nextflow.
* lsf: Submit the jobs to an LSF cluster. Nextflow must be running on a cluster node on which `bsub` is available.

Please refer to the [Nextflow documentation](https://www.nextflow.io/docs/latest/executor.html) for defining other executors. Note that environments and executors cannot arbitrarily be combined. For instance, your LSF administrators may not allow Docker to be executed by normal users.

### Location of Environments

By default, the Conda environments of the jobs as well as the Singularity containers are stored in subdirectories of the `cache/` subdirectory of the workflows installation directory (a.k.a `projectDir` by Nextflow). E.g. to use the Singularity container you can install the container as follows

```bash
cd $workflowRepoDir
# Refer to the nextflow.config for the name of the Singularity image.
singularity build \
  cache/singularity/ghcr.io-dkfz-odcf-nf-bam2fastq-$containerVersion.img \
  container-specs/Singularity.def
  
# Test your container
integration-tests/run.sh singularity test-results/ nextflowEnv/
```

This is suited for either a user-specific installation or for a centralized installation for which the environments should be shared for all users. Please refer to the `nextflow.config` or the `NXF_*_CACHEDIR` environment variables to change this default (see [here](https://www.nextflow.io/docs/latest/config.html#environment-variables). 

Make sure your users have read and execute permissions on the directories and read permissions on the files in the shared environment directories. Set `NXF_CONDA_CACHEDIR` to an absolute path to avoid "Not a conda environment: path/to/env/nf-bam2fastq-3e98300235b5aed9f3835e00669fb59f" errors.

## Development

The integration tests can be run with

```bash
integration-tests/run.sh $profile test-results/
```

This will create a test Conda environment in `./nextflowEnv` and then run the tests. For the tests themselves you can use a local Conda environment or a Docker container, dependent on whether you set `$profile` to "conda" or "docker", respectively. These integration tests are also run in Travis CI.

### Continuous Delivery

For all commits with a tag that follows the pattern `\d+\.\d+\.\d+` the job containers are automatically pushed to [Github Container Registry](https://github.com/orgs/DKFZ-ODCF/packages) of the "ODCF" organization. Version tags should only be added to commits on the `master` branch, although currently no automatic rule enforces this.

### Manual container release

The container includes a Conda installation and is pretty big. It should only be released if its content is actually changed. For instance, it would be perfectly fine to have a workflow version 1.6.5 but still refer to an old container for 1.2.7.

This is an outline of the procedure to release the container to [Github Container Registry](https://github.com/orgs/DKFZ-ODCF/packages):

1. Set the version that you want to release as variable. For the later commands you can set the Bash variable
   ```bash
   containerVersion=1.3.0
   ```
2. Build the container.
   ```bash
   docker \
      build \
      -t ghcr.io/dkfz-odcf/nf-bam2fastq:$containerVersion \
      --build-arg HTTP_PROXY=$HTTP_PROXY \
      --build-arg HTTPS_PROXY=$HTTPS_PROXY \
      -f container-specs/Dockerfile \
      ./
   ```
3. Edit the version-tag for the docker container in the "docker"-profile in the `nextflow.config` to match `$containerVersion`.
4. Run the integration test with the new container
   ```bash
   integration-tests/run.sh docker docker-test-results/
   ```
5. If the test succeeds, push the container to Github container registry. Set the CR_PAT variable to your personal access token (PAT):
   ```bash
   echo $CR_PAT | docker login ghcr.io -u vinjana --password-stdin
   docker image push ghcr.io/dkfz-odcf/nf-bam2fastq:$containerVersion
   ```

## Release Notes

* 1.3.0 (March, 2024)
  * Minor: Let Nextflow automatically create the cached Singularity image.
    > NOTE: The cached image name was changed to Nextflow's default name.
  * Patch: Reuse to the simpler Dockerfile that is also used in the [nf-seq-qc](https://gitlab.com/one-touch-pipeline/workflows/nf-seq-qc) and [nf-seq-convert](https://gitlab.com/one-touch-pipeline/workflows/nf-seq-convert) workflows.
  * Patch: Bumped Dockerfile base image to miniconda3:4.12.0.
  * Patch: Bumped minimum Nextflow to 23.10.1. Version 22 uses `singularity exec`, while 23 uses `singularity run`, which impacts process isolation.
  * Patch: Added a `Singularity.def`, in case the automatic conversion by Nextflow does not work.
  * Patch: Mention Conda only for development in `README.md`. Otherwise, it should not be used.
  * Patch: Test-script now implements a simple backwards-compatibility test by comparing against old result files.
  * Patch: Renamed `test/test1.sh` to `integration-tests/run.sh`. Changed order of parameters.

* 1.2.0 (May, 2023)
  * Minor: Updated to miniconda3:4.10.3 base container, because the previous version (4.9.2) didn't build anymore.
  * Minor: Use `-env none` for "lsf" cluster profile. Local environment should not be copied. This probably caused problems with the old "dkfzModules" environment profile.
  * Patch: Require Nextflow >= 22.07.1, which fixes an LSF memory request bug. Added options for per-job memory requests to "lsf" profile in `nextflow.config`.
  * Patch: Remove unnecessary `*_BINARY` variables in scripts. Binaries are fixed by Conda/containers.
  * Patch: Needed to explicitly set `conda.enabled = True` with newer Nextflow

* 1.1.0 (February, 2022)
  * Minor: Added `--publishMode` option to allow user to select the [Nextflow publish mode](https://www.nextflow.io/docs/latest/process.html#publishdir). Default: `rellink`. Note that the former default was `symlink`, but as this change is considered negligible we classified the change as "minor".
  * Minor: Removed `dkfzModules` profile. Didn't work well and was originally only for development. Please use 'conda', 'singularity' or 'docker'. The container-based environments provide the best reproducibility.
  * Patch: Switched from Travis to CircleCI for continuous integration.

* 1.0.1 (October 14., 2021)
  * Patch: Fix memory calculation as exponential backoff
  * Patch: Job names now contain workflow name and job/task hash. Run name seems currently not possible to include there (due to a possible bug in Nextflow).
  * Patch: The end message when the workflow runs now reports whether the workflow execution failed (instead of always "success").

* 1.0.0 (June 15., 2021)

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

## Origins

The workflow is a port of the Roddy-based [BamToFastqPlugin](https://github.com/TheRoddyWMS/BamToFastqPlugin). Compared to the Roddy-workflow, some problems with the execution of parallel processing, resulting in potential errors, have been fixed.

## License & Contributors

See [LICENSE.txt](LICENSE.txt) and [CONTRIBUTORS](CONTRIBUTORS).
