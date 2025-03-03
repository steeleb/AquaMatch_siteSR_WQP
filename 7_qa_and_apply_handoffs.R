# Targets list to gather Landsat stack at WQP site locations

# Source targets functions ------------------------------------------------

tar_source(files = "7_qa_and_apply_handoffs/src/")


# Define {targets} workflow -----------------------------------------------

# target objects in workflow
p7_qa_and_apply_handoffs <- list(
  
  tar_target(
    name = p7_check_dir_structure,
    command = {
      # make directories if needed
      directories = c("7_qa_and_apply_handoffs/qa/",
                      "7_qa_and_apply_handoffs/out/")
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
    name = p7_qa_Landsat_files,
    command = qa_and_document_LS(mission_info = p7_mission_identifiers,
                                 dswe = p7_dswe_types, 
                                 collated_files = p6_collated_siteSR_files),
    packages = c("arrow", "data.table", "tidyverse", "ggrepel", "viridis"),
    pattern = cross(p7_mission_identifiers, p7_dswe_types),
  )
  # , 
  # 
  # tar_target(
  #   name = p7_corrected_Landsat_files,
  #   command = correct_timeseries(
  #     qa_files = p7_qa_Landsat_files,
  #     method = p0_siteSR_config$correction_method,
  #     correct_to = p0_siteSR_config$correct_to
  #   )
  # )
  
)

