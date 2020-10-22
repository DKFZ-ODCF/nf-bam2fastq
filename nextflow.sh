nextflow run bam2fastq.nf -profile test,conda -ansi-log --bamFiles=test/test1.bam,test/test2.bam --outputDir=test_out --sortFastqs=true -resume -with-tower http://localhost:8000/api
