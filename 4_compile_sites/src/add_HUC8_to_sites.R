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
  