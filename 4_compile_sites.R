# General purpose targets list for the harmonization step

# Source the functions that will be used to build the targets in p3_targets_list
tar_source(files = "4_compile_sites/src/")

p4_targets_list <- list(
  
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
    command = harmonize_crs(sites = p4_distinct_sites)
  )
  
)

