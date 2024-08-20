add_HUC8_to_sites <- function(sites_without_HUC) {
}

tictoc::tic()
for (r in 1:nrow(sites_without_HUC)) {
  try(one_huc <- get_huc(sites_without_HUC[r, ], type = "huc08"))
  if (!is.null(one_huc)) {
    sites_without_HUC$HUCEightDigitCode[r] = one_huc$huc8
  }
}
tictoc::toc()
# 28.5 mins

tictoc::tic()
sites_without_HUC %>% 
  split(f = .$geometry) %>% 
  mutate(HUCEightDigitCode = get_huc(geometry, type = "huc08")$huc8) 
tictoc::toc()
