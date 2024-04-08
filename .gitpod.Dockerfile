FROM gitpod/workspace-full

RUN brew install R

FROM condaforge/mambaforge:22.9.0-1
