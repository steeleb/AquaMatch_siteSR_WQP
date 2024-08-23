#' @title Locate the closest flowline to a site and measure distance
#' 
#' @description
#' Given a site that is geolocated, find the nearest NHDPlusHR flowline, assign
#' the permanent_identifier to the site and measure the distance to the flowline
#' assigning that distance to the site as well
#' 
#' @param sites_with_huc a spatial feature object of sites that have a huc assigned
#' for spatial subsetting
#' @param huc8 8-digit character string to filter sites by
#' 
#' @returns a dataframe of the spatial feature information with flowline and 
#' distance to flowline assignment. Silently returns any hucs that had no
#' flowlines associated with them
#' 
#' 
add_NHD_flowline_to_sites <- function(sites_with_huc, huc8) {
  message(paste0("Assigning NHD HR flowlines to sites within ", huc8))
  
  # filter sites for those in a single huc
  sf_subset <- sites_with_huc %>%
    filter(HUCEightDigitCode == huc8) 
  
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
              .x$flow_perm_id <- flowlines_subset$permanent_identifier[.x$closest_flow_rowid]
              .x
            }) %>% 
        bind_rows() %>% 
        select(-c(closest_flow_rowid, rowid)) %>% 
        st_drop_geometry()
      return(df_subset_with_flow)
      
    } else { # if there are no flowlines in the extent
      
      message(paste0("HUC8 ", huc8, " doesn't contain any flowlines.
                   This huc will be documented in the file 
                   `4_compile_sites/mid/no_flow_huc8.txt"))
      if (!file.exists("4_compile_sites/mid/no_flow_huc8.txt")) {
        write_lines(huc8, file = "4_compile_sites/mid/no_flow_huc8.txt")
        return(NULL)
      } else {
        text <- read_lines("4_compile_sites/mid/no_flow_huc8.txt")
        new_text <- c(text, huc8)
        write_lines(new_text, "4_compile_sites/mid/no_flow_huc8.txt")
        return(NULL)
      }
    }
  },
  
  error = funciton(e) {
    # if subset failed, note and go to next 
    message(paste0("HUC8 ", huc8, " is not within the extent of the NHDPlusHR, 
                     noting in '4_compile_sites/mid/out_extent_flow_huc8.txt'"))
    if (!file.exists("4_compile_sites/mid/out_extent_flow_huc8.txt")) {
      write_lines(huc8, file = "4_compile_sites/mid/out_extent_flow_huc8.txt")
      return(NULL)
    } else {
      text <- read_lines("4_compile_sites/mid/out_extent_flow_huc8.txt")
      new_text <- c(text, huc8)
      write_lines(new_text, "4_compile_sites/mid/out_extent_flow_huc8.txt")
      return(NULL)
    }
  })
}