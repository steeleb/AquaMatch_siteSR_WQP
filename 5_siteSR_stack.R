# Targets list to assess site remote sensing visibility

# Set up python virtual environment ---------------------------------------

tar_source("py/pySetup.R")

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
                      "5_siteSR_stack/out/",
                      "5_siteSR_stack/collated/")
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
  
  # load, format, save yml as a csv, depends on confit_file target
  tar_target(
    name = p5_yml,
    command = format_yaml(yaml = p5_config_file)
  ),
  
  # load, format, save locations, depends on visible_sites target
  tar_target(
    name = p5_locs,
    command = {
      p5_visible_sites
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
  
  
  # Run Pekel Instance by WRS tile
  tar_target(
    name = p5_run_pekel,
    command = run_pekel_per_tile()
  ),
  
  # wait for all earth engine tasks to be completed
  tar_target(
    name = p5_pekel_tasks_complete,
    command = {
      p5_eeRun
      source_python("5_siteSR_stack/py/poi_wait_for_completion.py")
    },
    packages = "reticulate"
  ),

  
  # to mimic decisions in riverSR, we'll use a cutoff of 30m here
  tar_target(
    name = p5_visible_sites,
    command = {
      visible_sites <- p5_sites_with_distance_to_shore %>% 
        # coerce unit object to numeric for filtering and writing the csv
        mutate(dist_to_shore = as.numeric(dist_to_shore)) %>% 
        filter(dist_to_shore >= 30) %>% 
        st_drop_geometry() %>% 
        rowid_to_column()
      # save the file and return the dataframe
      write_csv(visible_sites, "5_siteSR_stack/out/visible_sites.csv")
      visible_sites
    },
    packages = c("sf", "grid", "tidyverse")
  ),
  
  # run the Landsat pull as function per tile
  tar_target(
    name = p5_eeRun,
    command = run_GEE_per_tile(p5_WRS_tiles),
    pattern = map(p5_WRS_tiles),
    packages = "reticulate"
  ),
  
  # wait for all earth engine tasks to be completed
  tar_target(
    name = p5_ee_tasks_complete,
    command = {
      p5_eeRun
      source_python("5_siteSR_stack/py/poi_wait_for_completion.py")
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
                               version_identifier = p5_yml$run_date)
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