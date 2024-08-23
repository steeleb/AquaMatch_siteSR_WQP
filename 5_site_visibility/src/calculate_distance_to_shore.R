#' @title Calculate a point's distance to shore
#' 
#' @description
#' Given points that have assigned NHD waterbodies, calculate the distance of the
#' point to the shoreline
#' 
calculate_distance_to_shore <- function(sites_with_waterbodies, huc8) {
  # filter the waterbodies to those within the huc
  sf_subset <- sites_with_waterbodies %>% 
    filter(HUCEightDigitCode == huc8) %>% 
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
          # grab the associated waterbody
          waterbody <- arc_select(waterbodies,
                                  where = paste0("Permanent_Identifier = '", 
                                                 unique(.x$nhd_permanent_identifier), 
                                                 "'")
          # cast the waterbody into a linestring to measure distance
          waterbody_boundary <- st_cast(st_geometry(waterbody), "MULTILINESTRING")
          # measure the distance, rounded to integer
          .x$dist_to_shore <- round(st_distance(.x, waterbody_boundary), 0)
          # return the sf with the added distance
          .x
        }) %>% 
    bind_rows()
}
