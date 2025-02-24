#' @title Load location information
#' 
#' @description
#' Load in and format location file using config settings
#' 
#' @param yaml contents of the yaml .csv file
#' @param type character string indicating which location file to pull, 'pekel'
#' or 'siteSR'
#' @param out_folder folder path where the output should be saved
#' 
#' @returns dataframe of the reformatted location data or the message
#' 'Not configured to use site locations'. Silently saves 
#' the .csv in the `out_folder` directory path if configured for site
#' acquisition.
#' 
#' 
grab_locs <- function(yaml, type, out_folder) {
  if (type == "pekel") {
    locs <- read_csv(file.path(yaml$pekel_data_dir, yaml$pekel_location_file))
  } else if (type == "siteSR") {
    locs <- read_csv(file.path(yaml$siteSR_data_dir, yaml$siteSR_location_file))
  } else {
    stop("Location file type not recognized. Only 'pekel' and 'siteSR' are 
            accepted arguments.",
         call. = TRUE)
  }
  if (yaml$site_filter) {
    locs <- locs %>% 
      filter(grepl("river|stream|lake|reservoir", 
                   MonitoringLocationTypeName, 
                   ignore.case = T))
  }
  # store yaml info as objects
  lat <- yaml$latitude
  lon <- yaml$longitude
  id <- yaml$unique_id
  # apply objects to tibble
  locs <- locs %>% 
    rename_with(~c("Latitude", "Longitude", "id"), any_of(c(lat, lon, id)))
  write_csv(locs, file.path(out_folder, "locs.csv"))
  locs
}

