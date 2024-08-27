# Target list to pull the historical Landsat stack at RS-visible sites

# Set up python virtual environment ---------------------------------------

tar_source("6_siteSR_stack/py/pySetup.R")


# Source targets functions ------------------------------------------------

tar_source(files = "6_siteSR_stack/src/")


# Point to the GEE configuration file -------------------------------------

yaml_file <- "gee_config.yml"

# Define {targets} workflow -----------------------------------------------

# Set target-specific options such as packages.
tar_option_set(packages = "tidyverse")

# target objects in workflow
p6_siteSR_stack <- list(
  # make directories if needed
  tar_target(
    name = p6_check_dir_structure,
    command = {
      directories = c("6_siteSR_stack/mid/",
                      "6_siteSR_stack/out/",
                      "6_siteSR_stack/down")
      
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
    name = config_file,
    command = yaml_file,
    read = read_yaml(!!.x),
    packages = "yaml",
    cue = tar_cue("always")
  ),
  
  # load, format, save yml as a csv, depends on confit_file target
  tar_target(
    name = yml,
    command = {
      config_file 
      format_yaml(yml_file = yaml_file)
    },
    packages = c("yaml", "tidyverse")
  ),
  
  # load, format, save locations, depends on visible_sites target
  tar_target(
    name = locs,
    command = {
      visible_sites
      grab_locs(yaml = yml)
    }
  ),
  
  # get WRS tiles
  tar_target(
    name = WRS_tiles,
    command = get_WRS_tiles(detection_method = "site", 
                            yaml = yml, 
                            locs = locs),
    packages = c("readr", "sf")
  ),
  
  # run the Landsat pull as function per tile
  tar_target(
    name = eeRun,
    command = run_GEE_per_tile(WRS_tiles),
    pattern = map(WRS_tiles),
    packages = "reticulate"
  ),
  
  # wait for all earth engine tasks to be completed
  tar_target(
    name = ee_tasks_complete,
    command = {
      eeRun
      source_python("6_siteSR_stack/py/poi_wait_for_completion.py")
    },
    packages = "reticulate"
  ),
  
  # download all files
  tar_target(
    name = download_files,
    command = {
      ee_tasks_complete
      download_csvs_from_drive(drive_folder_name = yml$proj_folder,
                               google_email = yml$google_email,
                               version_identifier = yml$run_date)
    },
    packages = c("tidyverse", "googledrive")
  ),
  
  # collate all files
  tar_target(
    name = collated_data_files,
    command = {
      download_files
      collate_csvs_from_drive(file_prefix = yml$proj, 
                              version_identifier = yml$run_date)
    },
    packages = c('tidyverse', 'feather')
  ),
  
  # and collate the data with metadata
  tar_target(
    name = make_files_with_metadata,
    command = add_metadata(yaml = yml,
                           collated_files = collated_data_files,
                           file_prefix = yml$proj,
                           version_identifier = yml$run_date),
    packages = c("tidyverse", "feather")
  )
  
  
)
