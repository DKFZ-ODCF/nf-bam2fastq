# BamToFastq Nexflow Workflow

Convert BWA-generated und possibly merged and duplication-marked BAM files back to FASTQ.

By default, the workflow sorts FASTQ files by their FASTQ IDs to avoid e.g. that reads [ what is meant here, are reads "produced", maybe use other wording ] from position-sorted BAMs are produced in position-sorted order, with possible subsequent problems during re-alignment (e.g. if alignment parameters like insert-size are estimated from the data itself). Most jobs are actually sorting-jobs -- so you can save a lot of computation time, if the input order during alignment does not matter for you.

Obviously, you can only reconstitute complete original FASTQs (except for order), if the BAM was not filtered in any way, e.g. by removing duplicates.  

[ what about putting quickstart/examples/how2run here making it easier to see (my personal preference)]

## Remarks

  * Paired-end FASTQs are generated with biobambam2's bamtofastq
  * Sorting is done with the UNIX coreutils tool "sort" in an efficient way (e.g. sorting per read-group; co-sorting of order-matched mate FASTQs).

## Status

  * Explicit single-end BAM processing is not implemented. Possibly it works with the paired-end pipeline. The original (Roddy) Picard-based code was left in the workflow, but was never tested in this workflow.
  * This is (yet) really more of an exercise to implement a Nextflow workflow.

## Parameters

When doing BAM-to-FASTQ conversion with subsequent sorting, the unsorted output of the conversion step are called "intermediate" FASTQs. In this case, you can choose to leave the intermediate FASTQs unsorted and thus trade CPU time for IO-time. Note that the output FASTQs of the workflow (possibly unsorted if `sortFastqs == false`) are always compressed [how?].

**Required**

  * `bamFileList`: Comma-separated list of input BAM-file paths.
  * `outputDir`: Output directory


**Optional**

  * `sortFastqs`: Whether to produce FASTQs in a similar order as in the input BAM (`false`) or sort by name (`true`). Default: `true`.
  * `pairedEnd`: Data is paired-end (`true`) or single-end (`false`). Default: `true`
  * `writeUnpairedFastqs`: Reads may have lost their mate, e.g. because of filtering or truncation of the BAM. By default, these reads are written to a `_U` file. [ what is a _U file ]
  * `excludedFlags`: Comma-separated list of flags. Default: "secondary,supplementary" (thus with complete BWA-aligned BAM input exactly the reads of the input are produced)
  * outputPerReadGroup: Whether reads from different read-groups should be written to different files. Default: true
  * `checkFastqMd5`: While reading in intermediate FASTQs, check that the MD5 is the same as in the accompanied '.md5' file. Only available for Picard, as Biobambam does not produce MD5 files for output files. Default: `true`.
  * Trading memory vs. IO
    * `sortMemory`: Memory used for sorting. Too large values are useless, unless you have enough memory to sort completely in-memory. Default: 100 MB.
    * `sortThreads`: Number of threads used for sorting. Default: 4
    * `compressIntermediateFastqs`: Whether to compress FASTQs produced by ???. Default: true
    * `compressor`: GZip tool to use. By default the script `bin/pigz.sh` is used. The tool needs to (1) compress by default, (2) accept a `-d` option to switch to decompression, and (3) work on standard-input and -output.
    * `compressorThreads`: pigz can use multiple threads for compression. Default: 4

## Example

Provided you have a working Conda installation and two test BAM files you can run

```bash
mkdir test_out/
nextflow run bam2fastq.nf \
    -profile test,conda \
    -ansi-log \
    --bamFileList=test/test.bam \
    --outputDir=test_out \
    --sortFastqs=false
```

For each BAM file in the comma-separated `--bamFileList` parameter, one directory with FASTQs is created in the `outputDir`. With the `test` profile use only small BAM files [why?]. The `conda` profile defines a Conda environment from the `./task-environment.yml` file, which Nextflow will by default automatically set up in the `work` directory.


### Run with Docker

There is also a dockerized version. You can build the container with

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

Then to run the workflow locally with Docker you can do e.g. (this time with sorting the FASTQs)

```bash
nextflow run bam2fastq.nf \
    -profile test,docker \
    -ansi-log \
    --bamFiles=test/test1.bam,test/test2.bam \
    --outputDir=test_out \
    --sortFastqs=true
```


### Run with Singularity

To run the workflow with singularity:

```bash
# Convert the Docker image to Singularity
singularity build nf-bam2fastq.sif docker-daemon://nf-bam2fastq:latest

# Run with the singularity profile
nextflow run bam2fastq.nf \
    -profile test,singularity \
    -ansi-log \
    --bamFiles=test/test1.bam,test/test2.bam \
    --outputDir=test_out \
    --sortFastqs=true
```

## Environment and Execution

[ the significance of this section is not entirely clear, especially to people unexperienced with Nextflow ]

Environment and execution are two relatively independently varying parameters that you can select by choosing a profile combination:

  * conda (Conda environment)
  * docker (based on Conda environment)
  * singularity (see above command to create this from the Docker container)
  * dkfzModules (uses the environment modules available in the DKFZ batch processing cluster)

As executors currently only "local" and "lsf" execution available as profiles. Adapt the `nextflow.config` if you need others.

For instance, if you want to run the workflow as Singularity containers in an LSF cluster you can do

```bash
nextflow run bam2fastq.nf \
    -profile lsf,singularity \
    -ansi-log \
    --bamFiles=test/test1.bam,test/test2.bam \
    --outputDir=test_out \
    --sortFastqs=true
```

## Test Data

[ can the test data be added or linked to the repository or download in the Dockerfile? would make testing easier ]

The test data in the `test/` directory is from https://github.com/genome/gms/wiki/HCC1395-WGS-Exome-RNA-Seq-Data.

## Origins

The workflow is a port of the Roddy-based [https://github.com/TheRoddyWMS/BamToFastqPlugin](BamToFastqPlugin). Some problems with the execution of parallel processing, resulting in potential errors, have been fixed. Roddy-specific code was removed.

## License & Contributors

See [LICENSE](LICENSE) and [CONTRIBUTORS](CONTRIBUTORS).
