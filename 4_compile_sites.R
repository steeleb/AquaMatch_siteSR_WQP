# Targets list to compile sites and attribute each feature to a waterbody or
# flowline

# Define p4 group --------------------------------------------------------

# Source the functions that will be used to build the targets in p3_targets_list
tar_source(files = "4_compile_sites/src/")

p4_compile_sites <- list(
  
  # make directories if needed
  tar_target(
    name = p4_check_dir_structure,
    command = {
      directories = c("4_compile_sites/in/",
                      "4_compile_sites/mid/",
                      "4_compile_sites/out/")
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
  
  # Get unique sites from parameter files -------------------------------------
  
  # Join all and pull distinct rows
  tar_target(
    name = p4_distinct_sites,
    command = {
      # combine across all site infos, but only retain distinct rows. 
      bind_rows(list(p3_chla_harmonized_site_info, 
                     p3_sdd_harmonized_site_info,
                     p3_doc_harmonized_site_info)) %>% 
        distinct() 
    },
    deployment = "main"
  ), 
  
  # Project and transform sites as needed
  tar_target(
    name = p4_harmonized_sites,
    command = harmonize_crs(sites = p4_distinct_sites),
    packages = c("tidyverse", "sf"),
    deployment = "main"
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
    deployment = "main"
  ),
  
  # Create the unique HUCs to map over, but drop those where a HUC4 was not 
  # able to be assigned, indicating that the point is not within the boundaries
  # of the NHDPlusV2 - processing via HUC4s is twice as fast as HUC8s
  tar_target(
    name = p4_HUC4_list,
    command = unique(str_sub(na.omit(p4_add_HUC8$HUCEightDigitCode), 1, 4)),
    deployment = "main"
  ),
  
  # Get the waterbodies associated with each site by HUC4
  tar_target(
    name = p4_add_NHD_waterbody_info,
    command = add_NHD_waterbody_to_sites(sites_with_huc = p4_add_HUC8,
                                         huc4 = p4_HUC4_list,
                                         buffer = 200) %>% 
      bind_rows(),
    pattern = map(p4_HUC4_list),
    packages = c("tidyverse", "sf", "arcgis", "rmapshaper")
  ),
  
  # Calculate the closest flowline to each site by HUC4
  tar_target(
    name = p4_add_NHD_flowline_info,
    command = add_NHD_flowline_to_sites(sites_with_huc = p4_add_HUC8,
                                        huc4 = p4_HUC4_list,
                                        buffer = 200) %>% 
      bind_rows(), 
    pattern = map(p4_HUC4_list),
    packages = c("tidyverse", "sf", "arcgis")
  ),
  
  # And add that waterbody and flowline info to the unique sites with HUC info
  tar_target(
    name = p4_sites_with_NHD_attribution,
    command = {
      collated_sites <- reduce(list(p4_add_HUC8, p4_add_NHD_waterbody_info, p4_add_NHD_flowline_info),
                               full_join) %>% 
        st_drop_geometry() %>% 
        rowid_to_column()
      # write this file for use in yml/ee workflow
      write_csv(collated_sites, "4_compile_sites/out/collated_sites.csv")
      collated_sites
    },
    deployment = "main"
    )
  
  # todo: Will need to address HUCs that are not in NHDPlusHR here ...
  # thoughts: grab huc8s and asses via that route? Make sure these aren't actually 
  # out of the AOI? I think this is because it's maxing out the request at this 
  # extent (I think the max number of objects to return using the MapServer is 2k?)
  
  
)

