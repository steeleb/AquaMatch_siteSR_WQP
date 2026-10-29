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
#' `a_compile_sites/out/failed_HUC/XXX_YYY_sites_unable_to_assign_HUC08.csv` where 
#' XXX is the information source (NWIS, WQP) and YYY is the harmonized site type.
#' 
#' 
add_HUC8_to_sites <- function(sites, hucs) {
  # joining the full site table against the national WBD polygons in one go
  # uses several GB per branch and crashes the crew workers when branches run
  # in parallel. Instead, intersect only the point geometries and attach the
  # result back to the site table.
  hucs_slim <- hucs %>% 
    select(assigned_HUC = huc8) %>% 
    st_transform("EPSG:4326")
  
  site_pts <- sites %>% 
    select(siteSR_id) %>% 
    st_transform("EPSG:4326")
  
  # the WBD polygons are in a geographic CRS; planar intersection avoids slow
  # and memory-heavy s2 operations (and s2 validity errors) on the national data
  s2_state <- sf_use_s2()
  on.exit(sf_use_s2(s2_state))
  sf_use_s2(FALSE)
  
  # sites on a boundary can match more than one HUC8; keep the first so that
  # the number of rows matches the input. This is done in a single call, since
  # repeated st_intersects() calls against the national polygons accumulate
  # native memory.
  hit <- st_intersects(site_pts, hucs_slim) %>% 
    map_int(\(i) if (length(i) == 0) NA_integer_ else i[[1]])
  assigned_HUC <- hucs_slim$assigned_HUC[hit]
  
  HUC08_assigned <- sites %>% 
    mutate(assigned_HUC = assigned_HUC)
  
  # make a list of the sites that couldn't be assigned (sites are grouped by
  # source and site type upstream, so each is unique within a branch)
  failed_to_assign <- HUC08_assigned %>% 
    filter(is.na(assigned_HUC))
  if (nrow(failed_to_assign) > 0) {
    # save to file
    write_csv(failed_to_assign, paste0("a_compile_sites/out/failed_HUC/", 
                                       unique(sites$source),
                                       "_",
                                       str_replace_all(unique(sites$harmonized_site_type), "[^A-Za-z0-9]+", "_"),
                                       "_sites_unable_to_assign_HUC08.csv"))
  }
  # return assigned file
  HUC08_assigned
}
