# Targets list to gather Landsat stack at WQP site locations


# Source targets functions ------------------------------------------------

tar_source(files = "5_determine_RS_visibility/src/")
tar_source(files = "6_siteSR_stack/src/")


# Define {targets} workflow -----------------------------------------------

# target objects in workflow
p6_siteSR_stack <- list(
  
  # general configuration ---------------------------------------------------
  
  # make directories if needed
  tar_target(
    name = p6_check_dir_structure,
    command = {
      directories = c("6_siteSR_stack/mid/",
                      "6_siteSR_stack/down/",
                      "6_siteSR_stack/run/",
                      "6_siteSR_stack/out/")
      walk(directories, function(dir) {
        if(!dir.exists(dir)){
          dir.create(dir)
        }
      })
    },
    cue = tar_cue("always")
  ),
  
  # Check for GEE export subfolder, create if not present
  tar_target(
    name = p6_check_siteSR_folder,
    command = {
      p0_check_drive_parent_folder
      tryCatch({
        drive_auth(p0_siteSR_config$google_email)
        drive_ls(paste0("siteSR_v", p5_yml$run_date))
      }, error = function(e) {
        # if the outpath doesn't exist, create it
        drive_mkdir(name = paste0("siteSR_v", p5_yml$run_date),
                    path = p0_siteSR_config$drive_project_folder)
      })
    },
    packages = "googledrive",
    cue = tar_cue("always")
  ),
  
  
  # assess visibility of sites ----------------------------------------------
  
  # get WRS pathrow
  tar_target(
    name = p6_WRS_pathrows,
    command = get_WRS_pathrows(detection_method = "site", 
                               yaml = p5_yml, 
                               locs = p5_visible_sites,
                               out_folder = "6_siteSR_stack/out/"),
    packages = c("readr", "sf"),
  ),
  
  # check to see that all sites and buffers are completely contained by each pathrow
  # and assign wrs path-rows for all sites based on configuration buffer.
  tar_target(
    name = p6_siteSR_locs_filtered,
    command = check_if_fully_within_pr(WRS_pathrow = p6_WRS_pathrows, 
                                       locations = p5_visible_sites, 
                                       yml = p5_yml),
    pattern = map(p6_WRS_pathrows),
    packages = c("tidyverse", "sf", "arrow")
  ),
  
  tar_file(
    name = p6_siteSR_script,
    command = "6_siteSR_stack/py/run_siteSR_per_pathrow.py"
  ), 
  
  # Run EE siteSR pull pull 
  tar_target(
    name = p6_run_siteSR,
    command = {
      p5_yml
      p6_siteSR_script
      p6_siteSR_locs_filtered
      run_siteSR_per_pathrow(WRS_pathrow = p6_WRS_pathrows)
    },
    pattern = p6_WRS_pathrows,
    packages = "reticulate",
    deployment = "main"
  ),
  
  # wait for all earth engine tasks to be completed
  tar_target(
    name = p6_siteSR_tasks_complete,
    command = {
      p6_run_siteSR
      source_python("5_determine_RS_visiblity/py/wait_for_completion.py")
    },
    packages = "reticulate",
    deployment = "main"
  ),
  
  # download siteSR files
  
  tar_target(
    name = p6_siteSR_contents,
    command = {
      # make sure that siteSR tasks complete
      p6_siteSR_tasks_complete
      # authorize Google
      drive_auth(email = p5_yml$google_email)
      # create the folder path as proj_folder and run_date
      drive_folder = paste0(p5_yml$proj_parent_folder, "siteSR_v", p5_yml$run_date)
      # get a list of files in the project file
      drive_ls(path = drive_folder) %>% 
        select(name, id)
    },
    packages = "googledrive"
  )
 
)
