add_NHD_waterbody_to_sites <- function(sites_with_huc, huc8) {
  message(paste0("Assigning NHD waterbodies to sites within ", huc8))
  # make sure that the huc 8 is within CONUS (to use NHDPlusV2)
  if (as.numeric(str_sub(huc8, 1, 2) <= 18)) {
    # filter sites for those in a single huc
    sf <- sites_with_huc %>%
      filter(HUCEightDigitCode == huc8) %>% 
      rowid_to_column()
    # and get the huc sf object using nhdplusTools
    one_huc <- get_huc(id = huc8, type = "huc08")
    # make sure the huc exists in NHDPlusV2
    if (!is.null(one_huc)) {
      # and get the waterbodies within the huc
      huc_wbd <- get_waterbodies(one_huc) 
      # now, if there are waterbodies in NHDPlusV2, add the information from the 
      # waterbody features using the NHDPlusV2
      if (!is.null(huc_wbd)) {
        # make the waterbodies valid
        # first try the simplistic st_make_valid
        huc_wbd <- huc_wbd %>% 
          st_make_valid()
        # if that didn't work, use brute force and rmapshaper to simplify
        if (FALSE %in% st_is_valid(huc_wbd)) {
          # pull out geometries that are still invalid, if any
          invalid <- huc_wbd[!st_is_valid(huc_wbd),]
          # simplify (st_simplify usually fails here, so using 
          # rmapshaper::ms_simplify())
          sf_use_s2(TRUE) # use more conservative setting to avoid errors
          wbd_less <- huc_wbd[!huc_wbd$comid %in% invalid$comid,]
          fixed <- invalid %>% 
            ms_simplify(keep = 0.75)
          huc_wbd <- bind_rows(wbd_less, fixed)
          sf_use_s2(FALSE) # but turn it back off
        }
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
          mutate(n_wbd_100m = if_else(is.na(n_wbd_100m), 0, n_wbd_100m)) %>% 
          select(-rowid)
        
        # return the sf with NHD info
        return(sf_with_wbd)
      } else {
        # if no waterbodies, note the huc8 in a text file
        message(paste0("HUC8 ", huc8, " contains no waterbodies, noting in '4_compile_sites/mid/no_wbd_huc8.txt'"))
        if (!file.exists("4_compile_sites/mid/no_wbd_huc8.txt")) {
          write_lines(huc8, file = "4_compile_sites/mid/no_wbd_huc8.txt")
          return(NULL)
        } else {
          text <- read_lines("4_compile_sites/mid/no_wbd_huc8.txt")
          new_text <- c(text, huc8)
          write_lines(new_text, "4_compile_sites/mid/no_wbd_huc8.txt")
          return(NULL)
        }
      } 
    } else {
      # if no huc, note the huc8 in a text file
      message(paste0("HUC8 ", huc8, " was not associated with a HUC in the NHD, noting in '4_compile_sites/mid/no_huc_huc8.txt'"))
      if (!file.exists("4_compile_sites/mid/no_huc_huc8.txt")) {
        write_lines(huc8, file = "4_compile_sites/mid/no_huc_huc8.txt")
        return(NULL)
      } else {
        text <- read_lines("4_compile_sites/mid/no_huc_huc8.txt")
        new_text <- c(text, huc8)
        write_lines(new_text, "4_compile_sites/mid/no_huc_huc8.txt")
        return(NULL)
      }
    }
  } else {
    # if huc is outside of CONUS add to text file
    message(paste0("HUC8 ", huc8, " is outside of the CONUS, noting in '4_compile_sites/mid/outside_CONUS_huc8.txt'"))
    if (!file.exists("4_compile_sites/mid/outside_CONUS_huc8.txt")) {
      write_lines(huc8, file = "4_compile_sites/mid/outside_CONUS_huc8.txt")
      return(NULL)
    } else {
      text <- read_lines("4_compile_sites/mid/outside_CONUS_huc8.txt")
      new_text <- c(text, huc8)
      write_lines(new_text, "4_compile_sites/mid/outside_CONUS_huc8.txt")
      return(NULL)
    }
  }
}
