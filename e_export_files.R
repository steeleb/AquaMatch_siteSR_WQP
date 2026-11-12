# Targets list to export the final siteSR files (and share them on Drive)

# Define {targets} workflow -----------------------------------------------

# the final files are only made if the configuration is to update and share 
# files on Drive. Otherwise this group is an empty list.
e_run_GEE <- config::get(config = general_config)$run_GEE

if (config::get(config = general_config)$update_and_share) {
  
  # target objects in workflow
  e_export_files <- list(
    
    # site information for all sites compiled upstream, with a flag for whether 
    # the site is RS-visible, and the grouping/extraction site information for the
    # visible sites. This is the companion to the pull data, which are not
    # annotated with site-level information.
    tar_target(
      name = e_site_info,
      command = {
        a_sites_with_NHD_info %>% 
          mutate(huc2 = str_sub(assigned_HUC, 1, 2),
                 flag_RS_visible = as.integer(siteSR_id %in% d_crosswalk$siteSR_id)) %>% 
          left_join(d_crosswalk, by = "siteSR_id") %>% 
          mutate(flag_grouped_extraction = as.integer(n_sites_in_cluster > 1)) %>% 
          relocate(siteSR_id, flag_RS_visible, huc2)
      },
      packages = "tidyverse"
    ),
  
    tar_target(
      name = e_site_info_file,
      command = {
        d_check_dir_structure
        fp <- file.path("d_qa_stack/export/",
                        paste0("siteSR_site_information_v", b_yml$run_date, ".csv"))
        write_csv(e_site_info, fp)
        fp
      },
      format = "file",
      packages = "tidyverse"
    ),

    # make a list of the collated and sorted files created
    tar_files(
      name = e_all_sorted_Landsat_files,
      command = as.vector(c(d_Landsat4_collated_data, d_collated_Landsat5_by_huc2,
                            d_collated_Landsat7_by_huc2, d_collated_Landsat8_by_huc2,
                            d_Landsat9_collated_data, d_Landsat_metadata_formatted,
                            # site information, including RS visibility and grouping
                            e_site_info_file,
                            # crosswalk of siteSR_id to extraction site (run_GEE only)
                            if (d_run_GEE) e_site_crosswalk_file))
    ),
  
    tar_target(
      name = e_make_Landsat_feather_files,
      command = {
        # create version folder for output
        if (!dir.exists(file.path("d_qa_stack/out/", b_yml$run_date))) {
          dir.create(file.path("d_qa_stack/out/", b_yml$run_date))
        }
      
        # filter for identifier/dswe
        fns  <- e_all_sorted_Landsat_files[grepl(gsub(" ", "", d_mission_identifiers$mission_names),
                                                 e_all_sorted_Landsat_files)]
        fns_dswe <- fns[grepl(paste0(d_dswe_types, "_"), fns)]
      
        # create the output filepath
        out_fp <- paste0("d_qa_stack/out/", 
                         b_yml$run_date, 
                         "/siteSR_", 
                         str_replace(d_mission_identifiers$mission_names," ", ""),
                         "_", d_dswe_types, "_", 
                         b_yml$run_date, ".feather")
      
        # check to see if this is a single file, or multiple and needs additional
        # data handling
        if (length(fns_dswe) > 1) {
          # create a temp directory for the temporary Arrow dataset
          temp_dataset_dir <- tempfile("arrow_ds_")
          dir.create(temp_dataset_dir)
          # these files need to be processed by chunk to deal with memory issues
          walk(fns_dswe, function(fn) {
            # read chunk
            chunk <- fread(fn)
            setDT(chunk)
          
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
        
        } else {
        
          data <- fread(fns_dswe)
          write_feather(data, out_fp, compression = "lz4")
        
        }
      
        # return filepath
        out_fp
      },
      pattern = cross(d_dswe_types, d_mission_identifiers),
      packages = c("arrow", "data.table", "tidyverse"),
      deployment = "main" # these are huge, so make sure this runs solo
    )
    
  )
  
  # when sites were grouped before acquisition, the data are keyed to the site 
  # that was sent to EE (`extraction_siteSR_id`). Save the crosswalk from every 
  # RS-visible siteSR_id to its extraction site, along with the flags at the 
  # extraction site, so that the data can be joined to all sites.
  if (e_run_GEE) {
    
    e_export_files <- list(
      
      e_export_files,
      
      tar_target(
        name = e_site_crosswalk_file,
        command = {
          d_check_dir_structure
          fp <- file.path("d_qa_stack/export/",
                          paste0("siteSR_extraction_site_crosswalk_v", 
                                 b_yml$run_date, 
                                 ".csv"))
          write_csv(c_site_crosswalk, fp)
          fp
        },
        format = "file"
      )
      
    )
    
  }
  
  # Drive upload
  e_export_files <- list(
    
    e_export_files,
    
    tar_target(
      name = e_check_Drive_siteSR_folder,
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
      name = e_send_siteSR_files_to_drive,
      command = export_single_file(file_path = e_all_sorted_Landsat_files,
                                   drive_path = e_check_Drive_siteSR_folder,
                                   google_email = siteSR_config$google_email),
      packages = c("tidyverse", "googledrive"),
      pattern = map(e_all_sorted_Landsat_files),
      cue = tar_cue("always")
    ),
    
    tar_target(
      name = e_save_siteSR_drive_info,
      command = {
        drive_ids <- e_send_siteSR_files_to_drive %>% 
          select(name, id) 
        write_csv(drive_ids,
                  paste0("d_qa_stack/out/siteSR_qa_files_drive_ids_v",
                         b_yml$run_date,
                         ".csv"))
        drive_ids
      },
      packages = c("tidyverse", "googledrive"),
      cue = tar_cue("always")
    ), 
    
    tar_target(
      name = e_send_feather_files_to_Drive,
      command = export_single_file(file_path = e_make_Landsat_feather_files,
                                   drive_path = e_check_Drive_siteSR_folder,
                                   google_email = siteSR_config$google_email),
      packages = c("tidyverse", "googledrive"),
      pattern = map(e_make_Landsat_feather_files),
      cue = tar_cue("always")
    ),
    
    tar_target(
      name = e_save_feather_drive_info,
      command = {
        d_check_dir_structure
        drive_ids <- e_send_feather_files_to_Drive %>% 
          select(name, id)
        write_csv(drive_ids,
                  paste0("d_qa_stack/out/siteSR_Landsat_QA_feather_files_drive_ids_v",
                         b_yml$run_date,
                         ".csv"))
        drive_ids
      },
      packages = c("tidyverse", "googledrive"),
      cue = tar_cue("always")
    )
    
  )
  
} else {
  
  e_export_files <- list()
  
}
