# Targets list to assess site remote sensing visibility

# Set up python virtual environment ---------------------------------------

tar_source("src/py/pySetup.R")

# Source targets functions ------------------------------------------------

tar_source(files = "5_siteSR_stack/src/")

# Point to the GEE configuration file -------------------------------------

yaml_file <- "gee_config.yml"

# Define {targets} workflow -----------------------------------------------

# target objects in workflow
p5_siteSR_stack <- list(
  # make directories if needed
  tar_target(
    name = p5_check_dir_structure,
    command = {
      directories = c("5_siteSR_stack/mid/",
                      "5_siteSR_stack/down/",
                      "5_siteSR_stack/run/",
                      "5_siteSR_stack/out/")
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
    name = p5_config_file,
    command = yaml_file,
    read = read_yaml(!!.x),
    packages = "yaml",
    cue = tar_cue("always")
  ),
  
  # load, format, save yml as a csv, depends on config_file target
  tar_target(
    name = p5_yml,
    command = format_yaml(yaml = p5_config_file)
  ),
  
  # load, format, save locations, depends on p4_sites_with_NHD_attribution target
  tar_target(
    name = p5_locs,
    command = {
      p4_sites_with_NHD_attribution
      grab_locs(yaml = p5_yml)
    }
  ),
  
  # get WRS tiles
  tar_target(
    name = p5_WRS_tiles,
    command = get_WRS_tiles(detection_method = "site", 
                            yaml = p5_yml, 
                            locs = p5_locs),
    packages = c("readr", "sf")
  ),
  
  # check to see that all sites and buffers are completely contained by each tile
  tar_target(
    name = p5_sites_contained,
    command = {
      check_for_containment(WRS_pathrow = p5_WRS_tiles,
                            locations = p5_locs,
                            yaml = p5_yml)
    },
    pattern = map(p5_WRS_tiles)
  ),
  
  # after pattern ran, save the file for use in Pekel run
  tar_target(
    name = p5_save_contained_sites,
    command = write_csv(p5_sites_contained, "5_siteSR_stack/run/locs_with_WRS.csv")
  ),
  
  # Run Pekel instance by WRS tile
  tar_target(
    name = p5_run_pekel,
    command = {
      p5_save_contained_sites
      source_python("5_siteSR_stack/py/runPekelOccurrence.py")
    },
    packages = "reticulate"
  ),
  
  # wait for all earth engine tasks to be completed
  tar_target(
    name = p5_pekel_tasks_complete,
    command = {
      p5_run_pekel
      source_python("5_siteSR_stack/py/wait_for_completion.py")
    },
    packages = "reticulate"
  ),
  
  # download Pekel files
  tar_target(
    name = p5_pekel_download,
    command = {
      p5_pekel_tasks_complete
      download_csvs_from_drive(drive_folder_name = p5_yml$proj_folder,
                               google_email = p5_yml$google_email,
                               version_identifier = p5_yml$run_date,
                               download_type = "pekel")
    },
    packages = c("tidyverse", "googledrive")
  ),
  
  # collate Pekel files
  tar_target(
    name = p5_pekel_collated,
    command = {
      p5_pekel_download
      files <- list.files(file.path("5_siteSR_stack/down/", 
                                    p5_yml$run_date, 
                                    "pekel"), 
                          full.names = TRUE)
      map(files, read_csv) %>% 
        bind_rows %>% 
        select(id, occurrence_med, occurrence_max, occurrence_min) %>% 
        left_join(., p5_save_contained_sites)
    }
  ),
  
  # filter for visible sites, here visible if Pekel max occurrence within buffer 
  # of site is > 80%
  tar_target(
    name = p5_visible_sites,
    command = {
      visible_sites <- p5_pekel_collated %>% 
        filter(occurrence_max >= 80) 
      # save the file and return the dataframe
      write_csv(visible_sites, "5_siteSR_stack/run/visible_locs_with_WRS.csv")
      visible_sites
    }
  ),
  
  # run the Landsat pull as function per tile
  tar_target(
    name = p5_eeRun,
    command = {
      p5_visible_sites
      run_GEE_per_tile(WRS_tile = p5_WRS_tiles)
    },
    pattern = map(p5_WRS_tiles),
    packages = "reticulate"
  ),
  
  # wait for all earth engine tasks to be completed
  tar_target(
    name = p5_ee_tasks_complete,
    command = {
      p5_eeRun
      source_python("5_siteSR_stack/py/wait_for_completion.py")
    },
    packages = "reticulate"
  ),
  
  # download all files
  tar_target(
    name = p5_download_files,
    command = {
      p5_ee_tasks_complete
      download_csvs_from_drive(drive_folder_name = p5_yml$proj_folder,
                               google_email = p5_yml$google_email,
                               version_identifier = p5_yml$run_date,
                               download_type = "stack")
    },
    packages = c("tidyverse", "googledrive")
  ),
  
  # collate all files
  tar_target(
    name = p5_collated_data_files,
    command = {
      p5_download_files
      collate_csvs_from_drive(file_prefix = p5_yml$proj, 
                              version_identifier = p5_yml$run_date)
    },
    packages = c("data.table", "tidyverse", "feather")
  ),
  
  # and collate the data with metadata
  tar_target(
    name = p5_make_files_with_metadata,
    command = add_metadata(yaml = p5_yml,
                           collated_files = p5_collated_data_files,
                           file_prefix = p5_yml$proj,
                           version_identifier = p5_yml$run_date),
    packages = c("data.table", "tidyverse", "feather")
  )
  
)
