# AquaMatch_siteSR

The third repository in the AquaMatch constellation. This repository determines remote sensing visibility and acquires surface reflectance data for RS-visible sites from the Water Quality Portal harmonized datasets and National Water Information System site locations.

We suggest users use the `run_targets.Rmd` script to run this workflow, as it walks through all necessary configuration and authentication steps prior to running the workflow.

This repository is covered by the MIT use license. We request that all downstream uses of this work be available to the public when possible.

NOTE: there is a patch (`a_all_site_locations_patch.Rmd`) to remove an unclosed quote from the `siteSR_collated_WQP_NWIS_sites_with_NHD_info_2025-06-04.csv` file for publication at EDI. This creates a file with the name `siteSR_collated_WQP_NWIS_sites_with_NHD_info_2026-01-18.csv` these files are identical other than the deletion of the single instance of the unclosed quote in the file dated 2025-06-04. End users can use either file for downstream applications.

## Prerequisites

Proper configuration of the general configuration file (`config.yml`) is necessary for proper pipeline function. This repository is stored in the 'default' configuration which loads the existing station list, default remote sensing visibility, and GEE run. These settings can be altered in the `config.yml` file to re-run or alter any portion of the pipeline.

We also use a configuration file (`gee_config.yml`) for the GEE run. If you are external to the ROSS team, you will need to update some entries in this configuration file and update the general_config argument in the \_targets.R script in order to successfully run the Pekel and Landsat portions of this workflow (targets groups b & c). If using the "default" setting for the general configuration file, the GEE configuration file can be ignored.

## Targets Architecture

This repository uses multicore processing wherever possible. All quoted processing times below are based on the use of 11 cores on an MacBook Pro M2 with 64GB memory.

**\_targets.R:**

This initial group of targets checks the configuration settings in config.yml and checks for Google Drive folder architecture.

**a_compile_sites:**

This {targets} group collates all sites in the US and Territories that are stored in WQP and NWIS, creating a list of locations for which to acquire remote sensing data. All locations are associated with a HUC8 if one is not listed in the metadata for the site from the WQP, then the unique HUC4s are used to associate points with waterbodies and flowlines of the NHD Best Resolution files (for all HUC4s). Text fields are cleaned in this group (`clean_text_fields()`), which removes the need for the post-hoc patch described above for new runs. Stream, river, canal and ditch sites more than 500 m from a flowline have their flowline information removed (`flag_fl` = 3). This step will take about one day to run, depending on the number of cores available for processing. If the general configuration setting `compile_locations` is set to FALSE, this step will acquire the previously-collated sites from Google Drive for the version date listed in the setting `collated_site_version` and processing time should be very quick.

**b_determine_RS_visibility:**

The resulting list of in situ locations from `a_compile_sites` are used to assess remote-sensing visibility in this {targets} group. Sites are assessed for visibility using the JRC Global Surface Water [@pekel2016] which is based on the historical Landsat record. This {targets} group takes a number of hours to run, if the general configuration of `run_pekel` is set to TRUE. If the configuration is set to FALSE, run time will be dependent on your internet connection (to access the previously-created files) and the number of cores available to run the workflow.

**c_siteSR_stack:**

This group of {targets} acquires Landsat Collection 2 SRST stacks for sites determined to be visible in the targets group `b_determine_RS_visibility` and the resulting acquisition files are collated in this step. This {targets} group takes about three days to run (note: this estimate will be updated for the de-duplicated workflow), if the configuration `run_GEE` is set to TRUE. If the configuration is set to FALSE, run time will be dependent on your internet connection (to access the previously-created files) and the number of cores available to run the workflow.

To reduce redundant Earth Engine compute, RS-visible sites are grouped before acquisition (target `c_site_crosswalk`, function `cluster_sites_for_GEE()`), and only one site per group, the "extraction site", is sent to Earth Engine. Sites are grouped when the buffers of every pair of sites in the group overlap by at least `overlap_threshold` (75% in `admin_update`) of the buffer area and the sites are attributed to the same NHD waterbody (Lake/Reservoir and Pond sites) or the same NHD flowline (Stream and Ditch/Canal sites); Estuary and Other sites are grouped with sites of the same site type, and Lake/Pond or Stream/Canal sites without an NHD assignment are not grouped. The extraction site is an actual site in the group, so the acquired data are keyed to its `siteSR_id`. The file `siteSR_extraction_site_crosswalk_v[date].csv` maps every RS-visible `siteSR_id` to its `extraction_siteSR_id` and provides the shoreline and NHD assignment flags at the extraction site (`extraction_*`), which describe the area summarized in Earth Engine and apply to every site in the group. These steps are only run if `run_GEE` is TRUE.

**d_qa_stack:**

Collated Landsat data are filtered for quality based on broadly applicable thresholds. QA'd SR data are exported by HUC2 for Landsat 5, 7 and 8 (single files for Landsat 4 and 9), along with feather files. Data are keyed to the extraction site, so they are back-joined to every RS-visible site in the group: `siteSR_id` is the visible site, `extraction_siteSR_id` is the site sent to Earth Engine, and `flag_grouped_extraction` is 1 when more than one site was in the group.

**e_export_files:**

If `update_and_share` is TRUE, the final files are written and uploaded to Drive: the QA'd data as feather files, the extraction site crosswalk, and a site information file (`siteSR_site_information_v[date].csv`) that includes a flag for RS visibility, the huc2 assignment, and the grouping and extraction site information.

## Note

Landsat remote sensing images used in analyses courtesy of the United States Geological Survey. Any use of trade, firm, or product names is for descriptive purposes only and does not imply endorsement by the U.S. Government.

## Disclaimer

Unless otherwise stated, all data, metadata and related materials are considered to satisfy the quality standards relative to the purpose for which the data were collected. Although these data and associated metadata have been reviewed for accuracy and completeness and approved for release by the U.S. Geological Survey (USGS), no warranty expressed or implied is made regarding the display or utility of the data for other purposes, nor on all computer systems, nor shall the act of distribution constitute any such warranty.
