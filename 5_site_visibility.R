# Targets list to assess site remote sensing visibility

# Source the functions that will be used to build the targets in p3_targets_list
tar_source(files = "5_site_visibility/src/")

p5_site_visibility <- list(
  # Create the unique HUCs to map over
  tar_target(
    name = p5_wbd_HUC4_list,
    command ={ 
      filtered_sites <- p4_add_NHD_waterbody_info %>% 
        # if there isn't a nhd waterbody to relate to, drop it from this summary
        filter(!is.na(nhd_permanent_identifier)) 
      HUC8s <- unique(na.omit(filtered_sites$HUCEightDigitCode))
      HUC8s %>% 
        str_sub(., 1, 4) %>% 
        unique(.)
    }
  ),
  
  # initial assessment of satellite visibility is completed by measuring distance
  # to shore. We know that this can be an overestimate in waterbodies with varying
  # surface level, but it is a good starting point to limit the queries sent to
  # GEE
  tar_target(
    name = sites_with_distance_to_shore,
    command = calculate_distance_to_shore(sites_with_waterbodies = p4_add_NHD_waterbody_info, 
                                          huc4 = p5_wbd_HUC4_list),
    pattern = p5_wbd_HUC4_list,
    packages = c("tidyverse", "sf", "arcgis")
  ),
  
  # to mimic decisions in riverSR, we'll use a cutoff of 30m here
  tar_target(
    name = visible_sites,
    command = {
      visible_sites <- sites_with_distance_to_shore %>% 
        filter(dist_to_shore >= 30) %>% 
        st_drop_geometry()
      write_csv(visible_sites, "5_site_visibility/out/visible_sites.csv")
      visible_sites
    },
    packages = c("sf", "tidyverse")
  )
  
)