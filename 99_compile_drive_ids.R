# Targets list to create/update drive ids for saved targets

# Define p99 group --------------------------------------------------------

# Source the functions that will be used to build the targets in this list
tar_source(files = "src/")

p99_compile_drive_ids <- list(
  
  # make directories if needed
  tar_target(
    name = p99_check_dir_structure,
    command = {
      directories = c("99_compile_drive_ids/out/")
      walk(directories, function(dir) {
        if(!dir.exists(dir)){
          dir.create(dir)
        }
      })
    },
    cue = tar_cue("always")
  ),
  
  # grab all the Drive info for the .rds files in the 'targets' folder
  tar_target(
    name = p99_make_target_ids,
    command = {
      get_file_ids(google_email = p0_siteSR_config$google_email,
                   drive_folder = "~/aquamatch_siteSR_wqp/targets/",
                   file_path = "99_compile_drive_ids/out/target_drive_ids.csv",
                   depend = c(p4_export_sites,
                              p5_export_visible_sites,
                              p99_check_dir_structure))
    },
    cue = tar_cue("always"),
    packages = c("tidyverse", "googledrive")
  )

)