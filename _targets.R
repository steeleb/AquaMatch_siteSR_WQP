# Created by use_targets()

# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)

# Set target options:
tar_option_set(
  packages = "tidyverse",
  memory = "transient",
  garbage_collection = TRUE
)

# Run the R scripts with custom functions:
tar_source(files = c(
  "src/",
  "4_compile_sites.R",
  "5_site_visibility.R",
  "6_siteSR_stack.R"))

# The list of targets/steps
config_targets <- list(
  
  # General config ----------------------------------------------------------
  
  # Grab configuration information for the workflow run (config.yml)
  tar_target(
    name = p0_siteSR_config,
    # The config package does not like to be used with library()
    command = config::get(config = "admin_update"),
    cue = tar_cue("always")
  ),
  
  # Import targets from the previous pipeline -------------------------------
  
  # Grab location of the local {targets} WQP download pipeline OR error if\
  # the location doesn't exist yet
  tar_target(
    name = p0_AquaMatch_harmonize_WQP_directory,
    command = if(dir.exists(p0_siteSR_config$download_repo_directory)){
      p0_siteSR_config$download_repo_directory
    } else if(!dir.exists(p0_siteSR_config)) {
      # Throw an error if the pipeline does not exist
      stop("The WQP harmonization pipeline is not at the specified location.")
    },
    cue = tar_cue("always")
  )#, 
  
  # Retrieve Drive IDs ------------------------------------------------------
  
  # Google Drive IDs of exported files from the harmonize pipeline 
  
  # tar_file_read(
  #   name = p3_chl_drive_ids,
  #   command = paste0(p0_AquaMatch_harmonize_WQP_directory,
  #                    "3_harmonize/out/chl_drive_ids.csv"),
  #   cue = tar_cue("always"),
  #   read = read_csv(file = !!.x)
  # ),
  # 
  # tar_file_read(
  #   name = p3_doc_drive_ids,
  #   command = paste0(p0_AquaMatch_harmonize_WQP_directory,
  #                    "3_harmonize/out/doc_drive_ids.csv"),
  #   cue = tar_cue("always"),
  #   read = read_csv(file = !!.x)
  # ), 
  
  # Retrieve Drive IDs ------------------------------------------------------
  
  # Google Drive IDs of exported files from the download pipeline
  
  # Site targets
  
  # Aggregated, harmonized parameter data
  
)

# Full targets list
c(config_targets)
