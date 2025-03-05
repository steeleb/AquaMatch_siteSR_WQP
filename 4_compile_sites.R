# Targets list to compile sites and attribute each feature to a waterbody or
# flowline

# Define p4 group --------------------------------------------------------

# Source the functions that will be used to build the targets in p3_targets_list
tar_source(files = "4_compile_sites/src/")

if (general_config != "default") {
  
  p4_compile_sites <- list(
    
    # make directories if needed
    tar_target(
      name = p4_check_dir_structure,
      command = {
        directories = c("4_compile_sites/in/",
                        "4_compile_sites/mid/",
                        "4_compile_sites/out/",
                        "4_compile_sites/nhd/")
        walk(directories, function(dir) {
          if(!dir.exists(dir)){
            dir.create(dir)
          }
        })
      },
      cue = tar_cue("always"),
    ),
    
    # Get unique sites from parameter files -------------------------------------
    
    # Join all and pull distinct rows
    tar_target(
      name = p4_distinct_sites,
      command = {
        # combine across all site infos, but only retain distinct rows. 
        distinct <- bind_rows(list(p3_chla_harmonized_site_info, 
                                   p3_sdd_harmonized_site_info,
                                   p3_doc_harmonized_site_info,
                                   p3_tss_harmonized_site_info)) %>% 
          # need to coerce lat/lon to numeric in order to properly find
          # distinct sites
          mutate(across(c(LatitudeMeasure, LongitudeMeasure),
                        ~ as.numeric(.))) %>% 
          distinct() 
        # there are still a few oddballs (~6k) that are duplicated for reasons
        # that I truly can not figure out, so grab duplicated MonitoringLocationIdentifier,
        # remove from distinct, then add back in the singular duplicated MonitoringLocationIdentifier
        duplicated <- distinct[duplicated(distinct$MonitoringLocationIdentifier), ]
        distinct <- distinct %>% 
          filter(!MonitoringLocationIdentifier %in% duplicated$MonitoringLocationIdentifier)
        # now join those back together
        bind_rows(duplicated, distinct) %>% 
          # and add id column
          rowid_to_column("siteSR_id")
      },
    ), 
    
    # Project and transform sites as needed
    tar_target(
      name = p4_harmonized_sites,
      command = {
        harmonized_crs <- harmonize_crs(sites = p4_distinct_sites) 
        write_csv(harmonized_crs, 
                  "4_compile_sites/out/distinct_WQP_sites.csv")
        harmonized_crs
      },
      packages = c("tidyverse", "sf"),
    ),
    
    
    # save this target as an .RDS in Drive
    tar_target(
      name = p4_save_harmonized_sites,
      command = {
        export_single_target(target = p4_harmonized_sites,
                             drive_path = p0_check_targets_drive,
                             stable = FALSE,
                             google_email = p0_siteSR_config$google_email,
                             date_stamp = p0_siteSR_config$collated_site_version)
      },
      packages = c("tidyverse", "googledrive"),
    ), 
    
    tar_target(
      name = p4_hamonized_sites_Drive_id,
      command = {
        get_file_ids(google_email = p0_siteSR_config$google_email,
                     drive_folder = p0_check_targets_drive, 
                     file_path = "4_compile_sites/out/harmonized_sites_drive_id.csv", 
                     depend = p4_save_harmonized_sites, 
                     filter_by = "p4_harmonized_sites")
      },
      packages = c("tidyverse", "googledrive")
    ),
    
    # Associate location with NHD waterbody and flowline ------------------------
    
    # Nearly all sites have a HUC8 reported in the `HUCEightDigitCode` field, but
    # a few need it assigned - with chla and sdd this takes about 40 minutes
    # this step also adds a flag to gap-filled HUC8 fields:
    # 0 = HUC8 reported in WQP site information
    # 1 = HUC8 determined from NHDPlusV2
    # 2 = HUC8 unable to be determined for site location
    tar_target(
      name = p4_add_HUC8,
      command = {
        need_HUC8 <- p4_harmonized_sites %>%
          filter(is.na(HUCEightDigitCode)) %>% 
          # default the flag to 1 and reassign if HUC can not be added
          mutate(flag_HUC8 = 1)
        assigned_HUC8 <- add_HUC8_to_sites(sites_without_HUC = need_HUC8)
        p4_harmonized_sites %>%
          filter(!is.na(HUCEightDigitCode)) %>% 
          mutate(flag_HUC8 = 0) %>% 
          bind_rows(assigned_HUC8) %>% 
          mutate(flag_HUC8 = if_else(is.na(HUCEightDigitCode), 2, flag_HUC8))
      },
      packages = c("tidyverse", "sf", "nhdplusTools"),
    ),
    
    # Create the unique HUCs to map over, but drop those where a HUC4 was not 
    # able to be assigned - processing via HUC4s is twice as fast as HUC8s
    tar_target(
      name = p4_HUC4_list,
      command = unique(str_sub(na.omit(p4_add_HUC8$HUCEightDigitCode), 1, 4)),
    ),
    
    # Get the waterbodies associated with each lake/reservoir site by HUC4
    tar_target(
      name = p4_add_NHD_waterbody_info,
      command = {
        p4_check_dir_structure
        add_NHD_waterbody_to_sites(sites_with_huc = p4_add_HUC8,
                                   huc4 = p4_HUC4_list,
                                   GEE_buffer = as.numeric(p5_yml$site_buffer))
      },
      pattern = map(p4_HUC4_list),
      iteration = "list",
      packages = c("tidyverse", "sf", "nhdplusTools", "rmapshaper")
    ),
    
    # Add flags for proximity to shore 
    
    # Calculate the closest flowline to each river/stream/res/lake/pond site by HUC4
    tar_target(
      name = p4_add_NHD_flowline_info,
      command = {
        p4_check_dir_structure
        add_NHD_flowline_to_sites(sites_with_huc = p4_add_HUC8,
                                  huc4 = p4_HUC4_list,
                                  GEE_buffer = as.numeric(p5_yml$site_buffer))
      }, 
      pattern = map(p4_HUC4_list),
      iteration = "list",
      packages = c("tidyverse", "sf", "nhdplusTools", "rmapshaper")
    ),
    
    # future opportunity: try state download of hucs without processing, currently 
    # in mid folder
    
    # future opportunity: add flowline to waterbody points. For users wishing to 
    # be able to trace using NHD functions, this could be useful. Because the associated
    # waterbody metadata for flowlines seems pretty incomplete, this is hard to do.
    # at this time, nearest flowline will be assigned in p4_add_NHD_flowline info, but
    # flowline metadata are not cross-referenced with the previously-assigned waterbody
    
    # And add that waterbody and flowline info to the unique sites with HUC info
    tar_target(
      name = p4_WQP_site_NHD_info,
      command = {
        p4_check_dir_structure
        # join the waterbody metadata data together
        waterbody_info <- map(p4_add_NHD_waterbody_info,
                              function(l) {
                                # get the first object of the list item (nhd info with waterbody info)
                                l[1]
                              }) %>% 
          bind_rows()
        # and the flowine data
        flowline_info <- map(p4_add_NHD_flowline_info,
                             function(l) {
                               # get the first object of the list item (nhd info with waterbody info)
                               l[1]
                             }) %>% 
          bind_rows
        collated_sites <- full_join(waterbody_info, 
                                    flowline_info) %>% 
          # add in spatial info from above
          full_join(p4_add_HUC8, .) %>% 
          st_drop_geometry()
        # get the intersections data to add to this
        waterbody_intersections <- map(p4_add_NHD_waterbody_info,
                                       function(l) {
                                         # get the second object of the list item (intersection info)
                                         l[2]
                                       }) %>% 
          bind_rows()
        flowline_intersections <- map(p4_add_NHD_flowline_info,
                                      function(l) {
                                        # get the first object of the list item (intersection info)
                                        l[2]
                                      }) %>% 
          bind_rows
        
        # turns out there are a few overlapping NHD waterbody polygons that create 
        # a handful of extra rows here. For the purposes of this workflow, we'll 
        # just grab the larger of the two overlapping polygons. 
        collated_sites <- collated_sites %>% 
          arrange(-wb_areasqkm) %>% 
          slice(1, .by = siteSR_id) %>% 
          left_join(., waterbody_intersections) %>% 
          left_join(., flowline_intersections)
        # fill in flags where HUC8 was not able to be assigned
        collated_sites <- collated_sites %>% 
          mutate(flag_wb = if_else(is.na(flag_wb), 3, flag_wb),
                 flag_wb = if_else(is.na(flag_fl), 4, flag_fl))
        write_csv(collated_sites, 
                  "4_compile_sites/out/collated_WQP_sites_with_metadata.csv")
        collated_sites
      },
    ),
    
    # save this target as an .RDS in Drive
    tar_target(
      name = p4_export_sites,
      command = {
        p0_check_targets_drive
        export_single_target(target = p4_WQP_site_NHD_info,
                             drive_path = p0_check_targets_drive,
                             stable = FALSE,
                             google_email = p0_siteSR_config$google_email,
                             date_stamp = p0_siteSR_config$collated_site_version)
      },
      packages = c("tidyverse", "googledrive"),
    ), 
    
    tar_target(
      name = p4_collated_sites_Drive_id,
      command = {
        get_file_ids(google_email = p0_siteSR_config$google_email,
                     drive_folder = p0_check_targets_drive, 
                     file_path = "4_compile_sites/out/collated_sites_drive_id.csv", 
                     depend = p4_export_sites, 
                     filter_by = "p4_WQP_site_NHD_info")
      },
      packages = c("tidyverse", "googledrive")
    )
    
  )
  
} else {
  
  p4_compile_sites <- list(
    
    # load in distinct sites did file and retrieve target
    tar_file_read(
      name = p4_hamonized_sites_Drive_id,
      command = "4_compile_sites/out/harmonized_sites_drive_id.csv",
      read = read_csv(!!.x),
      cue = tar_cue("always")
    ),
    
    tar_target(
      name = p4_harmonized_sites,
      command = retrieve_target(target = "p4_harmonized_sites",
                                id_df = p4_hamonized_sites_Drive_id, 
                                local_folder = "4_compile_sites/out/", 
                                google_email = p0_siteSR_config$google_email,
                                date_stamp = p0_siteSR_config$collated_site_version,
                                file_type = ".rds"),
      packages = c("tidyverse", "googledrive")
    ),
    
    # load in the collated sites did file and retrieve target
    tar_file_read(
      name = p4_collated_sites_Drive_id,
      command = "4_compile_sites/out/collated_sites_drive_id.csv",
      read = read_csv(!!.x),
      cue = tar_cue("always")
    ),
    
    tar_target(
      name = p4_WQP_site_NHD_info,
      command = retrieve_target(target = "p4_WQP_site_NHD_info",
                                id_df = p4_collated_sites_Drive_id, 
                                local_folder = "4_compile_sites/out/", 
                                google_email = p0_siteSR_config$google_email,
                                file_type = ".rds"),
      packages = c("tidyverse", "googledrive")
    )
    
  )
  
}

