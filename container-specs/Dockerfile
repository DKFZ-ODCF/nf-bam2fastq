# SPDX-FileCopyrightText: 2024 The OTP authors
#
# SPDX-License-Identifier: MIT

FROM continuumio/miniconda3:4.12.0

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

# Now, the stuff that needs to be rebuild for every workflow/container.
# The envName can be reused in later layers, and in a Singularity.def.
ENV envName="nf-bam2fastq"
LABEL org.opencontainers.image.source="https://ghcr.io/dkfz-odcf/$envName"

COPY task-environment.yml ./

RUN conda config --set proxy_servers.http "$HTTP_PROXY" && \
    conda config --set proxy_servers.https "$HTTPS_PROXY" && \
    conda env create -n "$envName" -f task-environment.yml && \
    source activate "$envName" && \
    conda clean --all -f -y

# Use -p path instead of -n name to activate the environment. Otherwise, Conda will fail with
# NoWritableEnvsDirError.
ENTRYPOINT ["conda", "run", "--no-capture-output", "-p", "/opt/conda/envs/$envName"]
