add_NHD_to_sites <- function(sites_with_huc, huc8) {
  message(paste0("Assigning NHD waterbodies to sites within ", huc8))
  # filter sites for those in a single huc
  sf <- sites_with_huc %>%
    filter(HUCEightDigitCode == huc8) %>% 
    rowid_to_column()
  # and get the huc sf object using nhdplusTools
  one_huc <- get_huc(id = huc8, type = "huc08")
  # and get the waterbodies within the huc
  huc_wbd <- get_waterbodies(one_huc) 
  # now, if there are waterbodies in NHDPlusV2, add the information from the 
  # waterbody features, otherwise, save HUC8 in text file
  if (!is.null(huc_wbd)) {
    sf_with_wbd <- sf %>% 
      st_transform(., st_crs(one_huc)) %>% 
      st_join(., huc_wbd) %>% 
      select(all_of(names(sf)), 
             wbd_comid = comid,
             wbd_gnis_id = gnis_id,
             wbd_gnis_name = gnis_name,
             wbd_area_sq_km = areasqkm,
             wbd_reach_code = reachcode,
             wbd_ftype = ftype)
    # add a 100m buffer and see how many points intersect multiple waterbodies
    # this is a stand in for how 'confident' we are in assigning a given point to a
    # waterbody
    sf_buffer_wbd <- sf %>% 
      st_buffer(dist = 100) %>% 
      st_join(., huc_wbd) %>% 
      st_drop_geometry() %>% 
      filter(!is.na(comid)) %>% 
      group_by(rowid) %>% 
      summarize(n_wbd_100m = n()) 
    
    # add that info to the sf object
    sf_with_wbd <- left_join(sf_with_wbd, sf_buffer_wbd) %>% 
      mutate(n_wbd_100m = if_else(is.na(n_wbd_100m), 0, n_wbd_100m))
    
    # # initialize flowline info columns
    # sf_with_wbd$closest_flowline_comid = NA_character_
    # sf_with_wbd$distance_to_flowline = NA_real_
    # 
    # # this loop creates a ton of messages, silencing to make the targets output
    # # cleaner
    # suppressMessages(
    #   # do this in UTM for distance in meters, for now, this is sufficient
    #   for (r in 1:nrow(sf_with_wbd)) {
    #     point <- sf_with_wbd[r, ]
    #     try({
    #       huc_flow <- get_flowline_index("download_nhdplusv2", point)
    #       if (!is.null(huc_flow)) {
    #         sf_with_wbd$closest_flowline_comid[r] <- huc_flow$COMID
    #         sf_with_wbd$distance_to_flowline[r] <- huc_flow$offset
    #       } 
    #     })
    #   }
    # )
    
    # return the sf with NHD info
    return(sf_with_wbd)
  } else {
    # get workflow from lakeSR center calc
  }
}
