# Created by use_targets()

# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)
library(reticulate)
library(crew)

# Set up python virtual environment ---------------------------------------

tar_source("python/pySetup.R")


# Set general configuration setting: -----------------------------

general_config <- "default"


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
tar_source(c("4_compile_sites.R",
             "5_determine_RS_visibility.R",
             "6_siteSR_stack.R",
             "7_qa_stack.R"))

# and load the global functions
tar_source("src/")

# The list of targets/steps
config_targets <- list(
  
  # General config ----------------------------------------------------------
  
  # Grab configuration information for the workflow run (config.yml)
  tar_target(
    name = p0_siteSR_config,
    # The config package does not like to be used with library()
    command = config::get(config = general_config),
    cue = tar_cue("always")
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
    cue = tar_cue("always")
  ),
  
  # Check for targets subfolder, create if not present
  tar_target(
    name = p0_check_targets_drive,
    command = {
      p0_check_drive_parent_folder
      tryCatch({
        drive_auth(p0_siteSR_config$google_email)
        drive_ls(paste0(p0_siteSR_config$drive_project_folder, "targets/"))
      }, error = function(e) {
        # if the outpath doesn't exist, create it along with a "stable" subfolder
        drive_mkdir(name = "targets",
                    path = p0_siteSR_config$drive_project_folder)
      })
      return(paste0(p0_siteSR_config$drive_project_folder, "targets/"))
    },
    packages = "googledrive",
    cue = tar_cue("always")
  ),
  
  
  # Check for other pipelines -----------------------------------------------
  
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
    cue = tar_cue("always")
  ),
  
  # Retrieve Drive IDs from linked repositories -------------------------------
  
  # Google Drive IDs of exported files from the download/harmonize pipeline
  
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
    read = read_csv(file = !!.x)
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
    read = read_csv(file = !!.x)
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
    read = read_csv(file = !!.x)
  ),
  
  tar_file_read(
    name = p3_tss_drive_ids,
    command = {
      if(grepl("tss", p0_siteSR_config$parameters)) {
        paste0(p0_AquaMatch_harmonize_WQP_directory,
               "3_harmonize/out/tss_drive_ids.csv") 
      } else {
        NULL
      }
    },
    cue = tar_cue("always"),
    read = read_csv(file = !!.x)
  ),
  
  # Google Drive IDs of exported files from the harmonize pipeline
  # Download files from Google Drive ----------------------------------------
  
  # chlorophyll site list
  tar_target(
    name = p3_chla_harmonized_site_info,
    command = {
      if (grepl("chla", p0_siteSR_config$parameter)) {
        retrieve_target(target = "p3_chla_harmonized_site_info",
                        id_df = p3_chla_drive_ids,
                        local_folder = "4_compile_sites/in",
                        google_email = p0_siteSR_config$google_email,
                        date_stamp = p0_siteSR_config$chla_version_date) 
      } else {
        NULL
      }
    },
    packages = c("tidyverse", "googledrive")
  ),
  
  # SDD site list
  tar_target(
    name = p3_sdd_harmonized_site_info,
    command = {
      if (grepl("sdd", p0_siteSR_config$parameter)) {
        retrieve_target(target = "p3_sdd_harmonized_site_info",
                        id_df = p3_sdd_drive_ids,
                        local_folder = "4_compile_sites/in",
                        google_email = p0_siteSR_config$google_email,
                        date_stamp = p0_siteSR_config$sdd_version_date)
      } else {
        NULL
      }
    },
    packages = c("tidyverse", "googledrive")
  ),
  
  # DOC site list
  tar_target(
    name = p3_doc_harmonized_site_info,
    command = {
      if (grepl("doc", p0_siteSR_config$parameter)) {
        retrieve_target(target = "p3_doc_harmonized_site_info",
                        id_df = p3_doc_drive_ids,
                        local_folder = "4_compile_sites/in",
                        google_email = p0_siteSR_config$google_email,
                        date_stamp = p0_siteSR_config$doc_version_date)
      } else {
        NULL
      }
    },
    packages = c("tidyverse", "googledrive")
  ),  
  
  # TSS site list
  tar_target(
    name = p3_tss_harmonized_site_info,
    command = {
      if (grepl("tss", p0_siteSR_config$parameter)) {
        retrieve_target(target = "p3_tss_harmonized_site_info",
                        id_df = p3_tss_drive_ids,
                        local_folder = "4_compile_sites/in",
                        google_email = p0_siteSR_config$google_email,
                        date_stamp = p0_siteSR_config$tss_version_date)
      } else {
        NULL
      }
    },
    packages = c("tidyverse", "googledrive")
  )
  
)

# Full targets list
c(config_targets,
  p4_compile_sites,
  p5_determine_RS_visibility,
  p6_siteSR_stack,
  p7_qa_stack)
