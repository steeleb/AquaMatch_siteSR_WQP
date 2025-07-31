# Targets list to gather Landsat stack at WQP site locations

# Source targets functions ------------------------------------------------

tar_source(files = "d_qa_stack/src/")


# Define {targets} workflow -----------------------------------------------

# target objects in workflow
d_qa_stack <- list(
  
  tar_target(
    name = d_check_dir_structure,
    command = {
      # make directories if needed
      directories = c("d_qa_stack/qa/",
                      "d_qa_stack/out/",
                      "d_qa_stack/export/")
      walk(directories, function(dir) {
        if(!dir.exists(dir)){
          dir.create(dir)
        }
      })
    },
    cue = tar_cue("always"),
    deployment = "main",
  ),
  
  tar_target(
    name = d_mission_identifiers,
    command = tibble(mission_id = c("LT04", "LT05", "LE07", "LC08", "LC09"),
                     mission_names = c("Landsat 4", "Landsat 5", "Landsat 7", "Landsat 8", "Landsat 9"))
  ),
  
  # set dswe types
  tar_target(
    name = d_dswe_types,
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
    }
  ), 
  
  tar_target(
    name = d_metadata_files,
    command = {
      c_collated_siteSR_files
      list.files(file.path("c_siteSR_stack/mid/", b_yml$run_date), 
                         full.names = TRUE) %>% 
      .[grepl("metadata", .)]
    }
  ),
  
  # qa the siteSR stacks like we do with lakeSR
  tar_target(
    name = d_qa_Landsat_files,
    command = {
      d_check_dir_structure
      qa_and_document_LS(mission_info = d_mission_identifiers,
                         dswe = d_dswe_types, 
                         metadata_files = d_metadata_files,
                         collated_files = c_collated_siteSR_files)
    },
    packages = c("arrow", "data.table", "tidyverse", "ggrepel", "viridis", "stringi"),
    pattern = cross(d_mission_identifiers, d_dswe_types),
    deployment = "main" # can not be run multi-core
  ),
  
  # now add siteSR id, and necessary information for data storage, save as .csv
  tar_target(
    name = d_qa_files_list,
    command = {
      d_qa_Landsat_files
      list.files("d_qa_stack/qa/", 
                 full.names = TRUE,
                 pattern = ".feather")
    },
    cue = tar_cue("always")
  ),
  
  tar_target(
    name = d_Landsat_files_for_export,
    command = prep_Landsat_for_export(file = d_qa_files_list,
                                      file_type = "csv",
                                      out_path = "d_qa_stack/export/"),
    pattern = map(d_qa_files_list),
    packages = c("arrow", "data.table", "tidyverse", "tools", "stringi"),
    deployment = "main"
  ),
  
  tar_target(
    name = d_Landsat_metadata_for_export,
    command = prep_Landsat_for_export(file = d_metadata_files,
                                      file_type = "csv", 
                                      out_path = "d_qa_stack/export/"),
    pattern = map(d_metadata_files),
    packages = c("arrow", "data.table", "tidyverse", "tools", "stringi")
  ),
  
  tar_target(
    name = d_make_Landsat_feather_files,
    command = {
      if (!dir.exists(file.path("d_qa_stack/out/", b_yml$run_date))) {
        dir.create(file.path("d_qa_stack/out/", b_yml$run_date))
      }
      fns  <- d_qa_files_list[grepl(d_mission_identifiers$mission_id, d_qa_files_list)]
      fns_dswe <- fns[grepl(paste0(d_dswe_types, "_"), fns)]
      
      out_fp <- paste0("d_qa_stack/out/", 
                       b_yml$run_date, 
                       "/siteSR_", 
                       str_replace(d_mission_identifiers$mission_names," ", ""),
                       "_", d_dswe_types, "_", 
                       b_yml$run_date, ".feather")
      
      # create a temp directory for the temporary Arrow dataset
      temp_dataset_dir <- tempfile("arrow_ds_")
      dir.create(temp_dataset_dir)
      
      # these files need to be processed by chunk to deal with memory issues
      walk(fns_dswe, function(fn) {
        # read chunk
        chunk <- read_feather(fn)
        
        # add source_file column to partition by
        chunk[, source_file := tools::file_path_sans_ext(basename(fn))]
        
        # write chunk using partitioning (otherwise we hit memory issues)
        write_dataset(chunk,
                      path = temp_dataset_dir,
                      format = "feather",
                      partitioning = "source_file",
                      existing_data_behavior = "delete_matching")
      })
      
      # connect to the arrow-partitioned file
      ds <- open_dataset(temp_dataset_dir, format = "feather")
      
      # and grab all the data and write the feather file
      ds %>% 
        collect() %>% 
        select(-source_file) %>% 
        write_feather(., out_fp, compression = "lz4")
      
      # housekeeping
      unlink(temp_dataset_dir, recursive = TRUE)
      gc()
      Sys.sleep(5)
      
      # return filepath
      out_fp
    },
    pattern = cross(d_dswe_types, d_mission_identifiers),
    packages = c("arrow", "data.table", "tidyverse"),
    deployment = "main" # these are huge, so make sure this runs solo
  )
  
)

