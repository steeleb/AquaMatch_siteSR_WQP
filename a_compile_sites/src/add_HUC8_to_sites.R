#' @title Add HUC8/HUC4 information to AquaMatch sites
#' 
#' @description
#' This function uses the location of a site to determine the HUC8 it
#' falls within and assigns that text to the `assigned_HUC` column native
#' to the WQP/NIWS site information. 
#' 
#' @param sites a simple feature object of WQP/NWIS sites 
#' 
#' @returns a simple feature object with `assigned_HUC` populated. Silently saves
#' a file of sites that couldn not be resolved to 
#' `a_compile_sites/out/XXX_sites_unable_to_assign_HUC08.csv` where XXX is the 
#' information source (AM, NWIS, WQP)
#' 
#' 
add_HUC8_to_sites <- function(sites) {
  # for each site, get the HUC8 associated with it and assign that value to the
  # upstream dataset 
  HUC08_assigned <- sites %>% 
    split(f = .$siteSR_id) %>% 
    map(.x = .,
        .f = ~ {
          tryCatch({
            # we can use the nhdplusTools package to grab this
            one_huc <- get_huc(.x, type = "huc08", buffer = 0.1)
            .x$assigned_HUC <- one_huc$huc8
            return(.x)
          },
          error = function(e) {
            # Try HUC04 as backup
            tryCatch({
              one_huc <- get_huc(.x, type = "huc04", buffer = 0.1)
              .x$assigned_HUC <- one_huc$huc4
              return(.x)
            }, error = function(e2) {
              # Could not assign either HUC 8 or 4
              .x$assigned_HUC <- NA
              return(.x)
            })
          }
          )}) %>%  
    bind_rows() %>% 
    filter(!is.na(assigned_HUC))
  # make a list of the sites that couldn't be assigned
  failed_to_assign <- sites %>% 
    filter(!siteSR_id %in% HUC08_assigned$siteSR_id)
  if (nrow(failed_to_assign) > 0) {
    # save to file
    write_csv(failed_to_assign, paste0("a_compile_sites/out/", 
                                       unique(HUC08_assigned$source), 
                                       "_sites_unable_to_assign_HUC08.csv"))
  }
  # return assigned file
  bind_rows(HUC08_assigned, failed_to_assign)
}
