#' @title Add NHD waterbody identifier to sites
#' 
#' @description
#' Using nhdPlusTools::get_waterbody(), assign a NHD identifier to each site to associate them with 
#' a specific waterbody
#' 
#' @param sites_with_huc simple feature object of sites to pair with waterbodies
#' @param huc4 4-digit character string to filter sites by
#' @param buffer distance from a given point to determine overlapping features
#' 
#' @returns a dataframe of the simple feature object of sites with additional 
#' fields from NHDPlusV2.
#' 
#' 
add_NHD_waterbody_to_sites <- function(sites_with_huc, huc4, buffer) {
  
  message(paste0("Assigning NHD waterbodies to sites within ", huc4))
  
  # filter sites for those in a single huc
  sf_subset <- sites_with_huc %>%
    filter(str_sub(HUCEightDigitCode, 1, 4) == huc4) %>% 
    rowid_to_column()
  
  # index over huc 8, grab waterbodies and intersect
  
  # if huc4 >= 1900, process differently

}
