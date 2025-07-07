# Targets list to gather Landsat stack at WQP site locations

# Source targets functions ------------------------------------------------

tar_source(files = "c_siteSR_stack/src/")


# Define {targets} workflow -----------------------------------------------

if (config::get(config = general_config)$run_GEE) {
  
  # Set up python virtual environment ---------------------------------------
  tar_source("python/pySetup.R")
  
  # target objects in workflow
  c_siteSR_stack <- list(
    
    # general configuration ---------------------------------------------------
    
    # make directories if needed
    tar_target(
      name = c_check_dir_structure,
      command = {
        directories = c("c_siteSR_stack/mid/",
                        "c_siteSR_stack/down/",
                        "c_siteSR_stack/run/",
                        "c_siteSR_stack/out/")
        walk(directories, function(dir) {
          if(!dir.exists(dir)){
            dir.create(dir)
          }
        })
      },
      cue = tar_cue("always")
    ),
    
    # save the output of RS-visible sites to this directory
    tar_target(
      name = c_store_visible_sites_for_GEE,
      command = write_csv(b_visible_sites, "c_siteSR_stack/run/visible_locs_with_WRS.csv")
    ),
    
    # Check for GEE export subfolder, create if not present
    tar_target(
      name = c_check_siteSR_folder,
      command = {
        check_drive_parent_folder
        tryCatch({
          drive_auth(b_yml$google_email)
          drive_ls(paste0("siteSR_v", b_yml$run_date))
        }, error = function(e) {
          # if the outpath doesn't exist, create it
          drive_mkdir(name = paste0("siteSR_v", b_yml$run_date),
                      path = b_yml$proj_parent_folder)
        })
      },
      packages = "googledrive",
      cue = tar_cue("always")
    ),
    
    
    # make siteSR pull ----------------------------------------------
    
    # get WRS pathrow
    tar_target(
      name = c_WRS_pathrows,
      command = get_WRS_pathrows(detection_method = "site", 
                                 yaml = b_yml, 
                                 locs = b_visible_sites,
                                 out_folder = "c_siteSR_stack/out/"),
      packages = c("readr", "sf"),
    ),
    
    # check to see that all sites and buffers are completely contained by each pathrow
    # and assign wrs path-rows for all sites based on configuration buffer.
    tar_target(
      name = c_siteSR_locs_filtered,
      command = check_if_fully_within_pr(WRS_pathrow = c_WRS_pathrows, 
                                         locations = b_visible_sites, 
                                         yml = b_yml),
      pattern = map(c_WRS_pathrows),
      packages = c("tidyverse", "sf", "arrow")
    ),
    
    tar_file(
      name = c_siteSR_script,
      command = "c_siteSR_stack/py/run_siteSR_per_pathrow.py"
    ), 
    
    # Run EE siteSR pull pull 
    tar_target(
      name = c_run_siteSR,
      command = {
        b_yml
        c_siteSR_script
        c_siteSR_locs_filtered
        run_siteSR_per_pathrow(WRS_pathrow = c_WRS_pathrows)
      },
      pattern = c_WRS_pathrows,
      packages = "reticulate",
      deployment = "main"
    ),
    
    # wait for all earth engine tasks to be completed
    tar_target(
      name = c_siteSR_tasks_complete,
      command = {
        c_run_siteSR
        source_python("c_siteSR_stack/py/siteSR_wait_for_completion.py")
      },
      packages = "reticulate",
      deployment = "main"
    ),
    
    # since we can't easily track if tasks have failed, and we send a lot of tasks
    # in this process, let's check for any failed tasks and add them to 
    # c_siteSR_stack/out/GEE_failed_tasks_vRUN_DATE.txt
    
    tar_file(
      name = c_failed_tasks_script,
      command = "c_siteSR_stack/py/check_for_failed_tasks.py"
    ), 
    
    tar_target(
      name = c_check_for_failed_tasks,
      command = {
        c_siteSR_tasks_complete
        source_python(c_failed_tasks_script)
      },
      packages = "reticulate",
      deployment = "main",
      error = "continue" # sometimes this will error out if you've completed a lot 
      # tasks in your ee-project
    ),
    
    
    # download/collated siteSR stacks -----------------------------------------
    
    # download siteSR files
    tar_target(
      name = c_siteSR_contents,
      command = {
        # make sure that siteSR tasks complete
        c_siteSR_tasks_complete
        # authorize Google
        drive_auth(email = b_yml$google_email)
        # create the folder path as proj_folder and run_date
        drive_folder <- paste0(b_yml$proj_parent_folder, "siteSR_v", b_yml$run_date)
        # get a list of files in the project file
        drive_ls(path = drive_folder) %>% 
          select(name, id)
      },
      packages = c("tidyverse", "googledrive")
    ), 
    
    # target with list of data segments:
    tar_target(
      name = c_data_segments,
      command = c("metadata", "LS457", "LS89"),
      deployment = "main"
    ),
    
    # set mission groups
    tar_target(
      name = c_mission_groups,
      command = c("LS457", "LS89"),
      deployment = "main"
    ),
    
    # set dswe types
    tar_target(
      name = c_dswe_types,
      command = {
        dswe = NULL
        if (grepl("1", b_yml$DSWE_setting)) {
          dswe = c(dswe, "DSWE1")
        } 
        if (grepl("1a", b_yml$DSWE_setting)) {
          dswe = c(dswe, "DSWE1a")
        } 
        if (grepl("3", b_yml$DSWE_setting)) {
          dswe = c(dswe, "DSWE3")
        } 
        dswe
      },
      deployment = "main"
    ), 
    
    # download all files, branched by data segments
    tar_target(
      name = c_download_files,
      command = download_csvs_from_drive(local_folder = "c_siteSR_stack/down/",
                                         file_type = c_data_segments,
                                         drive_contents = c_siteSR_contents,
                                         yml = b_yml,
                                         depends = c_check_dir_structure),
      packages = c("tidyverse", "googledrive"),
      pattern = map(c_data_segments)
    ),
    
    # collate all files - these end up being pretty big without filtering, so we 
    # need to break them up as metadata, then site pulls. The site pulls also need
    # to be split by dswe type and mission, otherwise the files are too big for R
    # to handle
    
    # make metadata file - this doesn't require filtering of dswe or mission
    tar_target(
      name = c_make_collated_metadata,
      command = collate_csvs_from_drive(file_type = "metadata",
                                        yml = b_yml,
                                        dswe = NULL,
                                        separate_missions = FALSE,
                                        depends = c_download_files),
      packages = c("data.table", "tidyverse", "arrow")
    ),
    
    # make target of first two digits of PR - LS7 is too large to only subset
    # by mission group and dswe, so apply to all missions.
    tar_target(
      name = c_WRS_prefix,
      command = unique(str_sub(b_WRS_pathrows, 1, 2))
    ),
    
    tar_target(
      name = c_make_collated_point_files,
      command = collate_csvs_from_drive(file_type = c_mission_groups,
                                        yml = b_yml,
                                        wrs_prefix = c_WRS_prefix,
                                        dswe = c_dswe_types,
                                        separate_missions = TRUE,
                                        depends = c_download_files),
      packages = c("data.table", "tidyverse", "arrow"),
      pattern = cross(c_mission_groups, c_dswe_types, c_WRS_prefix),
      deployment = "main"
    ),
    
    # Save collated files to Drive, create csv with ids -----------------------
    
    # get list of files to save to drive
    tar_target(
      name = c_collated_siteSR_files,
      command = {
        c_make_collated_metadata
        c_make_collated_point_files
        list.files(file.path("c_siteSR_stack/mid/",
                             b_yml$run_date),
                   full.names = TRUE)
      }
    ),
    
    tar_target(
      name = c_check_Drive_collated_folder,
      command =  {
        check_drive_parent_folder
        tryCatch({
          drive_auth(b_yml$google_email)
          if (b_yml$proj_parent_folder != "") {
            parent_folder <- b_yml$proj_parent_folder
            version_path <- paste0(b_yml$proj_parent_folder,
                                   paste0("collated_raw_v", b_yml$run_date, "/"))
            
          } else {
            parent_folder <- b_yml$proj_folder
            version_path <- paste0(b_yml$proj_folder,
                                   paste0("collated_raw_v", b_yml$run_date, "/"))
          }
          # check for doubles!
          drive_ls(version_path)
        }, error = function(e) {
          # if there is an error, check both the 'collated_raw' folder and the 'version'
          # folder
          drive_mkdir(path = parent_folder, name = paste0("collated_raw_v", b_yml$run_date))
        })
        return(version_path)
      },
      packages = "googledrive",
      cue = tar_cue("always")
    ),
    
    tar_target(
      name = c_send_collated_files_to_drive,
      command = export_single_file(file_path = c_collated_siteSR_files,
                                   drive_path = c_check_Drive_collated_folder,
                                   google_email = b_yml$google_email),
      packages = c("tidyverse", "googledrive"),
      pattern = c_collated_siteSR_files
    ),
    
    tar_target(
      name = c_save_collated_Drive_info,
      command = {
        drive_ids <- c_send_collated_files_to_drive %>%
          select(name, id)
        write_csv(drive_ids,
                  "c_siteSR_stack/out/raw_collated_files_drive_ids.csv")
        drive_ids
      },
      packages = c("tidyverse", "googledrive")
    )
    
  )
  
} else {
  
  c_siteSR_stack <- list(
    
    # make directories if needed
    tar_target(
      name = c_check_dir_structure,
      command = {
        directories = c("c_siteSR_stack/mid/")
        walk(directories, function(dir) {
          if(!dir.exists(dir)){
            dir.create(dir)
          }
        })
      },
      cue = tar_cue("always")
    ),
    
    tar_file_read(
      name = c_save_collated_Drive_info,
      command = "c_siteSR_stack/out/raw_collated_files_drive_ids.csv",
      read = read_csv(!!.x)
    ),
    
    tar_target(
      name = c_collated_siteSR_files,
      command = {
        c_check_dir_structure
        retrieve_data(id_df = c_save_collated_Drive_info, 
                      local_folder = paste0("c_siteSR_stack/mid/",
                                            siteSR_config$pekel_gee_version), 
                      google_email = siteSR_config$google_email)
        list.files(path = paste0("c_siteSR_stack/mid/",
                                 siteSR_config$pekel_gee_version), 
                   full.names = TRUE)
      },
      packages = c("tidyverse", "googledrive")
    )
    
  )
  
}



