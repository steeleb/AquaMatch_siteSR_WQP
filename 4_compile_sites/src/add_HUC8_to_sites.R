#' @title Add HUC8 information to sites if not populated
#' 
#' @description
#' This funciuon uses the location of a site to determine the HUC8 it
#' falls within and assigns that text to the `HUCEightDigitCode` column native
#' to the WQP site information. This is only run for sites where the `HUCEightDigitCode`
#' is NA
#' 
#' @param sites_without_HUC a simple feature object of WQP sites that do not have
#' the `HUCEightDigitCode` column populated.
#' 
#' @returns a simple feature object with `HUCEightDigitCode` populated if the 
#' sites are associated with a HUC8.
#' 
#' 
add_HUC8_to_sites <- function(sites_without_HUC) {
  # point to the nhdplushr MapServer url
  nhd_plus_hr_url <- "https://hydro.nationalmap.gov/arcgis/rest/services/NHDPlus_HR/MapServer"
  # open that connection
  nhd_hr <- arc_open(nhd_plus_hr_url)
  # grab the NHD huc12 layer using the mapserver
  huc12 <- get_layer(nhd_hr, 12)
  
  # for each site, get the HUC8 associated with it and assign that value to the
  # upstream dataset 
  sites_without_HUC %>% 
    rowid_to_column() %>% 
    split(f = .$rowid) %>% 
    map(.x = .,
        .f = ~ {
          tryCatch({
            one_huc12 <- arc_select(huc12,
                                    filter_geom = .x %>% st_as_sfc())
            # as long as there are rows in the one_huc12, assign the huc8 to the appropriate column
            if (nrow(one_huc12) > 0) {
              .x$HUCEightDigitCode <- str_sub(one_huc12$huc12, 1, 8)
              return(.x)
            } else {
              # and if there is nothing there, just return the site without additional info
              return(.x)
            }
          },
          error = function(e) {
            # if this errors for some reason, return the point, without HUC assigned
            return(.x)
          }
          )}) %>%  
    bind_rows() %>% 
    select(-rowid)
}
