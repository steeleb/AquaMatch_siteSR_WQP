# General purpose targets list for the harmonization step

# Source the functions that will be used to build the targets in p3_targets_list
tar_source(files = "5_site_visibility/src/")

p5_site_visibility <- list(
  # Create the unique HUCs to map over
  tar_target(
    name = p5_wbd_HUC8_list,
    command = p4_add_NHD_waterbody_info %>% 
      # if there isn't a nhd waterbody to relate to, drop it from this summary
      filter(!is.na(nhd_permanent_identifier)) %>% 
      unique(na.omit(.$HUCEightDigitCode))
  ),

  # initial assessment of satellite visibility is completed by measuring distance
  # to shore. We know that this can be an overestimate in waterbodies with varying
  # surface level, but it is a good starting point to limit the queries sent to
  # GEE
  tar_target(
    name = sites_with_distance_to_shore,
    command = calculate_distance_to_shore(sites_with_waterbodies = p4_add_NHD_waterbody_info, 
                                          huc8 = p5_wbd_HUC8_list),
    pattern = p5_wbd_HUC8_list,
    packages = c("tidyverse", "sf", "nhdplusTools")
  ),
  
  # to mimic decisions in riverSR, we'll use a cutoff of 30m here
  tar_target(
    name = visible_sites,
    command = sites_with_distance_to_shore %>% filter(dist_to_shore >= 30)
  )
  
)