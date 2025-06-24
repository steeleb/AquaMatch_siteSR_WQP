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
#' a file of sites that can not not be resolved to 
#' `a_compile_sites/out/XXX_YYY_sites_unable_to_assign_HUC08.csv` where XXX is the 
#' information source (AM, NWIS, WQP) and YYY is the org_id.
#' 
#' 
add_HUC8_to_sites <- function(sites, hucs) {
  # for each site, get the HUC8 associated with it and assign that value to the
  # upstream dataset 
  transformed_sites <- st_transform(sites, st_crs(hucs))
  HUC08_assigned <- st_join(transformed_sites, hucs %>% select(assigned_HUC = huc8)) %>% 
    st_transform(., crs = "EPSG:4326") 
  # make a list of the sites that couldn't be assigned
  failed_to_assign <- sites %>% 
    filter(!siteSR_id %in% HUC08_assigned$siteSR_id)
  if (nrow(failed_to_assign) > 0) {
    # save to file
    write_csv(failed_to_assign, paste0("a_compile_sites/out/failed_HUC/", 
                                       unique(sites$source),
                                       "_",
                                       unique(sites$org_id),
                                       "_sites_unable_to_assign_HUC08.csv"))
  }
  # return assigned file
  bind_rows(HUC08_assigned, failed_to_assign)
}
