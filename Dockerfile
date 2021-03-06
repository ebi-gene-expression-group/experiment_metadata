FROM continuumio/miniconda3:4.8.2
# debian

RUN apt-get update 
RUN apt-get install -y git bash gawk

# install conda packages atlas-experiment-metadata and perl dependencies
RUN /opt/conda/bin/conda config --add channels defaults && \
    /opt/conda/bin/conda config --add channels conda-forge && \
    /opt/conda/bin/conda config --add channels bioconda && \
    /opt/conda/bin/conda install -c ebi-gene-expression-group atlas-experiment-metadata

ENV PATH "/opt/conda/bin:/opt/conda/condabin:/bin:/sbin:/usr/bin:/usr/local/bin"

ENV ZOOMA_API_BASE=https://www.ebi.ac.uk/spot/zooma/v2/api/
ENV OLS_API_BASE=http://www.ebi.ac.uk/ols/api/

