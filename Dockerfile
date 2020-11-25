FROM continuumio/miniconda3:4.8.2

LABEL maintainer="Philip R. Kensche <p.kensche@dkfz.de>"

SHELL ["/bin/bash", "-c"]

# Setup base conda container.
RUN conda init bash && \
    conda update -n base -c defaults conda && \
    conda clean --all -f -y

# Add nf-bam2fastq requirements.
COPY task-environment.yml ./
RUN conda env create -n nf-bam2fastq -f task-environment.yml && \
    source activate nf-bam2fastq && \
    conda clean --all -f -y

# ps is needed for collecting runtime information from the container
RUN apt update && \
    apt-get install -y procps && \
    rm -rf /var/lib/apt/lists/*

# For login Bash /etc/profile and ~/.profile is sourced. /etc/profile sources /etc/bash.bashrc.
# For non-login, interactive Bash /etc/bash.bashrc is sourced directly.
# For non-login, non-interactive Bash. We set BASH_ENV/ENV to /etc/bash.bashrc
# NOTE: For unknown reasons /.bashrc could not be used, because when using
#       `-u $(id -u):$(id -g)` as docker run parameter, the file was absent
#       (but not when just starting the container as root). Therefore
#       /etc/bash.bashrc is used.
# NOTE: Conda should be fully available in non-login, interactive shell. Conda itself creates
#       /etc/profile.d/conda.sh. The code that `conda init bash` writes to ~/.bashrc is moved
#       to /etc/bash.bashrc and reads the /etc/profile.d/conda.sh.
ENV BASH_ENV /etc/container.bashrc
ENV ENV /etc/container.bashrc

RUN grep "managed by 'conda init'" -A 100 ~/.bashrc >> /etc/container.bashrc && \
    rm ~/.bashrc && \
    echo -e '\
set +u\n\
source activate nf-bam2fastq\n\
set -u\n\
export SAMTOOLS_BINARY=samtools\n\
export PICARD_BINARY=picard\n\
export JAVA_BINARY=java\n\
export MBUFFER_BINARY=mbuffer\n\
export CHECKSUM_BINARY=md5sum\n\
export PERL_BINARY=perl\n\
export BIOBAMBAM_BAM2FASTQ_BINARY=bamtofastq\n' >> /etc/container.bashrc && \
    echo "source /etc/profile" > ~/.profile && \
    cp ~/.profile /.profile && \
    echo "source /etc/container.bashrc" >> /etc/bash.bashrc

ENTRYPOINT ["bash", "-i", "-c"]
