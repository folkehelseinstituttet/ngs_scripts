FROM rocker/tidyverse:4.4.2

# Copy the script into the container
WORKDIR /app
COPY make_labware_import.R /app/make_labware_import.R
RUN chmod +x /app/make_labware_import.R

ENTRYPOINT ["/app/make_labware_import.R"]
