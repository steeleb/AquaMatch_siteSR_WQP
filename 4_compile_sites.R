# General purpose targets list for the harmonization step

# Source the functions that will be used to build the targets in p3_targets_list
tar_source(files = "4_compile_sites/src/")

p4_compile_sites <- list(
  
  # Get unique sites from parameter files -------------------------------------
  
  # Join all and pull distinct rows
  tar_target(
    name = p4_distinct_sites,
    command = {
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
  
  # Associcate location with NHD waterbody or flowline ------------------------

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
  
  # Create the unique HUCs to map over
  tar_target(
    name = p4_HUC8_list,
    command = unique(p4_add_HUC8$HUCEightDigitCode)
  ),

  # Get the waterbodys and flowlines assocated with each site by HUC8
  tar_target(
    name = p4_add_NHD_info,
    command = add_NHD_to_sites(sites_with_huc = p4_add_HUC8,
                               huc8 = p4_HUC8_list),
    pattern = p4_HUC8_list,
    packages = c("tidyverse", "sf", "nhdplusTools")
  )
  
)

