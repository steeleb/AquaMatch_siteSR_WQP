# Target list to pull the historical Landsat stack at RS-visible sites

# Set up python virtual environment ---------------------------------------

tar_source("6_siteSR_stack/py/pySetup.R")


# Source targets functions ------------------------------------------------

tar_source(files = "6_siteSR_stack/src/")


# Point to the GEE configuration file -------------------------------------

yaml_file <- "gee_config.yml"

# Define {targets} workflow -----------------------------------------------

# target objects in workflow
p6_siteSR_stack <- list(
  # make directories if needed
  tar_target(
    name = p6_check_dir_structure,
    command = {
      directories = c("6_siteSR_stack/mid/",
                      "6_siteSR_stack/out/",
                      "6_siteSR_stack/out_files/",
                      "6_siteSR_stack/down/")
      
      walk(directories, function(dir) {
        if(!dir.exists(dir)){
          dir.create(dir)
        }
      })
    },
    cue = tar_cue("always"),
    priority = 1
  ),
  
  # read and track the config file
  tar_file_read(
    name = p6_config_file,
    command = yaml_file,
    read = read_yaml(!!.x),
    packages = "yaml",
    cue = tar_cue("always")
  ),
  
  # load, format, save yml as a csv, depends on confit_file target
  tar_target(
    name = p6_yml,
    command = format_yaml(yaml = p6_config_file)
  ),
  
  # load, format, save locations, depends on visible_sites target
  tar_target(
    name = p6_locs,
    command = {
      p5_visible_sites
      grab_locs(yaml = p6_yml)
    }
  ),
  
  # get WRS tiles
  tar_target(
    name = p6_WRS_tiles,
    command = get_WRS_tiles(detection_method = "site", 
                            yaml = p6_yml, 
                            locs = p6_locs),
    packages = c("readr", "sf")
  ),
  
  # run the Landsat pull as function per tile
  tar_target(
    name = p6_eeRun,
    command = run_GEE_per_tile(p6_WRS_tiles),
    pattern = map(p6_WRS_tiles),
    packages = "reticulate"
  ),
  
  # wait for all earth engine tasks to be completed
  tar_target(
    name = p6_ee_tasks_complete,
    command = {
      p6_eeRun
      source_python("6_siteSR_stack/py/poi_wait_for_completion.py")
    },
    packages = "reticulate"
  ),
  
  # download all files
  tar_target(
    name = p6_download_files,
    command = {
      p6_ee_tasks_complete
      download_csvs_from_drive(drive_folder_name = p6_yml$proj_folder,
                               google_email = p6_yml$google_email,
                               version_identifier = p6_yml$run_date)
    },
    packages = c("tidyverse", "googledrive")
  ),
  # collate all files
  tar_target(
    name = p6_collated_data_files,
    command = {
      p6_download_files
      collate_csvs_from_drive(file_prefix = p6_yml$proj, 
                              version_identifier = p6_yml$run_date)
    },
    packages = c("tidyverse", "feather", "data.table")
  ),
  
  # and collate the data with metadata
  tar_target(
    name = p6_make_files_with_metadata,
    command = add_metadata(yaml = p6_yml,
                           collated_files = p6_collated_data_files,
                           file_prefix = p6_yml$proj,
                           version_identifier = p6_yml$run_date),
    packages = c("tidyverse", "feather", "data.table")
  )
  
)
