# AquaMatch_siteSR_WQP

The third repository in the AquaMatch constellation. This repository determines remote sensing visibility and acquires surface reflectance data for RS-visible sites from the Water Quality Portal harmonized datasets.

We suggest users use the `run_targets.Rmd` script to run this workflow, as it walks through all necessary configuration and authentication steps prior to running the workflow.

This repository is covered by the MIT use license. We request that all downstream uses of this work be available to the public when possible.

## Pre-requisites

In order to run the code in this repository, you must have the AquaMatch_harmonize_WQP repository and AquaMatch_lakeSR on your computer. Proper configuration of `harmonize_repo_directory` and `lakeSR_repo_directory` in the general configuration file (`config.yml`) is imperative as the siteSR_WQP workflow references files inside AquaMatch_harmonize_WQP and AquaMatch_lakeSR file structures. If this is incorrectly set up, users will receive a message to communicate this and the workflow will stop. All repositories stored on the AquaSat v2 GitHub will contain files that link to versions of the data that the AquaSat v2 team has harmonized so that a local run is not necessitated.

We use a configuration file (`gee_config.yml`) for the GEE run, as well. If you are outside of the ROSS team, you will need to update some entries in the configuration file and update the general_config argument in the \_targets.R script in order to successfully run the Pekel and Landsat portions of this workflow (groups 5 & 6).

## Targets Architecture

**\_targets.R:**

This initial group of targets checks the configuration settings in config.yml, checks for the harmonization and lakeSR pipelines, and checks for Google Drive folder architecture. This group also acquires target objects from the harmonization and lakeSR pipelines.

**4_compile_sites:**

This {targets} group collates the sites from the harmonization pipeline, creating a list of locations to acquire remote sensing data. All locations are associated with a HUC8 if one is not listed in the metadata for the site from the WQP, then the unique HUC4s are used to associate points with waterbodies and flowlines of the NHDPlusV2 (CONUS) or NHD Best Resolution (non-CONUS HUCs) files.

**5_determine_RS_visibility:**

The resulting list of in situ locations are used to assess remote-sensing visibility in this {targets} group. Sites are assessed for visibility using the JRC Global Surface Water [@pekel2016] which is based on the historical Landsat record. This {targets} group takes a number of hours to run, if the configuration of `run_pekel` is set to TRUE. If the configuration is set to FALSE, run time will be dependent on your internet connection (to access the previously-created files) and the number of cores available to run the workflow.

**6_siteSR_stack:**

This group of {targets} acquires Landsat Collection 2 SRST stacks for sites determined to be visible in the previous {targets} group. Data are collated in this step. This {targets} group takes about three days to run, if the configuration `run_GEE` is set to TRUE. If the configuration is set to FALSE, run time will be dependent on your internet connection (to access the previously-created files) and the number of cores available to run the workflow.

**7_siteSR_qa:**

Collated Landsat data are filtered for quality based on broadly applicable thresholds.

**8_siteSR_matchup:**

forthcoming
