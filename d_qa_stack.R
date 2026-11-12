# Targets list to gather Landsat stack at WQP site locations

# Source targets functions ------------------------------------------------

tar_source(files = "d_qa_stack/src/")


# Define {targets} workflow -----------------------------------------------

# when the siteSR acquisition is run (run_GEE), only one site per group of 
# overlapping sites is sent to EE, see c_site_crosswalk. Files are exported (and
# shared on Drive) in group e, see e_export_files.R
d_run_GEE <- config::get(config = general_config)$run_GEE

# target objects in workflow
d_qa_stack <- list(
  
  tar_target(
    name = d_check_dir_structure,
    command = {
      # make directories if needed
      directories = c("d_qa_stack/qa/",
                      "d_qa_stack/out/",
                      "d_qa_stack/export/")
      walk(directories, function(dir) {
        if(!dir.exists(dir)){
          dir.create(dir)
        }
      })
    },
    cue = tar_cue("always"),
    deployment = "main",
  ),
  
  tar_target(
    name = d_mission_identifiers,
    command = tibble(mission_id = c("LT04", "LT05", "LE07", "LC08", "LC09"),
                     mission_names = c("Landsat 4", "Landsat 5", "Landsat 7", "Landsat 8", "Landsat 9"))
  ),
  
  # set dswe types
  tar_target(
    name = d_dswe_types,
    command = {
      dswe = NULL
      if (grepl("1", b_yml$DSWE_setting)) {
        dswe = c(dswe, "DSWE1")
      } 
      if (grepl("1a", b_yml$DSWE_setting)) {
        dswe = c(dswe, "DSWE1a")
      } 
      if (grepl("3", b_yml$DSWE_setting)) {
        dswe = c(dswe, "DSWE3")
      } 
      dswe
    }
  ), 
  
  tar_files(
    name = d_metadata_files,
    command = c_collated_siteSR_files %>% 
      .[grepl("metadata", .)]
  ),
  
  # crosswalk of every RS-visible siteSR_id to the site that was sent to EE. If
  # sites were not grouped (no run_GEE), each site is its own extraction site.
  tar_target(
    name = d_crosswalk,
    command = {
      if (d_run_GEE) {
        c_site_crosswalk
      } else {
        tibble(siteSR_id = b_visible_sites$id,
               extraction_siteSR_id = b_visible_sites$id,
               n_sites_in_cluster = 1L)
      }
    }
  ),
  
  # qa the siteSR stacks like we do with lakeSR
  tar_target(
    name = d_qa_Landsat_files,
    command = {
      d_check_dir_structure
      qa_and_document_LS(mission_info = d_mission_identifiers,
                         dswe = d_dswe_types, 
                         metadata_files = d_metadata_files,
                         collated_files = c_collated_siteSR_files)
    },
    packages = c("arrow", "data.table", "tidyverse", "ggrepel", "viridis", "stringi"),
    pattern = cross(d_mission_identifiers, d_dswe_types),
    deployment = "main" # can not be run multi-core
  ),
  
  # now add siteSR id, and necessary information for data storage, save as .csv
  tar_files(
    name = d_qa_files_list,
    command = {
      d_qa_Landsat_files
      list.files("d_qa_stack/qa/", 
                 full.names = TRUE,
                 pattern = ".feather") %>% 
        # make sure gee version is right
        .[grepl(paste0(b_yml$run_date, "_filtered"), .)]
    }
  ),
  
  # create a list of HUC2's to map over (all RS-visible sites, since the data 
  # are back-joined to every visible site)
  tar_target(
    name = d_unique_huc2,
    command = {
      a_sites_with_NHD_info %>%
        filter(siteSR_id %in% d_crosswalk$siteSR_id) %>%
        distinct(huc2 = str_sub(assigned_HUC, 1, 2)) %>%
        pull(huc2)
    }
  ),
  
  # Landsat 4 is small enough for a single file
  tar_target(
    name = d_Landsat4_collated_data,
    command = sort_qa_Landsat_data(qa_files = d_qa_files_list, 
                                   gee_identifier = b_yml$run_date,
                                   mission_info = d_mission_identifiers %>% 
                                     filter(mission_names == "Landsat 4"),
                                   site_info = a_sites_with_NHD_info,
                                   crosswalk = d_crosswalk,
                                   dswe = d_dswe_types),
    pattern = map(d_dswe_types),
    packages = c("data.table", "tidyverse", "arrow", "stringi")
  ),
  
  # Landsat 5, 7, 8 need to be separated by HUC2
  tar_target(
    name = d_collated_Landsat5_by_huc2,
    command = sort_qa_Landsat_data(qa_files = d_qa_files_list,
                                   gee_identifier = b_yml$run_date,
                                   mission_info = d_mission_identifiers %>%
                                     filter(mission_names == "Landsat 5"),
                                   site_info = a_sites_with_NHD_info,
                                   crosswalk = d_crosswalk,
                                   dswe = d_dswe_types,
                                   HUC2 = d_unique_huc2),
    pattern = cross(d_dswe_types, d_unique_huc2),
    packages = c("data.table", "tidyverse", "arrow", "stringi"),
    deployment = "main" # too big for multicore
  ),
  
  tar_target(
    name = d_collated_Landsat7_by_huc2,
    command = sort_qa_Landsat_data(qa_files = d_qa_files_list,
                                   gee_identifier = b_yml$run_date,
                                   mission_info = d_mission_identifiers %>%
                                     filter(mission_names == "Landsat 7"),
                                   site_info = a_sites_with_NHD_info,
                                   crosswalk = d_crosswalk,
                                   dswe = d_dswe_types,
                                   HUC2 = d_unique_huc2),
    pattern = cross(d_dswe_types, d_unique_huc2),
    packages = c("data.table", "tidyverse", "arrow", "stringi"),
    deployment = "main" # too big for multicore
  ),
  
  tar_target(
    name = d_collated_Landsat8_by_huc2,
    command = sort_qa_Landsat_data(qa_files = d_qa_files_list,
                                   gee_identifier = b_yml$run_date,
                                   mission_info = d_mission_identifiers %>%
                                     filter(mission_names == "Landsat 8"),
                                   site_info = a_sites_with_NHD_info,
                                   crosswalk = d_crosswalk,
                                   dswe = d_dswe_types,
                                   HUC2 = d_unique_huc2),
    pattern = cross(d_dswe_types, d_unique_huc2),
    packages = c("data.table", "tidyverse", "arrow", "stringi"),
    deployment = "main" # too big for multicore
  ),
  
  # Landsat 9 is small enough to be a single file.
  tar_target(
    name = d_Landsat9_collated_data,
    command = sort_qa_Landsat_data(qa_files = d_qa_files_list, 
                                   gee_identifier = b_yml$run_date,
                                   mission_info = d_mission_identifiers %>% 
                                     filter(mission_names == "Landsat 9"),
                                   site_info = a_sites_with_NHD_info,
                                   crosswalk = d_crosswalk,
                                   dswe = d_dswe_types),
    pattern = map(d_dswe_types),
    packages = c("data.table", "tidyverse", "arrow", "stringi")
  ),
  
  # metadata
  tar_target(
    name = d_Landsat_metadata_formatted,
    command = prep_LS_metadata_for_export(file = d_metadata_files,
                                          file_type = "csv",
                                          gee_identifier = b_yml$run_date,
                                          out_path = "d_qa_stack/export"),
    pattern = map(d_metadata_files),
    packages = c("data.table", "tidyverse", "arrow", "stringi")
  )

)
