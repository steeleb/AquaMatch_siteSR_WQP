#' @title Locate the closest flowline to a site and measure distance
#' 
#' @description
#' Given a site that is geolocated, find the nearest NHDPlusHR flowline, assign
#' the permanent_identifier to the site and measure the distance to the flowline
#' assigning that distance to the site as well
#' 
#' @param sites_with_huc a spatial feature object of sites that have a huc assigned
#' for spatial subsetting
#' @param huc4 4-digit character string to filter sites by
#' 
#' @returns a dataframe of the spatial feature information with flowline and 
#' distance to flowline assignment. Silently returns any hucs that had no
#' flowlines associated with them
#' 
#' 
add_NHD_flowline_to_sites <- function(sites_with_huc, huc4) {
  message(paste0("Assigning NHD HR flowlines to sites within ", huc4))
  
  # filter sites for those in a single huc4
  sf_subset <- sites_with_huc %>%
    filter(str_sub(HUCEightDigitCode, 1, 4) == huc4) 
  
  # point to the nhdplushr MapServer url
  nhd_plus_hr_url <- "https://hydro.nationalmap.gov/arcgis/rest/services/NHDPlus_HR/MapServer"
  # open that connection
  nhd_hr <- arc_open(nhd_plus_hr_url)
  # grab the NHD flowlines layer using the mapserver
  flowlines <- get_layer(nhd_hr, 3)
  
  # use the bounding box of the sites to query the flowlines
  bbox = st_bbox(sf_subset) %>% 
    st_as_sfc()
  
  tryCatch({
    flowlines_subset <- arc_select(flowlines,
                                   filter_geom = bbox) 
    
    # make sure that the huc 8 contains flowlines
    if (nrow(flowlines_subset) > 0) {
      # transform the points to the same crs as the flowlines
      sf_subset <- st_transform(sf_subset, crs = st_crs(flowlines_subset))
      # get the rowid of the closest flowline
      sf_subset$closest_flow_rowid <- st_nearest_feature(sf_subset, flowlines_subset)
      df_subset_with_flow <- sf_subset %>% 
        rowid_to_column() %>% 
        split(f = .$rowid) %>% 
        map(.x = .,
            .f = ~{
              # calculate distance
              .x$dist_to_flow <- st_distance(.x, flowlines_subset[.x$closest_flow_rowid, ])
              # and store the permanent_id
              .x$flow_permanent_identifier <- flowlines_subset$permanent_identifier[.x$closest_flow_rowid]
              .x
            }) %>% 
        bind_rows() %>% 
        select(-c(closest_flow_rowid)) %>% 
        st_drop_geometry()
      
      # add a 100m buffer and see how many points intersect multiple flowlines
      # this is a stand in for how 'confident' we are in assigning a given point to a
      # flowline
      df_buffer_flow <- sf_subset %>% 
        st_transform(., st_crs(flowlines_subset)) %>% 
        st_buffer(dist = 100) %>% 
        st_join(., flowlines_subset) %>% 
        st_drop_geometry() %>% 
        filter(!is.na(permanent_identifier)) %>% 
        group_by(rowid) %>% 
        summarize(n_flow_100m = n())
      
      # add that info to the dataframe
      df_with_flow <- left_join(df_subset_with_flow, df_buffer_flow) %>% 
        mutate(n_flow_100m = if_else(is.na(n_flow_100m), 0, n_flow_100m)) %>% 
        select(-rowid)
      
      return(df_with_flow)
      
    } else { # if there are no flowlines in the extent
      
      message(paste0("HUC4 ", huc4, " doesn't contain any flowlines.
                   This huc will be documented in the file 
                   `4_compile_sites/mid/no_flow_huc4.txt"))
      if (!file.exists("4_compile_sites/mid/no_flow_huc4.txt")) {
        write_lines(huc4, file = "4_compile_sites/mid/no_flow_huc4.txt")
        return(NULL)
      } else {
        text <- read_lines("4_compile_sites/mid/no_flow_huc4.txt")
        new_text <- c(text, huc4)
        write_lines(new_text, "4_compile_sites/mid/no_flow_huc4.txt")
        return(NULL)
      }
    }
  },
  
  error = function(e) {
    # if subset failed, note and go to next 
    message(paste0("HUC4 ", huc4, " is not within the extent of the NHDPlusHR, 
                     noting in '4_compile_sites/mid/out_extent_flow_huc4.txt'"))
    if (!file.exists("4_compile_sites/mid/out_extent_flow_huc4.txt")) {
      write_lines(huc4, file = "4_compile_sites/mid/out_extent_flow_huc4.txt")
      return(NULL)
    } else {
      text <- read_lines("4_compile_sites/mid/out_extent_flow_huc4.txt")
      new_text <- c(text, huc4)
      write_lines(new_text, "4_compile_sites/mid/out_extent_flow_huc4.txt")
      return(NULL)
    }
  })
}