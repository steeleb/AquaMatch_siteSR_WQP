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
  # grab the NHD waterbodies layer using the mapserver and SQL query for the NHD Permanent IDs
  waterbodies <- get_layer(nhd_hr, 9)
  query = paste0("Permanent_Identifier IN (",
                 paste(
                   paste0("'",
                          unique(sf_subset$nhd_permanent_identifier),
                          "'"),
                   collapse = (", ")),
                 ")")
  
  # filter the waterbodies by permanent identifier list
  filtered_waterbodies <- arc_select(waterbodies,
                                     # use SQL query for where
                                     where = query)
  
  # create an sf from the points
  points = st_as_sf(sf_subset, coords = c("WGS84_Longitude", "WGS84_Latitude"), crs = "EPSG:4326")
  
  # cast the waterbodies into a linestrings to measure distance
  waterbody_boundary <- st_cast(st_geometry(filtered_waterbodies), "MULTILINESTRING") %>% 
    # dissolve these into a single geometry, since the identity of the line doesn't
    # matter
    st_union()
  # transform the point into same crs
  points = st_transform(points, crs = st_crs(waterbody_boundary))
  # measure the distance, rounded to integer
  sf_subset$dist_to_shore <- round(st_distance(points, waterbody_boundary), 0)
  sf_subset
}
