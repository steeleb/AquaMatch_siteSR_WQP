#' @title Add NHD waterbody identifier to sites
#' 
#' @description
#' Using the USGS MapServer, assign a permanent identifier to each site to associate them with 
#' a specific waterbody
#' 
#' @param sites_with_huc simple feature object of sites to pair with waterbodies
#' @param huc4 4-digit character string to filter sites by
#' @param buffer distance from a given point to determine overlapping features
#' 
#' @returns a dataframe of the simple feature object of sites with additional 
#' fields from the NHDPlusHR. Silently returns text files with huc4s that failed 
#' this function
#' 
#' 
add_NHD_waterbody_to_sites <- function(sites_with_huc, huc4, buffer) {
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
  
  # make the box a bit bigger for proper overlap
  bbox <- sf_subset %>% 
    st_buffer(buffer) %>% 
    st_bbox() %>% 
    st_as_sfc() 
  
  tryCatch({     
    
    # when this function errors, it's usually here. The request can be too large and it
    # fails. 
    waterbodies_subset <- arc_select(waterbodies,
                                     # also limit the type and size of waterbody
                                     # to try to stay within the limits of 
                                     # the query 
                                     where = "ftype IN (390, 436, 493) AND areasqkm >= 0.01",
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
        sf_use_s2(FALSE) # use more flat-earth setting to avoid errors
        wbd_less <- huc_wbd[!huc_wbd$permanent_identifier %in% invalid$permanent_identifier,]
        fixed <- invalid %>% 
          ms_simplify(keep = 0.75)
        huc_wbd <- bind_rows(wbd_less, fixed)
        sf_use_s2(TRUE) # but turn spherical earth back on
        
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
      
      # get distance to shore for these
      points = st_as_sf(sf_with_wbd, coords = c("WGS84_Longitude", "WGS84_Latitude"), crs = "EPSG:4326")
      
      # filter the waterbodies to those that have points associated with them
      filtered_waterbodies <- huc_wbd %>% 
        filter(permanent_identifier %in% unique(sf_with_wbd$nhd_permanent_identifier))
      
      # cast the waterbodies into a linestrings to measure distance
      waterbody_boundary <- st_cast(st_geometry(filtered_waterbodies), "MULTILINESTRING") %>% 
        # dissolve these into a single geometry, since the identity of the line doesn't
        # matter
        st_union()
      
      # transform the point into same crs
      points = st_transform(points, crs = st_crs(waterbody_boundary))
      
      # measure the distance, rounded to one decimal resolution
      sf_with_wbd$dist_to_shore <- round(st_distance(points, waterbody_boundary), 1)
      
      # add a 100m buffer and see how many points intersect multiple waterbodies
      # this is a stand in for how 'confident' we are in assigning a given point to a
      # waterbody
      sf_buffer_wbd <- sf_subset %>% 
        st_transform(., st_crs(huc_wbd)) %>% 
        st_buffer(dist = buffer) %>% 
        st_join(., huc_wbd) %>% 
        st_drop_geometry() %>% 
        filter(!is.na(permanent_identifier)) %>% 
        group_by(rowid) %>% 
        summarize(n_wbd_buff = n()) 
      
      # add that info to the sf object
      df_with_wbd <- full_join(sf_with_wbd, sf_buffer_wbd) %>% 
        st_drop_geometry()
      
      unresolved_wbd <- sf_subset %>% 
        filter(!(rowid %in% unique(df_with_wbd$rowid))) %>% 
        st_drop_geometry()
      
      # return the df with NHD info and unresolved wbd
      df_with_water <- full_join(df_with_wbd, unresolved_wbd) %>% 
        select(-rowid)
      
      return(df_with_water)
      
    } else {
      
      # usually the request just errors and is sent to the catch, but just in case
      # if no waterbodies returned, note the huc4 in a text file.
      message(paste0("Observation extent within huc4 ", huc4, " contained no waterbodies, 
                       noting in '4_compile_sites/mid/no_wbd_huc4.txt'"))
      
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
    
    # if query errored
    message(paste0("Observation extent within huc4 ", huc4, " is outside of
                     NHDPlusHR availability."))
    
    if (!file.exists("4_compile_sites/mid/out_extent_wb_huc4.txt")) {
      
      write_lines(huc4, file = "4_compile_sites/mid/out_extent_wb_huc4.txt")
      return(NULL)
      
    } else {
      
      text <- read_lines("4_compile_sites/mid/out_extent_wb_huc4.txt")
      new_text <- c(text, huc4)
      write_lines(new_text, "4_compile_sites/mid/out_extent_wb_huc4.txt")
      return(NULL)
      
    }
    
  })
  
}
