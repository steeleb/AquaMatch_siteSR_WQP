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
  
  # qa the siteSR stacks like we do with lakeSR
  tar_target(
    name = p7_qa_Landsat_files,
    command = {
      p7_check_dir_structure
      qa_and_document_LS(mission_info = p7_mission_identifiers,
                         dswe = p7_dswe_types, 
                         collated_files = p6_collated_siteSR_files)
    },
    packages = c("arrow", "data.table", "tidyverse", "ggrepel", "viridis"),
    pattern = cross(p7_mission_identifiers, p7_dswe_types),
  ),
  
  # now add siteSR id, and necessary information for data storage, save as .csv
  tar_target(
    name = p7_qa_files_list,
    command = {
      p7_qa_Landsat_files
      list.files("7_qa_stack/qa/", full.names = TRUE)
    }
  ),
  
  tar_target(
    name = p7_Landsat_files_for_export,
    command = prep_Landsat_for_export(file = p7_qa_files_list,
                                      file_type = "csv",
                                      out_path = "7_qa_stack/export/"),
    pattern = map(p7_qa_files_list),
    packages = c("arrow", "data.table", "tidyverse", "tools", "stringi")
  )
  
)

# if configuration is to update and share on Drive, add these targets to the p7 
# list
if (config::get(config = general_config)$update_and_share) {
  p7_qa_stack <- list(
    
    p7_qa_stack,
    
    tar_target(
      name = p7_test,
      command = "fish"
      
    )
  )
}

