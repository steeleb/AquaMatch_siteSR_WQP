#' @title Make list of WRS tiles to map over
#' 
#' @description
#' Function to define the list of WRS2 tiles for branching
#' 
#' @param detection_method optimal shapefile from get_WRS_detection()
#' @param yaml contents of the yaml .csv file
#' @param locs sf object of user-provided locations for Landsat acqusition
#' 
#' @returns list of WRS2 tiles
#' 
#' 
get_WRS_tiles <- function(detection_method, yaml, locs, poly, centers) {
  WRS <- read_sf("6_siteSR_stack/in/WRS2_descending.shp")
  if (detection_method == "site") {
    locs <- st_as_sf(locs, 
                     coords = c("Longitude", "Latitude"), 
                     crs = yaml$location_crs[1])
    if (st_crs(locs) == st_crs(WRS)) {
      WRS_subset <- WRS[locs,]
    } else {
      locs <- st_transform(locs, st_crs(WRS))
      WRS_subset <- WRS[locs,]
    }
    write_csv(st_drop_geometry(WRS_subset), "6_siteSR_stack/out/WRS_subset_list.csv")
    return(WRS_subset$PR)
  } else {
    message("This workflow is not set up to run extents other than sites.")
  }
}

