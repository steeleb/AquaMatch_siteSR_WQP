#' @title Add NHD waterbody identifier to sites
#' 
#' @description
#' Using the USGS MapServer, assign a permanent identifier to each site to associate them with 
#' a specific waterbody
#' 
#' @param sites_with_huc simple feature object of sites to pair with waterbodies
#' @param huc4 4-digit character string to filter sites by
#' 
#' @returns a dataframe of the simple feature object of sites with additional 
#' fields from the NHDPlusHR. Silently returns text files with huc4s that failed 
#' this function
#' 
#' 
add_NHD_waterbody_to_sites <- function(sites_with_huc, huc4) {
  message(paste0("Assigning NHD waterbodies to sites within ", huc4))
  
  # filter sites for those in a single huc
  sf_subset <- sites_with_huc %>%
    filter(str_sub(HUCEightDigitCode, 1, 4) == huc4) %>% 
    rowid_to_column()
  
  # point to the nhdplushr MapServer url
  nhd_plus_hr_url <- "https://hydro.nationalmap.gov/arcgis/rest/services/NHDPlus_HR/MapServer"
  # open that connection
  nhd_hr <- arc_open(nhd_plus_hr_url)
  # grab the NHD waterbodies layer using the mapserver
  waterbodies <- get_layer(nhd_hr, 9)
  
  # use the bounding box of the sites to query the waterbodies within the AOI
  bbox = st_bbox(sf_subset) %>% 
    st_as_sfc()
  
  tryCatch(
    { # wrap this in a try catch to address AOIs outside of extent of NHD HR
      waterbodies_subset <- arc_select(waterbodies,
                                       filter_geom = bbox) 
      
      # make sure that the huc 8 contains waterbodies
      if (nrow(waterbodies_subset) > 0) {
        # make the waterbodies valid
        # first try the simplistic st_make_valid
        huc_wbd <- waterbodies_subset %>% 
          st_make_valid()
        # if that didn't work, use brute force and rmapshaper to simplify
        if (FALSE %in% st_is_valid(huc_wbd)) {
          # pull out geometries that are still invalid, if any
          invalid <- huc_wbd[!st_is_valid(huc_wbd),]
          # simplify (st_simplify usually fails here, so using 
          # rmapshaper::ms_simplify())
          sf_use_s2(TRUE) # use more conservative setting to avoid errors
          wbd_less <- huc_wbd[!huc_wbd$permanent_identifier %in% invalid$permanent_identifier,]
          fixed <- invalid %>% 
            ms_simplify(keep = 0.75)
          huc_wbd <- bind_rows(wbd_less, fixed)
          sf_use_s2(FALSE) # but turn it back off
        }
        sf_with_wbd <- sf_subset %>% 
          # reproject in crs of huc
          st_transform(., st_crs(huc_wbd)) %>% 
          # add all the info from the huc to the sf object
          st_join(., huc_wbd) %>% 
          select(all_of(names(sf_subset)), 
                 nhd_permanent_identifier = permanent_identifier,
                 nhd_gnis_id = gnis_id,
                 nhd_gnis_name = gnis_name,
                 nhd_area_sq_km = areasqkm,
                 nhd_reach_code = reachcode,
                 nhd_ftype = ftype) %>% 
          st_drop_geometry()
        # add a 100m buffer and see how many points intersect multiple waterbodies
        # this is a stand in for how 'confident' we are in assigning a given point to a
        # waterbody
        sf_buffer_wbd <- sf_subset %>% 
          st_transform(., st_crs(huc_wbd)) %>% 
          st_buffer(dist = 100) %>% 
          st_join(., huc_wbd) %>% 
          st_drop_geometry() %>% 
          filter(!is.na(permanent_identifier)) %>% 
          group_by(rowid) %>% 
          summarize(n_wbd_100m = n()) 
        
        # add that info to the sf object
        df_with_wbd <- left_join(sf_with_wbd, sf_buffer_wbd) %>% 
          mutate(n_wbd_100m = if_else(is.na(n_wbd_100m), 0, n_wbd_100m)) %>% 
          select(-rowid)
        
        # return the sf with NHD info
        return(df_with_wbd)
      } else {
        # if no waterbodies, note the huc4 in a text file
        message(paste0("huc4 ", huc4, " contains no waterbodies, noting in '4_compile_sites/mid/no_wbd_huc4.txt'"))
        if (!file.exists("4_compile_sites/mid/no_wbd_huc4.txt")) {
          write_lines(huc4, file = "4_compile_sites/mid/no_wbd_huc4.txt")
          return(NULL)
        } else {
          text <- read_lines("4_compile_sites/mid/no_wbd_huc4.txt")
          new_text <- c(text, huc4)
          write_lines(new_text, "4_compile_sites/mid/no_wbd_huc4.txt")
          return(NULL)
        }
      }
    },
    error = function(e) {
      # if subset failed, note and go to next 
      message(paste0("huc4 ", huc4, " is not within the extent of the NHDPlusHR, 
                     noting in '4_compile_sites/mid/out_extent_wbd_huc4.txt'"))
      if (!file.exists("4_compile_sites/mid/out_extent_wbd_huc4.txt")) {
        write_lines(huc4, file = "4_compile_sites/mid/out_extent_wbd_huc4.txt")
        return(NULL)
      } else {
        text <- read_lines("4_compile_sites/mid/out_extent_wbd_huc4.txt")
        new_text <- c(text, huc4)
        write_lines(new_text, "4_compile_sites/mid/out_extent_wbd_huc4.txt")
        return(NULL)
      }
    })
}
