#' @title Calculate a point's distance to shore
#' 
#' @description
#' Given points that have assigned NHD waterbodies, calculate the distance of the
#' point to the shoreline
#' 
calculate_distance_to_shore <- function(sites_with_waterbodies, huc8) {
  # filter the waterbodies to those within the huc
  sf_subset <- sites_with_waterbodies %>% 
    filter(HUCEightDigitCode == huc8)
  sf_subset %>% 
    split(f = .$wbd_comid) %>% 
    map(.x = .,
        .f = ~ {
          # grab the associated waterbody
          waterbody <- get_waterbodies(id = .x$wbd_comid) 
          # cast the waterbody into a linestring to measure distance
          waterbody_boundary <- st_cast(st_geometry(waterbody), "MULTILINESTRING")
          # measure the distance, rounded to integer
          .x$dist_to_shore <- round(st_distance(.x, waterbody_boundary), 0)
          # return the sf with the added distance
          .x
        }) %>% 
    bind_rows()
}
