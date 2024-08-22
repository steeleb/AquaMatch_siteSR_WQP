# General purpose targets list for the harmonization step

# Source the functions that will be used to build the targets in p3_targets_list
tar_source(files = "4_compile_sites/src/")

p4_compile_sites <- list(
  
  # make directories if needed
  tar_target(
    name = p4_check_dir_structure,
    command = {
      directories = c("4_compile_sites/in/",
                      "4_compile_sites/mid/")
      
      walk(directories, function(dir) {
        if(!dir.exists(dir)){
          dir.create(dir)
        }
      })
    },
    cue = tar_cue("always"),
    priority = 1
  ),
  
  # Get unique sites from parameter files -------------------------------------
  
  # Join all and pull distinct rows
  tar_target(
    name = p4_distinct_sites,
    command = {
      # combine across all site infos, but only retain distinct rows. 
      reduce(.x = list(p3_chla_harmonized_site_info, 
                            p3_sdd_harmonized_site_info),
                     .f = bind_rows) %>% 
      distinct()
      }
  ), 
  
  # Project and transform sites as needed
  tar_target(
    name = p4_harmonized_sites,
    command = harmonize_crs(sites = p4_distinct_sites),
    packages = c("tidyverse", "sf")
  ),
  
  # Associate location with NHD waterbody and flowline ------------------------

  # Nearly all sites have a HUC8 reported in the `HUCEightDigitCode` field, but
  # a few need it assigned
  tar_target(
    name = p4_add_HUC8,
    command = {
      need_HUC8 <- p4_harmonized_sites %>%
        filter(is.na(HUCEightDigitCode))
      assigned_HUC8 <- add_HUC8_to_sites(sites_without_HUC = need_HUC8)
      p4_harmonized_sites %>%
        filter(!is.na(HUCEightDigitCode)) %>%
        bind_rows(assigned_HUC8)
    },
    packages = c("tidyverse", "sf", "nhdplusTools")
  ),
  
  # todo: might consider whether or not it's faster to do this by HUC4 instead
  # of HUC8
  
  # Create the unique HUCs to map over
  tar_target(
    name = p4_HUC8_list,
    command = unique(na.omit(p4_add_HUC8$HUCEightDigitCode))
  ),

  # Get the waterbodies associated with each site by HUC8
  tar_target(
    name = p4_add_NHD_waterbody_info,
    command = add_NHD_waterbody_to_sites(sites_with_huc = p4_add_HUC8,
                                         huc8 = p4_HUC8_list),
    pattern = p4_HUC8_list,
    packages = c("tidyverse", "sf", "nhdplusTools", "rmapshaper")
  )#,

  # # Calculate the closest flowline to each site by HUC8
  # tar_target(
  #   name = p4_add_NHD_flowline_info,
  #   command = add_NHD_flowline_to_sites(sites_with_huc = p4_add_HUC8,
  #                                       huc8 = p4_HUC8_list),
  #   pattern = p4_HUC8_list,
  #   packages = c("tidyverse", "sf", "nhdplusTools")
  # )
  
  # Will need to address HUCs that are not in NHDPlusV2 here ...
  
  # And also join the waterbody and flowline info ...
  
)

