# Targets list to compile sites and attribute each feature to a waterbody or
# flowline

# Define `a` group --------------------------------------------------------

# Source the functions that will be used to build the targets in `a_compile_sites`
tar_source(files = "a_compile_sites/src/")

if (general_config != "default") {
  
  a_compile_sites <- list(
    
    # make directories if needed
    tar_target(
      name = a_check_dir_structure,
      command = {
        directories <- c("a_compile_sites/in/",
                         "a_compile_sites/mid/",
                         "a_compile_sites/out/",
                         "a_compile_sites/nhd/")
        walk(directories, function(dir) {
          if(!dir.exists(dir)){
            dir.create(dir)
          }
        })
      },
      cue = tar_cue("always"),
    ),
    
    # Get unique sites from WQP and NWIS -------------------------------------
    
    # Make list of FIPS state descriptions
    tar_target(
      name = a_fips_descriptions,
      command = {
        # grab the xml from the National Water Quality Monitoring Council
        read_xml("https://www.waterqualitydata.us/Codes/statecode?countrycode=US") %>% 
          xml_find_all(., ".//Code") %>% 
          xml_attr(., "desc")
      },
      packages = c("tidyverse", "xml2")
    ),
    
    # map the descriptions to get all filtered site metadata for WQP
    tar_target(
      name = a_WQP_site_metadata,
      command = {
        # get site info
        site_info <- get_site_info(fips_state_code_desc = a_fips_descriptions,
                                   site_source = "WQP")
        # check for dupes
        site_info
      },
      pattern = map(a_fips_descriptions),
      packages = c("tidyverse", "dataRetrieval")
    ),
    
    # map the descriptions to get all filtered site metadata for WQP
    tar_target(
      name = a_NWIS_site_metadata,
      command = get_site_info(fips_state_code_desc = a_fips_descriptions,
                              site_source = "NWIS"),
      pattern = map(a_fips_descriptions),
      packages = c("tidyverse", "dataRetrieval")
    ),
    
    # Project and transform sites as needed - this is done separately since the
    # metadata is not the same across the two data sources (WQP/NWIS)
    tar_target(
      name = a_harmonized_WQP_sites,
      command = {
        # use function to harmonize across all CRS
        harmonized_crs <- harmonize_crs(sites = a_WQP_site_metadata)
        # return sf
        harmonized_crs
      },
      packages = c("tidyverse", "sf"),
    ),
    
    # NWIS data lat/lon that start with `dec_` are all stored in NAD83
    tar_target(
      name = a_harmonized_NWIS_sites,
      command = {
        # create sf and transform to WGS84
        to_wgs84 <- a_NWIS_site_metadata %>% 
          st_as_sf(coords = c("dec_long_va", "dec_lat_va"),
                   crs = "EPSG:4269",
                   remove = FALSE) %>%
          st_transform(crs = "EPSG:4326")
        
        # store harmonized Latitude and Longitude in site list
        new_coords <- to_wgs84 %>% st_coordinates()
        
        # add WGS84 lat/long
        to_wgs84$WGS84_Longitude = new_coords[,1]
        to_wgs84$WGS84_Latitude = new_coords[,2]
        
        # return sf
        to_wgs84
      },
      packages = c("tidyverse", "sf"),
    ),
    
    # save these two targets as .RDS in Drive
    tar_target(
      name = a_save_WQP_harmonized_sites,
      command = {
        export_single_target(target = a_harmonized_WQP_sites,
                             drive_path = check_targets_drive,
                             stable = FALSE,
                             google_email = siteSR_config$google_email,
                             date_stamp = siteSR_config$collated_site_version,
                             file_type = "rds")
      },
      packages = c("tidyverse", "googledrive"),
    ), 
    
    tar_target(
      name = a_save_NWIS_harmonized_sites,
      command = {
        export_single_target(target = a_harmonized_NWIS_sites,
                             drive_path = check_targets_drive,
                             stable = FALSE,
                             google_email = siteSR_config$google_email,
                             date_stamp = siteSR_config$collated_site_version,
                             file_type = "rds")
      },
      packages = c("tidyverse", "googledrive"),
    ), 
    
    tar_target(
      name = a_hamonized_WQP_sites_Drive_id,
      command = {
        get_file_ids(google_email = siteSR_config$google_email,
                     drive_folder = check_targets_drive, 
                     file_path = "a_compile_sites/out/harmonized_WQP_sites_drive_id.csv", 
                     depend = a_save_WQP_harmonized_sites, 
                     filter_by = "a_WQP_harmonized_sites")
      },
      packages = c("tidyverse", "googledrive")
    ),
    
    tar_target(
      name = a_hamonized_NWIS_sites_Drive_id,
      command = {
        get_file_ids(google_email = siteSR_config$google_email,
                     drive_folder = check_targets_drive, 
                     file_path = "a_compile_sites/out/harmonized_NWIS_sites_drive_id.csv", 
                     depend = a_save_NWIS_harmonized_sites, 
                     filter_by = "a_NWIS_harmonized_sites")
      },
      packages = c("tidyverse", "googledrive")
    ),
    
    # collate the two sf files retaining just the uniqe id and wgs lat/lon
    tar_target(
      name = a_all_site_locations,
      command = {
        NWIS <- a_harmonized_NWIS_sites %>% 
          select(org_id = agency_cd, loc_id = site_no, 
                 WGS84_Latitude, WGS84_Longitude, source) %>% 
          st_drop_geometry()
        WQP <- a_harmonized_WQP_sites %>% 
          select(org_id = OrganizationIdentifier, 
                 loc_id = MonitoringLocationIdentifier, 
                 HUCEightDigitCode,
                 WGS84_Latitude, WGS84_Longitude, source) %>% 
          st_drop_geometry()
        # join together and provide a siteSR id for use
        full_join(NWIS, WQP) %>% 
          rowid_to_column("siteSR_id") %>% 
          relocate(siteSR_id) %>% 
          st_as_sf(coords = c("WGS84_Longitude", "WGS84_Latitude"),
                   crs = "EPSG:4326")
      },
    ), 
    
    # save this as a .rds file in drive
    tar_target(
      name = a_save_all_site_locs,
      command = {
        export_single_target(target = a_all_site_locations,
                             drive_path = check_targets_drive,
                             stable = FALSE,
                             google_email = siteSR_config$google_email,
                             date_stamp = siteSR_config$collated_site_version,
                             file_type = "rds")
      },
      packages = c("tidyverse", "googledrive"),
    ),
    
    # get the drive id info
    tar_target(
      name = a_all_site_locs_Drive_id,
      command = {
        get_file_ids(google_email = siteSR_config$google_email,
                     drive_folder = check_targets_drive, 
                     file_path = "a_compile_sites/out/all_site_locations_drive_id.csv", 
                     depend = a_save_all_site_locs, 
                     filter_by = "a_all_site_locations")
      },
      packages = c("tidyverse", "googledrive")
    ),

    # Associate location with NHD waterbody and flowline ------------------------

    # Nearly all WQP sites have a HUC8 reported in the `HUCEightDigitCode` field, 
    # but a few need it assigned, as do all of the NWIS sites
    # this step also adds a flag to gap-filled HUC8 fields:
    # 0 = HUC8 reported in WQP site information
    # 1 = HUC8 determined from NHDPlusV2
    # 2 = HUC8 unable to be determined for site location
    tar_target(
      name = a_sites_add_HUC8,
      command = {
        need_HUC8 <- a_all_site_locations %>%
          filter(is.na(HUCEightDigitCode)) %>%
          # default the flag to 1 and reassign if HUC can not be added
          mutate(flag_HUC8 = 1)
        assigned_HUC8 <- add_HUC8_to_sites(sites_without_HUC = need_HUC8)
        a_all_site_locations %>%
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
      name = a_HUC4_list,
      command = unique(str_sub(na.omit(a_sites_add_HUC8$HUCEightDigitCode), 1, 4)),
    ),
    
    # Get the waterbodies associated with each lake/reservoir site by HUC4, 
    # leave these in a list for other branching funcitons
    tar_target(
      name = a_add_NHD_waterbody_info,
      command = {
        a_check_dir_structure
        add_NHD_waterbody_to_sites(sites_with_huc = a_sites_add_HUC8,
                                   huc4 = a_HUC4_list,
                                   GEE_buffer = as.numeric(b_yml$site_buffer))
      },
      pattern = map(a_HUC4_list),
      iteration = "list",
      packages = c("tidyverse", "sf", "nhdplusTools", "rmapshaper")
    ),

    # Calculate the closest flowline to each river/stream/res/lake/pond site by HUC4
    tar_target(
      name = a_add_NHD_flowline_info,
      command = {
        a_check_dir_structure
        add_NHD_flowline_to_sites(sites_with_huc = a_sites_add_HUC8,
                                  huc4 = a_HUC4_list,
                                  GEE_buffer = as.numeric(b_yml$site_buffer))
      },
      pattern = map(a_HUC4_list),
      iteration = "list",
      packages = c("tidyverse", "sf", "nhdplusTools", "rmapshaper")
    ),

    # And add that waterbody and flowline info to the unique sites with HUC info
    tar_target(
      name = a_sites_with_NHD_info,
      command = {
        a_check_dir_structure
        # join the waterbody metadata data together
        waterbody_info <- map(a_add_NHD_waterbody_info,
                              function(l) {
                                # get the first object of the list item (nhd info with waterbody info)
                                l[1]
                              }) %>%
          bind_rows() 
        # and the flowine data
        flowline_info <- map(a_add_NHD_flowline_info,
                             function(l) {
                               # get the first object of the list item (nhd info with waterbody info)
                               l[1]
                             }) %>%
          bind_rows()
        collated_sites <- full_join(waterbody_info,
                                    flowline_info) %>%
          # add in spatial info from above
          full_join(a_sites_add_HUC8, .) %>%
          st_drop_geometry()
        # get the intersections data to add to this
        waterbody_intersections <- map(a_add_NHD_waterbody_info,
                                       function(l) {
                                         # get the second object of the list item (intersection info)
                                         l[2]
                                       }) %>%
          bind_rows()
        flowline_intersections <- map(a_add_NHD_flowline_info,
                                      function(l) {
                                        # get the first object of the list item (intersection info)
                                        l[2]
                                      }) %>%
          bind_rows()

        # turns out there are a few overlapping NHD waterbody polygons that create
        # a handful of extra rows here. For the purposes of this workflow, we'll
        # just grab the larger of the two overlapping polygons.
        collated_sites <- collated_sites %>%
          left_join(., waterbody_intersections) %>%
          left_join(., flowline_intersections) %>%
          arrange(-wb_areasqkm) %>%
          slice(1, .by = siteSR_id)
        # fill in flags where HUC8 was not able to be assigned
        collated_sites <- collated_sites %>%
          mutate(flag_wb = if_else(is.na(flag_wb), 3, flag_wb),
                 flag_wb = if_else(is.na(flag_fl), 4, flag_fl),
                 # flag 0 = unlikely shoreline contamination
                 # flag 1 = possible shoreline contamination
                 flag_optical_shoreline =  case_when(flag_wb != 0 ~ NA,
                                                     dist_to_shore <= (as.numeric(b_yml$site_buffer) + 30) &
                                                       flag_wb == 0 ~ 1,
                                                     dist_to_shore > (as.numeric(b_yml$site_buffer) + 30) &
                                                       flag_wb == 0 ~ 0),
                 flag_thermal_TM_shoreline =  case_when(flag_wb != 0 ~ NA,
                                                        dist_to_shore <= (as.numeric(b_yml$site_buffer) + 120) &
                                                          flag_wb == 0 ~ 1,
                                                        dist_to_shore > (as.numeric(b_yml$site_buffer) + 120) &
                                                          flag_wb == 0 ~ 0),
                 flag_thermal_ETM_shoreline = case_when(flag_wb != 0 ~ NA,
                                                        dist_to_shore <= (as.numeric(b_yml$site_buffer) + 60) &
                                                          flag_wb == 0 ~ 1,
                                                        dist_to_shore > (as.numeric(b_yml$site_buffer) + 60) &
                                                          flag_wb == 0 ~ 0),
                 flag_thermal_TIRS_shoreline = case_when(flag_wb != 0 ~ NA,
                                                         dist_to_shore <= (as.numeric(b_yml$site_buffer) + 100) &
                                                           flag_wb == 0 ~ 1,
                                                         dist_to_shore > (as.numeric(b_yml$site_buffer) + 100) &
                                                           flag_wb == 0 ~ 0))
        write_csv(collated_sites,
                  "a_compile_sites/out/collated_WQP_sites_with_metadata.csv")
        collated_sites
      },
    ),

    # save this target as an .RDS in Drive
    tar_target(
      name = a_export_sites_with_NHD,
      command = {
        check_targets_drive
        export_single_target(target = a_sites_with_NHD_info,
                             drive_path = check_targets_drive,
                             stable = FALSE,
                             google_email = siteSR_config$google_email,
                             date_stamp = siteSR_config$collated_site_version,
                             file_type = "rds")
      },
      packages = c("tidyverse", "googledrive"),
    ),

    tar_target(
      name = a_sites_with_NHD_Drive_id,
      command = {
        get_file_ids(google_email = siteSR_config$google_email,
                     drive_folder = check_targets_drive,
                     file_path = "a_compile_sites/out/sites_with_NHD_drive_id.csv",
                     depend = a_export_sites,
                     filter_by = "a_sites_with_NHD_info")
      },
      packages = c("tidyverse", "googledrive")
    )
    
  )
  
} else {
  
  a_compile_sites <- list(
    
    # load in distinct sites did file and retrieve target
    tar_file_read(
      name = a_all_site_locs_Drive_id,
      command = "a_compile_sites/out/all_site_locations_drive_id.csv",
      read = read_csv(!!.x),
      cue = tar_cue("always")
    ),
    
    tar_target(
      name = a_all_site_locations,
      command = retrieve_target(target = "a_all_site_locations",
                                id_df = a_hamonized_sites_Drive_id, 
                                local_folder = "a_compile_sites/out/", 
                                google_email = siteSR_config$google_email,
                                date_stamp = siteSR_config$collated_site_version,
                                file_type = "rds"),
      packages = c("tidyverse", "googledrive")
    ),
    
    # load in the collated sites did file and retrieve target
    tar_file_read(
      name = a_sites_with_NHD_Drive_id,
      command = "a_compile_sites/out/sites_with_NHD_drive_id.csv",
      read = read_csv(!!.x),
      cue = tar_cue("always")
    ),
    
    tar_target(
      name = a_sites_with_NHD_info,
      command = retrieve_target(target = "a_sites_with_NHD_info",
                                id_df = a_sites_with_NHD_Drive_id, 
                                local_folder = "a_compile_sites/out/", 
                                google_email = siteSR_config$google_email,
                                date_stamp = siteSR_config$collated_site_version,
                                file_type = ".rds"),
      packages = c("tidyverse", "googledrive")
    )
    
  )
  
}

