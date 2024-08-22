#' @title Add HUC8 information to sites if not populated
#' 
#' @description
#' This funciton uses the location of a site to determine the HUC8 it
#' falls within and assigns that text to the `HUCEightDigitCode` column native
#' to the WQP site informaiton. This is only run for sites where the `HUCEightDigitCode`
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
  for (r in 1:nrow(sites_without_HUC)) {
    # wrap in try for sites that are unassociated with NHD HUC8 extent
    try(one_huc <- get_huc(sites_without_HUC[r, ], type = "huc08"))
    # if one huc has data in it, assign the huc8 to the appropriate column
    if (!is.null(one_huc)) {
      sites_without_HUC$HUCEightDigitCode[r] = one_huc$huc8
    }
  }
  # return the df that now has as many HUC8s filled as possible
  sites_without_HUC
}
  