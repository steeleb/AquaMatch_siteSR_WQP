#' @title Calculate a point's distance to shore
#' 
#' @description
#' Given points that have assigned NHD waterbodies, calculate the distance of the
#' point to the shoreline
#' 
calculate_distance_to_shore <- function(sites_with_waterbodies, huc4) {
  # filter the waterbodies to those within the huc
  sf_subset <- sites_with_waterbodies %>% 
    filter(str_sub(HUCEightDigitCode, 1, 4) == huc4) %>% 
    filter(!is.na(nhd_permanent_identifier))
  
  # set up MapSever
  # point to the nhdplushr MapServer url
  nhd_plus_hr_url <- "https://hydro.nationalmap.gov/arcgis/rest/services/NHDPlus_HR/MapServer"
  # open that connection
  nhd_hr <- arc_open(nhd_plus_hr_url)
  # grab the NHD waterbodies layer using the mapserver
  waterbodies <- get_layer(nhd_hr, 9)
  
  sf_subset %>% 
    split(f = .$nhd_permanent_identifier) %>% 
    map(.x = .,
        .f = ~ {
          # create an sf from the points
          points = st_as_sf(.x, coords = c("WGS84_Longitude", "WGS84_Latitude"), crs = "EPSG:4326")
          # grab the associated waterbody
          waterbody <- arc_select(waterbodies,
                                  # use SQL query for where
                                  where = paste0("Permanent_Identifier = '", 
                                                 unique(.x$nhd_permanent_identifier), 
                                                 "'"))
          # cast the waterbody into a linestring to measure distance
          waterbody_boundary <- st_cast(st_geometry(waterbody), "MULTILINESTRING")
          # transform the point into same crs
          points = st_transform(points, crs = st_crs(waterbody_boundary))
          # measure the distance, rounded to integer
          .x$dist_to_shore <- round(st_distance(points, waterbody_boundary), 0)
          # return the sf with the added distance
          .x
        }) %>% 
    bind_rows()
}
