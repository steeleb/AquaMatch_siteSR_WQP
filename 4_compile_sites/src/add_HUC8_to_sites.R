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
  # for each site, get the HUC8 associated with it and assign that value to the
  # upstream dataset 
  sites_without_HUC %>% 
    rowid_to_column() %>% 
    split(f = .$rowid) %>% 
    map(.x = .,
        .f = ~ {
          tryCatch({
            # we can use the nhdplusTools package to grab this, since WBD hasn't
            # changed significantly over time and it's a bunch more efficient than
            # a mapserver query for NHDPlusHR
            one_huc <- get_huc(.x, type = "huc08")
            .x$HUCEightDigitCode <- one_huc$huc8
            return(.x)
          },
          error = function(e) {
            # if this errors because no HUC8 is available, return the point, 
            # without HUC assigned.
            return(.x)
          }
          )}) %>%  
    bind_rows() %>% 
    select(-rowid)
}
