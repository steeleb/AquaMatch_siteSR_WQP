# Created by use_targets()

# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)

# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)
library(reticulate)
library(crew)


# Set up crew controller for multicore processing ------------------------
controller_cores <- crew_controller_local(
  workers = parallel::detectCores()-1,
  seconds_idle = 12
)

# Set target options: ---------------------------------------

tar_option_set(
  # packages that {targets} need to run for this workflow
  packages = c("tidyverse", "sf"),
  memory = "transient",
  garbage_collection = TRUE,
  # set up crew controller
  controller = controller_cores
)



# Define targets workflow -------------------------------------------------

# Run the R scripts with custom functions:
tar_source(files = c(
  "src/",
  "4_compile_sites.R",
  "5_siteSR_stack.R"))

# The list of targets/steps
config_targets <- list(
  
  # General config ----------------------------------------------------------
  
  # Grab configuration information for the workflow run (config.yml)
  tar_target(
    name = p0_siteSR_config,
    # The config package does not like to be used with library()
    command = config::get(config = "admin_update"),
    cue = tar_cue("always"),
    priority = 1,
    deployment = "main"
  ),
  
  # Set Google Drive directory paths for parameter objects
  tar_target(
    name = p0_chla_output_path,
    command = paste0(p0_siteSR_config$drive_project_folder,
                     "chlorophyll/"),
    priority = 1,
    deployment = "main"
  ),
  
  tar_target(
    name = p0_sdd_output_path,
    command = paste0(p0_siteSR_config$drive_project_folder,
                     "sdd/"),
    priority = 1,
    deployment = "main"
  ), 

  tar_target(
    name = p0_doc_output_path,
    command = paste0(p0_siteSR_config$drive_project_folder,
                     "doc/"),
    priority = 1,
    deployment = "main"
  ), 
  
  # Check for Google Drive folder for siteSR output path, create it if it
  # doesn't exist
  tar_target(
    name = p0_check_drive_parent_folder,
    command = tryCatch({
      drive_auth(p0_siteSR_config$google_email)
      drive_ls(p0_siteSR_config$drive_project_folder)
    }, error = function(e) {
      drive_mkdir(str_sub(p0_siteSR_config$drive_project_folder, 1, -2))  
    }),
    packages = "googledrive",
    cue = tar_cue("always"),
    error = "stop",
    priority = 1,
    deployment = "main"
  ),
  
  # Check for chlorophyll subfolder, create if not present
  tar_target(
    name = p0_check_chla_drive,
    command = {
      p0_check_drive_parent_folder
      tryCatch({
        drive_auth(p0_siteSR_config$google_email)
        drive_ls(p0_chla_output_path)
      }, error = function(e) {
        # if the outpath doesn't exist, create it along with a "stable" subfolder
        drive_mkdir(name = "chlorophyll",
                    path = p0_siteSR_config$drive_project_folder)
        drive_mkdir(name = "stable",
                    path = paste0(p0_siteSR_config$drive_project_folder,
                                  "chlorophyll"))
      })
    },
    packages = "googledrive",
    cue = tar_cue("always"),
    error = "stop",
    priority = 1,
    deployment = "main"
  ),
  
  # Check for sdd subfolder, create if not present
  tar_target(
    name = p0_check_sdd_drive,
    command = {
      p0_check_drive_parent_folder
      tryCatch({
        drive_auth(p0_siteSR_config$google_email)
        drive_ls(p0_sdd_output_path)
      }, error = function(e) {
        # if the outpath doesn't exist, create it along with a "stable" subfolder
        drive_mkdir(name = "sdd",
                    path = p0_siteSR_config$drive_project_folder)
        drive_mkdir(name = "stable",
                    path = paste0(p0_siteSR_config$drive_project_folder,
                                  "sdd"))
      })
    },
    packages = "googledrive",
    cue = tar_cue("always"),
    error = "stop",
    priority = 1,
    deployment = "main"
  ),
  
  # Check for doc subfolder, create if not present
  tar_target(
    name = p0_check_doc_drive,
    command = {
      p0_check_drive_parent_folder
      tryCatch({
        drive_auth(p0_siteSR_config$google_email)
        drive_ls(p0_doc_output_path)
      }, error = function(e) {
        # if the outpath doesn't exist, create it along with a "stable" subfolder
        drive_mkdir(name = "doc",
                    path = p0_siteSR_config$drive_project_folder)
        drive_mkdir(name = "stable",
                    path = paste0(p0_siteSR_config$drive_project_folder,
                                  "doc"))
      })
    },
    packages = "googledrive",
    cue = tar_cue("always"),
    error = "stop",
    priority = 1,
    deployment = "main"
  ),
  
  # Import targets from the previous pipeline -------------------------------
  
  # Grab location of the local {targets} WQP download pipeline OR error if
  # the location doesn't exist yet
  tar_target(
    name = p0_AquaMatch_harmonize_WQP_directory,
    command = if(dir.exists(p0_siteSR_config$harmonize_repo_directory)) {
      p0_siteSR_config$harmonize_repo_directory
    } else {
      # Throw an error if the pipeline does not exist
      stop("The WQP download pipeline is not at the location specified in the 
           config.yml file. Check the location specified as `harmonize_repo_directory`
           in the config.yml file and rerun the pipeline.")
    },
    cue = tar_cue("always"),
    priority = 1,
    deployment = "main"
  ),
  
  
  # Retrieve Drive IDs ------------------------------------------------------
  
  # Google Drive IDs of exported files from the download pipeline
  
  tar_file_read(
    name = p3_chla_drive_ids,
    command = {
      if(grepl("chla", p0_siteSR_config$parameters)) {
        paste0(p0_AquaMatch_harmonize_WQP_directory,
               "3_harmonize/out/chl_drive_ids.csv") 
      } else {
        NULL
      }
    },
    cue = tar_cue("always"),
    read = read_csv(file = !!.x),
    priority = 1,
    deployment = "main"
  ),
  
  tar_file_read(
    name = p3_sdd_drive_ids,
    command = {
      if(grepl("sdd", p0_siteSR_config$parameters)) {
        paste0(p0_AquaMatch_harmonize_WQP_directory,
               "3_harmonize/out/sdd_drive_ids.csv") 
      } else {
        NULL
      }
    },
    cue = tar_cue("always"),
    read = read_csv(file = !!.x),
    priority = 1,
    deployment = "main"
  ),

  tar_file_read(
    name = p3_doc_drive_ids,
    command = {
      if(grepl("doc", p0_siteSR_config$parameters)) {
        paste0(p0_AquaMatch_harmonize_WQP_directory,
               "3_harmonize/out/doc_drive_ids.csv") 
      } else {
        NULL
      }
    },
    cue = tar_cue("always"),
    read = read_csv(file = !!.x),
    priority = 1,
    deployment = "main"
  ),
  
  # Google Drive IDs of exported files from the harmonize pipeline
  # Download files from Google Drive ----------------------------------------
  
  # chlorophyll site list
  tar_target(
    name = p3_chla_harmonized_site_info,
    command = {
      if (grepl("chla", p0_siteSR_config$parameter)) {
        retrieve_data(target = "p3_chla_harmonized_site_info",
                      id_df = p3_chla_drive_ids,
                      local_folder = "4_compile_sites/in",
                      stable = p0_siteSR_config$chla_use_stable,
                      google_email = p0_siteSR_config$google_email,
                      stable_date = p0_siteSR_config$chla_stable_date) 
      } else {
        NULL
      }
    },
    packages = c("tidyverse", "googledrive"),
    priority = 1,
    deployment = "main"
  ),
  
  # SDD site list
  tar_target(
    name = p3_sdd_harmonized_site_info,
    command = {
      if (grepl("sdd", p0_siteSR_config$parameter)) {
        retrieve_data(target = "p3_sdd_harmonized_site_info",
                      id_df = p3_sdd_drive_ids,
                      local_folder = "4_compile_sites/in",
                      stable = p0_siteSR_config$sdd_use_stable,
                      google_email = p0_siteSR_config$google_email,
                      stable_date = p0_siteSR_config$sdd_stable_date)
      } else {
        NULL
      }
    },
    packages = c("tidyverse", "googledrive"),
    priority = 1,
    deployment = "main"
  ),
  
  # DOC site list
  tar_target(
    name = p3_doc_harmonized_site_info,
    command = {
      if (grepl("doc", p0_siteSR_config$parameter)) {
        retrieve_data(target = "p3_doc_harmonized_site_info",
                      id_df = p3_doc_drive_ids,
                      local_folder = "4_compile_sites/in",
                      stable = p0_siteSR_config$doc_use_stable,
                      google_email = p0_siteSR_config$google_email,
                      stable_date = p0_siteSR_config$doc_stable_date)
      } else {
        NULL
      }
    },
    packages = c("tidyverse", "googledrive"),
    priority = 1,
    deployment = "main"
  )
  
  
)

# Full targets list
c(config_targets,
  p4_compile_sites,
  p5_siteSR_stack)
