# Use the Gitpod base image for Python 3.11
FROM gitpod/workspace-python-3.11

# Install Miniconda
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p $HOME/miniconda && \
    rm ~/miniconda.sh

# Add Miniconda to PATH
ENV PATH="$HOME/miniconda/bin:$PATH"

# Initialize conda in bash config fiiles:
RUN conda init bash

RUN conda install GenoFlU -c conda-forge -c bioconda -y

RUN conda install conda-forge::r-base -y


