# Targets list to gather Landsat stack at WQP site locations

# Source targets functions ------------------------------------------------

tar_source(files = "7_qa_stack/src/")


# Define {targets} workflow -----------------------------------------------

# target objects in workflow
p7_qa_stack <- list(
  
  tar_target(
    name = p7_check_dir_structure,
    command = {
      # make directories if needed
      directories = c("7_qa_stack/qa/",
                      "7_qa_stack/out/",
                      "7_qa_stack/export/")
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
    name = p7_mission_identifiers,
    command = tibble(mission_id = c("LT04", "LT05", "LE07", "LC08", "LC09"),
                     mission_names = c("Landsat 4", "Landsat 5", "Landsat 7", "Landsat 8", "Landsat 9"))
  ),
  
  # set dswe types
  tar_target(
    name = p7_dswe_types,
    command = {
      dswe = NULL
      if (grepl("1", p5_yml$DSWE_setting)) {
        dswe = c(dswe, "DSWE1")
      } 
      if (grepl("1a", p5_yml$DSWE_setting)) {
        dswe = c(dswe, "DSWE1a")
      } 
      if (grepl("3", p5_yml$DSWE_setting)) {
        dswe = c(dswe, "DSWE3")
      } 
      dswe
    }
  ), 
  
  tar_target(
    name = p7_metadata_files,
    command = list.files(file.path("6_siteSR_stack/mid/", p5_yml$run_date), 
                         full.names = TRUE) %>% 
      .[grepl("metadata", .)]
  ),
  
  # qa the siteSR stacks like we do with lakeSR
  tar_target(
    name = p7_qa_Landsat_files,
    command = {
      p7_check_dir_structure
      qa_and_document_LS(mission_info = p7_mission_identifiers,
                         dswe = p7_dswe_types, 
                         metadata_files = p7_metadata_files,
                         collated_files = p6_collated_siteSR_files)
    },
    packages = c("arrow", "data.table", "tidyverse", "ggrepel", "viridis", "stringi"),
    pattern = cross(p7_mission_identifiers, p7_dswe_types),
  ),
  
  # now add siteSR id, and necessary information for data storage, save as .csv
  tar_target(
    name = p7_qa_files_list,
    command = {
      p7_qa_Landsat_files
      list.files("7_qa_stack/qa/", full.names = TRUE)
    },
    cue = tar_cue("always")
  ),
  
  tar_target(
    name = p7_Landsat_files_for_export,
    command = prep_Landsat_for_export(file = p7_qa_files_list,
                                      file_type = "csv",
                                      out_path = "7_qa_stack/export/"),
    pattern = map(p7_qa_files_list),
    packages = c("arrow", "data.table", "tidyverse", "tools", "stringi")
  ),
  
  tar_target(
    name = p7_Landsat_metadata_for_export,
    command = prep_Landsat_for_export(file = p7_metadata_files,
                                      file_type = "csv", 
                                      out_path = "7_qa_stack/export/"),
    pattern = map(p7_metadata_files),
    packages = c("arrow", "data.table", "tidyverse", "tools", "stringi")
  )
  
)

# if configuration is to update and share on Drive, add these targets to the p7 
# list
if (config::get(config = general_config)$update_and_share) {
  
  p7_qa_stack <- list(
    
    p7_qa_stack,
    
    tar_target(
      name = p7_check_Drive_siteSR_folder,
      command =  {
        p0_check_drive_parent_folder
        tryCatch({
          drive_auth(p0_siteSR_config$google_email)
          parent_folder <- p0_siteSR_config$drive_project_folder
          version_path <- paste0(p0_siteSR_config$drive_project_folder, 
                                 paste0("siteSR_qa_v", p5_yml$run_date, "/"))
          drive_ls(version_path)
        }, error = function(e) {
          # if there is an error, check both the 'collated_raw' folder and the 'version'
          # folder
          drive_mkdir(path = parent_folder, name = paste0("siteSR_qa_v", p5_yml$run_date))
        })
        return(version_path)
      },
      packages = "googledrive",
      cue = tar_cue("always")    
    ),
    
    tar_target(
      name = p7_send_siteSR_files_to_drive,
      command = export_single_file(file_path = p7_Landsat_files_for_export,
                                   drive_path = p7_check_Drive_siteSR_folder,
                                   google_email = p0_siteSR_config$google_email),
      packages = c("tidyverse", "googledrive"),
      pattern = map(p7_Landsat_files_for_export)
    ),
    
    tar_target(
      name = p7_send_metadata_files_to_drive,
      command = export_single_file(file_path = p7_Landsat_metadata_for_export,
                                   drive_path = p7_check_Drive_siteSR_folder,
                                   google_email = p0_siteSR_config$google_email),
      packages = c("tidyverse", "googledrive"),
      pattern = map(p7_Landsat_metadata_for_export)
    ),
    
    tar_target(
      name = p7_save_siteSR_drive_info,
      command = {
        drive_ids_site <- p7_send_siteSR_files_to_drive %>% 
          select(name, id)
        drive_ids_meta <- p7_send_metadata_files_to_drive %>% 
          select(name, id)
        drive_ids <- bind_rows(drive_ids_site, drive_ids_meta) 
        write_csv(drive_ids,
                  paste0("7_qa_stack/out/siteSR_qa_files_drive_ids_v",
                         p5_yml$run_date,
                         ".csv"))
        drive_ids
      },
      packages = c("tidyverse", "googledrive"),
      deployment = "main"
    )
    
  )
  # collate site info/site id info here
  
}

