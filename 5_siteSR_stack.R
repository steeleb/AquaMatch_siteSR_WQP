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
  
  # general configuration ---------------------------------------------------
  
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
    priority = 1,
    deployment = "main"
  ),
  
  # read and track the config file
  tar_file_read(
    name = p5_config_file,
    command = yaml_file,
    read = read_yaml(!!.x),
    packages = "yaml",
    cue = tar_cue("always"),
    deployment = "main"
  ),
  
  # load, format, save yml as a csv, depends on config_file target
  tar_target(
    name = p5_yml,
    command = format_yaml(yaml = p5_config_file),
    deployment = "main"
  ),
  
  # Check for GEE export subfolder, create if not present
  tar_target(
    name = p5_check_GEE_folder,
    command = {
      p0_check_drive_parent_folder
      tryCatch({
        drive_auth(p0_siteSR_config$google_email)
        drive_ls(p5_yml$proj_folder)
      }, error = function(e) {
        # if the outpath doesn't exist, create it
        drive_mkdir(name = p5_yml$proj_folder,
                    path = p0_siteSR_config$drive_project_folder)
      })
    },
    packages = "googledrive",
    cue = tar_cue("always"),
    error = "stop",
    priority = 1,
    deployment = "main"
  ),
  
  # Check for GEE export subfolder, create if not present
  tar_target(
    name = p5_check_pekel_folder,
    command = {
      p0_check_drive_parent_folder
      tryCatch({
        drive_auth(p0_siteSR_config$google_email)
        drive_ls(paste0("pekel_v", p5_yml$run_date))
      }, error = function(e) {
        # if the outpath doesn't exist, create it
        drive_mkdir(name = paste0("pekel_v", p5_yml$run_date),
                    path = p0_siteSR_config$drive_project_folder)
      })
    },
    packages = "googledrive",
    cue = tar_cue("always"),
    error = "stop",
    priority = 1,
    deployment = "main"
  ),
  
  
  # locations and pathrows --------------------------------------------------
  
  # load, format, save locations, depends on p4_sites_with_NHD_attribution target
  tar_target(
    name = p5_locs,
    command = {
      p4_WQP_site_NHD_info
      grab_locs(yaml = p5_yml)
    },
    deployment = "main"
  ),
  
  # get WRS pathrow
  tar_target(
    name = p5_WRS_pathrows,
    command = get_WRS_pathrows(detection_method = "site", 
                               yaml = p5_yml, 
                               locs = p5_locs),
    packages = c("readr", "sf"),
    deployment = "main"
  ),
  
  # check to see that all sites and buffers are completely contained by each pathrow
  # and assign wrs path-rows for all sites based on configuration buffer.
  tar_target(
    name = p5_add_WRS_to_site,
    command = {
      check_for_containment(WRS_pathrow = p5_WRS_pathrows,
                            locations = p5_locs,
                            yaml = p5_yml)
    },
    pattern = map(p5_WRS_pathrows)
  ),
  
  # after pattern ran, make sure there is only one instance of each site, for 
  # pekel, we don't need to run every contained site in every WRS pathrow, just need
  # to use WRS pathrows as a map. 
  tar_target(
    name = p5_sites_for_pekel,
    command = {
      one_PR_per_site <- p5_add_WRS_to_site %>% 
        slice(1, .by = "id")
      write_csv(one_PR_per_site, "5_siteSR_stack/run/locs_with_WRS_for_pekel.csv")
      one_PR_per_site
    },
    deployment = "main"
  ),
  
  
  # assess visibility of sites ----------------------------------------------
  
  # Run pekel pull - this is broken up by 5k sites in the script, so it takes
  # a bit of time.
  tar_target(
    name = p5_run_pekel,
    command = {
      p5_sites_for_pekel
      p5_yml
      run_pekel_per_pathrow(WRS_pathrow = p5_WRS_pathrows)
    },
    pattern = p5_WRS_pathrows,
    packages = "reticulate",
    deployment = "main"
  ),
  
  # wait for all earth engine tasks to be completed
  tar_target(
    name = p5_pekel_tasks_complete,
    command = {
      p5_run_pekel
      source_python("5_siteSR_stack/py/wait_for_completion.py")
    },
    packages = "reticulate",
    deployment = "main"
  ),

  # download Pekel files
  
  tar_target(
    name = p5_pekel_contents,
    command = {
      # make sure that pekel tasks complete
      p5_pekel_tasks_complete
      # authorize Google
      drive_auth(email = p5_yml$google_email)
      # create the folder path as proj_folder and run_date
      drive_folder = paste0(p5_yml$proj_parent_folder, "pekel_v", p5_yml$run_date)
      # get a list of files in the project file
      drive_ls(path = drive_folder) %>% 
        select(name, id)
    },
    packages = "googledrive",
    deployment = "main"
  ),
  
  tar_target(
    name = p5_pekel_download,
    command = download_csvs_from_drive(local_folder = "5_siteSR_stack/down",
                                       file_type = "pekel",
                                       yml = p5_yml,
                                       drive_contents = p5_pekel_contents),
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
      test <- map(files, read_csv) %>% 
        bind_rows() %>% 
        select(id, occurrence_med, occurrence_max, occurrence_min) %>% 
        # add wrs info for proper join with site info
        left_join(., p5_sites_for_pekel) %>% 
        # add site info (on id/lat/lon/wrs)
        left_join(., p5_add_WRS_to_site) 
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
  
  # export this target for use in documentation, no need for this to be versioned at this time
  tar_target(
    name = p5_export_visible_sites,
    command = {
      p0_check_targets_drive
      export_single_target(target = p5_visible_sites,
                           drive_path = "~/aquamatch_siteSR_wqp/targets/",
                           stable = FALSE,
                           google_email = p5_yml$google_email,
                           date_stamp = p5_yml$run_date)
    },
    packages = c("tidyverse", "googledrive"),
    deployment = "main"
  )
  
)
