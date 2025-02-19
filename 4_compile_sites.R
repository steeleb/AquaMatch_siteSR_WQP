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
      bind_rows(duplicated, distinct)
    },
  ), 
  
  # Project and transform sites as needed
  tar_target(
    name = p4_harmonized_sites,
    command = harmonize_crs(sites = p4_distinct_sites),
    packages = c("tidyverse", "sf"),
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
                                         huc4 = p4_HUC4_list)
      },
    pattern = map(p4_HUC4_list),
    packages = c("tidyverse", "sf", "nhdplusTools", "rmapshaper")
  ),
  
  # Calculate the closest flowline to each river/stream/res/lake/pond site by HUC4
  tar_target(
    name = p4_add_NHD_flowline_info,
    command = {
      p4_check_dir_structure
      add_NHD_flowline_to_sites(sites_with_huc = p4_add_HUC8,
                                        huc4 = p4_HUC4_list)
      }, 
    pattern = map(p4_HUC4_list),
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
      # join the data together
      collated_sites <- full_join(p4_add_NHD_waterbody_info, 
                                  p4_add_NHD_flowline_info) %>% 
        # add in spatial info from above
        full_join(p4_add_HUC8, .) %>% 
        st_drop_geometry() %>% 
        rowid_to_column("siteSR_id")
      # turns out there are a few overlapping NHD waterbody polygons that create 
      # a handful of extra rows here. For the purposes of this workflow, we'll 
      # just grab the larger of the two overlapping polygons. 
      collated_sites <- collated_sites %>% 
        arrange(-wb_areasqkm) %>% 
        slice(1, .by = MonitoringLocationIdentifier)
      # fill in flags where HUC8 was not able to be assigned
      collated_sites <- collated_sites %>% 
        mutate(flag_wb = if_else(is.na(flag_wb), 3, flag_wb),
               flag_wb = if_else(is.na(flag_fl), 4, flag_fl))
      write_csv(collated_sites, 
                "4_compile_sites/out/collated_WQP_sites.csv")
      collated_sites
    },
  ),
  
  # save this target as an .RDS in Drive, no need for this to be versioned at this time
  tar_target(
    name = p4_export_sites,
    command = {
      p0_check_targets_drive
      export_single_target(target = p4_WQP_site_NHD_info,
                           drive_path = "~/aquamatch_siteSR_wqp/targets/",
                           stable = FALSE,
                           google_email = p0_siteSR_config$google_email,
                           date_stamp = p0_siteSR_config$run_date)
    },
    packages = c("tidyverse", "googledrive"),
  )
  
)

