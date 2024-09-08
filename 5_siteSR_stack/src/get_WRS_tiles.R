#' @title Make list of WRS tiles to map over
#' 
#' @description
#' Function to define the list of WRS2 tiles for branching
#' 
#' @param detection_method optimal shapefile from get_WRS_detection()
#' @param yaml contents of the yaml .csv file
#' @param locs sf object of user-provided locations for Landsat acqusition
#' 
#' @returns list of WRS2 tiles, silently returns sites with WRS info
#' 
#' 
get_WRS_tiles <- function(detection_method, yaml, locs) {
  WRS <- read_sf("5_siteSR_stack/in/WRS2_descending.shp")
  if (detection_method == "site") {
    sf <- st_as_sf(locs, 
                   coords = c("Longitude", "Latitude"), 
                   crs = yaml$location_crs) %>% 
      st_buffer(buffer = yaml$site_buffer)
    if (st_crs(sf) == st_crs(WRS)) {
      WRS_subset <- WRS[sf,]
    } else {
      sf <- st_transform(sf, st_crs(WRS))
      WRS_subset <- WRS[sf,]
    }
    # make a stub file for filtering in Py that has WRS info, this will result
    # in more rows than sf due to points being in multiple path-rows
    locs_w_WRS <- st_join(sf, WRS_subset) %>% 
      # but check to see that each point (and buffer) is completely within the 
      # individual PR
      split(f = .$PR) %>% 
      map(.x = .,
          .f = ~ {
            one_WRS <- WRS_subset %>% 
              filter(PR == unique(.$PR))
            contained <- st_within(.,
                                   one_WRS,
                                   sparse = FALSE) %>% 
              rename(is_contained_by_WRS = V1)
            bind_cols(., contained)
          }) %>% 
      st_drop_geometry() %>% 
      left_join(., locs) %>% 
      select(id, Latitude, Longitude, PR) %>% 
      write_csv("5_siteSR_stack/run/locs_with_WRS.csv")
    write_csv(st_drop_geometry(WRS_subset), "5_siteSR_stack/run/WRS_subset_list.csv")
    return(unique(locs_w_WRS$PR))
  } else {
    message("This workflow is not set up to run extents other than sites.")
  }
}

