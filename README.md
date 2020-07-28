# BamToFastq Nexflow Workflow

Convert BWA-generated und possibly merged and duplication-marked BAM files back to FASTQ. 

By default, FASTQ files are sorted by their FASTQ IDs to avoid e.g. that reads from position-sorted BAMs are produced in position-sorted order, with possible subsequent problems during re-alignment (e.g. if alignment parameters like insert-size are estimated from the data itself). Most jobs are arctually sorting-jobs.
 
Obviously, you can only reconstitute complete original FASTQs (except for order), if the BAM was not filtered in any way, e.g. by removing duplicates.  

## Remarks

  * Paired-end FASTQs are done with biobambam2's bamtofastq
  * Sorting is done with the UNIX coreutils tool "sort" in an efficient way (e.g. sorting per read-group; co-sorting of order-matched mate FASTQs).
  
## Status

  * Explicit single-end BAM processing is not implemented. Possibly it works with the paired-end pipeline. The original (Roddy) Picard-based code was left in the workflow, but was never tested in this workflow.
  * This is (yet) really more of an exercise to implement a Nextflow workflow. 
  
## Parameters

When doing BAM-to-FASTQ conversion with subsequent sorting, the unsorted output of the conversion step are called "intermediate" FASTQs. In this case, you can choose to leave the intermediate FASTQs unsorted and thus trade CPU time for IO-time. Note that the output FASTQs of the workflow (possibly unsorted if `sortFastqs == false`) are always compressed.

  * `bamFileList`: Comma-separated list of input BAM-file paths.
  * `sortFastqs`: Whether to produce FASTQs in a similar order as in the input BAM (`false`) or sort by name (`true`). Default: `true`.
  * `pairedEnd`: Data is paired-end (`true`) or single-end (`false`). Default: `true`
  * `writeUnpairedFastqs`: Reads may have lost their mate, e.g. because of filtering or truncation of the BAM. By default, these reads are written to a `_U` file.
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

```bash
nextflow run bam2fastq.nf -profile test,conda -ansi-log --bamFileList=test/test.bam --outputDir=test_out --sortFastqs=false
```

For each BAM file in the comma-separated `--bamFileList` parameter, one directory with FASTQs is created in the `outputDir`.

## Origins

The workflow is a port of the Roddy-based [https://github.com/TheRoddyWMS/BamToFastqPlugin](BamToFastqPlugin). Some problems with the execution of parallel processing, resulting in potential errors, have been fixed. Roddy-specific code was removed.

## License & Contributors

See [LICENSE](LICENSE) and [CONTRIBUTORS](CONTRIBUTORS).