# if configuration is to update and share on Drive, add these targets to the d 
# list
if (config::get(config = general_config)$update_and_share) {
  
  d_qa_stack <- list(
    
    d_qa_stack,
    
    tar_target(
      name = d_check_Drive_siteSR_folder,
      command =  {
        check_drive_parent_folder
        tryCatch({
          drive_auth(siteSR_config$google_email)
          parent_folder <- siteSR_config$drive_project_folder
          version_path <- paste0(siteSR_config$drive_project_folder, 
                                 paste0("siteSR_qa_v", b_yml$run_date, "/"))
          drive_ls(version_path)
        }, error = function(e) {
          # if there is an error, check both the 'collated_raw' folder and the 'version'
          # folder
          drive_mkdir(path = parent_folder, name = paste0("siteSR_qa_v", b_yml$run_date))
        })
        return(version_path)
      },
      packages = "googledrive",
      cue = tar_cue("always")    
    ),
    
    tar_target(
      name = d_send_siteSR_files_to_drive,
      command = export_single_file(file_path = d_Landsat_files_for_export,
                                   drive_path = d_check_Drive_siteSR_folder,
                                   google_email = siteSR_config$google_email),
      packages = c("tidyverse", "googledrive"),
      pattern = map(d_Landsat_files_for_export)
    ),
    
    tar_target(
      name = d_send_metadata_files_to_drive,
      command = export_single_file(file_path = d_Landsat_metadata_for_export,
                                   drive_path = d_check_Drive_siteSR_folder,
                                   google_email = siteSR_config$google_email),
      packages = c("tidyverse", "googledrive"),
      pattern = map(d_Landsat_metadata_for_export)
    ),
    
    tar_target(
      name = d_save_siteSR_drive_info,
      command = {
        drive_ids_site <- d_send_siteSR_files_to_drive %>% 
          select(name, id)
        drive_ids_meta <- d_send_metadata_files_to_drive %>% 
          select(name, id)
        drive_ids <- bind_rows(drive_ids_site, drive_ids_meta) 
        write_csv(drive_ids,
                  paste0("d_qa_stack/out/siteSR_qa_files_drive_ids_v",
                         b_yml$run_date,
                         ".csv"))
        drive_ids
      },
      packages = c("tidyverse", "googledrive")
    ), 
    
    tar_target(
      name = d_send_feather_files_to_Drive,
      command = export_single_file(file_path = d_make_Landsat_feather_files,
                                   drive_path = d_check_Drive_siteSR_folder,
                                   google_email = siteSR_config$google_email),
      packages = c("tidyverse", "googledrive"),
      pattern = map(d_make_Landsat_feather_files)
    ),
    
    tar_target(
      name = d_save_feather_drive_info,
      command = {
        d_check_dir_structure
        drive_ids <- d_send_feather_files_to_Drive %>% 
          select(name, id)
        write_csv(drive_ids,
                  paste0("d_qa_stack/out/siteSR_Landsat_QA_feather_files_drive_ids_v",
                         b_yml$run_date,
                         ".csv"))
        drive_ids
      },
      packages = c("tidyverse", "googledrive")
    )
    
  )
  
}

