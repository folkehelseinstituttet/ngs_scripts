FROM rocker/r-ver:4.4.1

# Install system dependencies for building R packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Install required R packages from CRAN
RUN Rscript -e "install.packages(c('dplyr','readr','stringr'), repos='https://cloud.r-project.org/')"


# Set working directory
WORKDIR /app

# Copy the script into the container
COPY make_labware_import.R /app/make_labware_import.R

# Ensure it is executable
RUN chmod +x /app/make_labware_import.R

# Default entrypoint
ENTRYPOINT ["/app/make_labware_import.R"]
