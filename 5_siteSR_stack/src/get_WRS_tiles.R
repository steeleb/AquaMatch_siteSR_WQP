#' @title Make list of WRS pathrows to map over
#' 
#' @description
#' Function to define the list of WRS2 pathrows for branching
#' 
#' @param detection_method optimal shapefile from get_WRS_detection()
#' @param yaml contents of the yaml .csv file
#' @param locs sf object of user-provided locations for Landsat acqusition
#' 
#' @returns list of WRS2 pathrows, silently returns sites with WRS info
#' 
#' 
get_WRS_pathrows <- function(detection_method, yaml, locs) {
  WRS <- read_sf("5_siteSR_stack/in/WRS2_descending.shp")
  if (detection_method == "site") {
    sf <- st_as_sf(locs, 
                   coords = c("Longitude", "Latitude"), 
                   crs = yaml$location_crs) 
    if (st_crs(sf) == st_crs(WRS)) {
      WRS_subset <- WRS[sf,]
    } else {
      sf <- st_transform(sf, st_crs(WRS))
      WRS_subset <- WRS[sf,]
    }
    # save the file for use later (we don't track this, but need it for the python
    # workflow)
    write_csv(st_drop_geometry(WRS_subset), "5_siteSR_stack/out/WRS_subset_list.csv")
    # return the unique PR list
    WRS_subset$WRSPR
  } else {
    message("This workflow is not set up to run extents other than sites.")
  }
}

