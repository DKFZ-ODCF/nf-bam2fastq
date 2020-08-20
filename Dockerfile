# WESnake

FROM continuumio/miniconda3:4.8.2

SHELL ["/bin/bash", "-c"]

RUN conda init bash

RUN conda update --prefix /opt/conda conda

COPY task-environment.yml ./

RUN conda env create -n nf-bam2fastq -f task-environment.yml && \
    source activate nf-bam2fastq && \
    conda clean --all -f -y

RUN echo "source activate nf-bam2fastq" >> ~/.bashrc

RUN echo -e '\
export SAMTOOLS_BINARY=samtools\n\
export MBUFFER_BINARY=mbuffer\n\
export CHECKSUM_BINARY=md5sum\n\
export PERL_BINARY=perl\n\
export BIOBAMBAM_BAM2FASTQ_BINARY=bamtofastq\n' >> ~/.bashrc


ENTRYPOINT ["bash", "-i", "-c"]
