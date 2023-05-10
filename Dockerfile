FROM continuumio/miniconda3:4.10.3

LABEL maintainer="Philip R. Kensche <p.kensche@dkfz.de>"

# Capitalized versions for many tools. Minuscle version at least for apt.
ARG HTTP_PROXY=""
ARG http_proxy="$HTTP_PROXY"
ARG HTTPS_PROXY=""
ARG https_proxy="$HTTPS_PROXY"
ARG NO_PROXY=""
ARG no_proxy="$NO_PROXY"

# Setup base conda container with bash as default shell.
SHELL ["/bin/bash", "-c"]
RUN conda init bash

# Add nf-bam2fastq requirements.
LABEL org.opencontainers.image.source="https://github.com/dkfz-odcf/nf-bam2fastq"
COPY task-environment.yml ./
RUN conda config --set proxy_servers.http "$HTTP_PROXY" && \
    conda config --set proxy_servers.https "$HTTPS_PROXY" && \
    conda env create -n nf-bam2fastq -f task-environment.yml && \
    source activate nf-bam2fastq && \
    conda clean --all -f -y

# ps is needed by Nextflow for collecting runtime information from the container
RUN apt update && \
    apt-get install -y procps && \
    rm -rf /var/lib/apt/lists/* && \
    apt clean

# For login Bash /etc/profile and ~/.profile is sourced. /etc/profile sources /etc/bash.bashrc.
# For non-login, interactive Bash /etc/bash.bashrc is sourced directly.
# For non-login, non-interactive Bash. We set BASH_ENV/ENV to /etc/bash.bashrc
# NOTE: ~/.bashrc could not be used, because when using it, ~/ is /root/.
#       Therefore /etc/bash.bashrc is used to use conda for all user IDs.
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
set -u\n\' >> /etc/container.bashrc && \
    echo "source /etc/profile" > ~/.profile && \
    cp ~/.profile /.profile && \
    echo "source /etc/container.bashrc" >> /etc/bash.bashrc

ENTRYPOINT ["bash", "-i", "-c"]
