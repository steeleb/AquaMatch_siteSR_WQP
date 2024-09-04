# Targets list to assess site remote sensing visibility

# Source the functions that will be used to build the targets in p3_targets_list
tar_source(files = "5_site_visibility/src/")

p5_site_visibility <- list(
  # make directories if needed
  tar_target(
    name = p5_check_dir_structure,
    command = {
      directories = c("5_site_visibility/out/")
      
      walk(directories, function(dir) {
        if(!dir.exists(dir)){
          dir.create(dir)
        }
      })
    },
    cue = tar_cue("always"),
    priority = 1
  ),
  
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
    name = p5_sites_with_distance_to_shore,
    command = calculate_distance_to_shore(sites_with_waterbodies = p4_add_NHD_waterbody_info, 
                                          huc4 = p5_wbd_HUC4_list),
    pattern = p5_wbd_HUC4_list,
    packages = c("tidyverse", "sf", "arcgis")
  ),
  
  # to mimic decisions in riverSR, we'll use a cutoff of 30m from a waterbody edge.
  tar_target(
    name = p5_visible_sites,
    command = {
      visible_sites <- p5_sites_with_distance_to_shore %>% 
        # coerce unit object to numeric for filtering and writing the csv
        mutate(dist_to_shore = as.numeric(dist_to_shore)) %>% 
        filter(dist_to_shore >= 30) %>% 
        st_drop_geometry() %>% 
        rowid_to_column()
      # save the file and return the dataframe
      write_csv(visible_sites, "5_site_visibility/out/visible_sites.csv")
      visible_sites
    },
    packages = c("sf", "grid", "tidyverse")
  )
  
  # deal with rivers! filter by distance to flowline (30m too)
)