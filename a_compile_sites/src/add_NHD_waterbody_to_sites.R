#' @title Add NHD waterbody identifier to sites
#' 
#' @description
#' Using the NHD Best Resolution GeoPackage for each HUC4, assign a NHD identifier to each lake/reservoir site to 
#' associate them with a specific waterbody
#' 
#' @param sites_with_huc simple feature object of sites to pair with waterbodies
#' @param huc4 4-digit character string to filter sites by
#' @param GEE_buffer numeric value of buffer for GEE site extraction in meters
#' @param HUC4_manifest tibble from `get_bestres_manifest()` with huc4, url, and
#' etag columns
#' 
#' @returns a list object of a simple feature object of sites with additional fields from 
#' NHDPlusV2 or NHD Best Resolution file, as well as flags for waterbody 
#' assignment and a dataframe of intersections
#' 
#' 
add_NHD_waterbody_to_sites <- function(sites_with_huc, huc4, GEE_buffer, HUC4_manifest) {
  
  message(paste0("Assigning NHD waterbodies to sites within ", huc4))
  
  tryCatch({
    
    # filter sites for those in a single huc
    sf_subset <- sites_with_huc %>%
      filter(str_sub(assigned_HUC, 1, 4) == huc4, 
             # and to confirm that the site has a flag_HUC8 of 0/1/2
             flag_HUC8 %in% c(0,1,2)) 
    
    # make sure there are results, if not return NULL from the function
    if (nrow(sf_subset) == 0) { return( NULL ) }
    
    # split the sites by harmonized location type - for this, we'll just
    # pair lake/reservoir/other. river/ditch/canal sites are paired in add_NHD_flowline_to_sites()
    huc4_lake_points <- sf_subset %>%
      filter(harmonized_site_type %in% c("Lake/Reservoir", "Estuary", "Pond", "Other"))
    
    # check to make sure there are obs when filtered for lake/reservoir/other, otherwise
    # return null from function
    if (nrow(huc4_lake_points) == 0) { return( NULL ) }
    
    # all HUC4s (including those in CONUS) use NHD Best Resolution, downloaded
    # from The National Map if not already present locally
    gpkg_path <- download_bestres_gpkg(huc4, HUC4_manifest)
    
    # open the NHDWaterbody layer, coerce to a {sf} object
    huc4_wbd <- st_read(gpkg_path, layer = "NHDWaterbody", quiet = TRUE) %>% 
      # filter the waterbodies for ftypes of interest. 390 = lake/pond; 
      # 436 = res, 493 = estuary
      filter(ftype %in% c(390, 436, 493)) %>% 
      select(wb_nhd_id = permanent_identifier, 
             wb_gnis_id = gnis_id, 
             wb_gnis_name = gnis_name, 
             wb_fcode = fcode, 
             wb_areasqkm = areasqkm) %>% 
      rowid_to_column("wbd_id") %>% 
      mutate(wb_nhd_source = "NHDBestRes",
             wb_nhd_id = as.character(wb_nhd_id))
    
    # per usual, make sure geo is valid
    # try to make valid polygons 
    huc4_wbd <- huc4_wbd %>% 
      st_make_valid()
    
    # pull out geometries that are still invalid, if any
    invalid <- huc4_wbd[!st_is_valid(huc4_wbd), ]
    
    # if there are any, simplify (st_simplify usually fails here, so using 
    # rmapshaper::ms_simplify())
    if (nrow(invalid) > 0) {
      sf_use_s2(TRUE) # make sure that we're using spherical geometry here
      wbd_less <- huc4_wbd[!huc4_wbd$wb_nhd_id %in% invalid$wb_nhd_id, ]
      # for the rare cases that this doesn't work, we include a little error
      # handling here
      try(fixed <- invalid %>% 
            ms_simplify(keep = 0.75))
      if ("fixed" %in% ls()) {
        huc4_wbd <- bind_rows(wbd_less, fixed)
      } else {
        huc4_wbd <- wbd_less
      }
    }
    
    # work in a local UTM zone using planar geometry (see set_local_utm())
    s2_state <- sf_use_s2()
    on.exit(sf_use_s2(s2_state), add = TRUE)
    sf_use_s2(FALSE)
    local <- set_local_utm(huc4_lake_points, huc4_wbd)
    huc4_lake_points <- local$points
    huc4_wbd <- local$features
    
    buffered_points <- st_buffer(huc4_lake_points, GEE_buffer)
    intersections <- st_intersects(buffered_points, huc4_wbd)
    intersecting_waterbodies <- tibble(
      siteSR_id = huc4_lake_points$siteSR_id,
      number_int_wb = lengths(intersections)
    )    
    
    # Assign waterbodies to Lake points -------------------------------------
    
    # grab the waterbody rowid for the points - without a buffer. While
    # there are more steps to this workflow, it's exceptionally faster
    # than st_intersection().
    
    huc4_wbd_intersect <- st_intersects(huc4_lake_points, huc4_wbd)
    
    # see if there are any intersections, if not skip
    if (any(lengths(huc4_wbd_intersect) > 0)) {
      
      # get lake points (just ids) to map by
      to_match <- huc4_lake_points %>%
        st_drop_geometry(.) %>%
        rowid_to_column("location_id") %>%
        select(location_id, siteSR_id)
      
      matched <- map2(.x = to_match$siteSR_id,
                      .y = to_match$location_id,
                      .z = huc4_wbd_intersect,
                      .f = \(.x, .y, .z) {
                        tibble(siteSR_id = .x,
                               wbd_id = .z[[.y]])
                      }) %>%
        bind_rows() %>%
        left_join(., huc4_wbd %>% st_drop_geometry()) %>%
        select(-wbd_id) %>%
        left_join(huc4_lake_points, .) %>%
        filter(!is.na(wb_nhd_id)) %>%
        # add distance to waterbody for rbind later, since these are WITHIN a waterbody
        mutate(dist_to_wb = NA)
      
      # cast the waterbodies into a linestrings to measure distance
      waterbody_boundary <- st_cast(st_geometry(huc4_wbd), "MULTILINESTRING") %>% 
        # dissolve these into a single geometry, since the identity of the line doesn't
        # matter
        st_union()
      
      # measure the distance, rounded to integer, set as numeric (otherwise comes back as a matrix)
      matched$dist_to_shore <- as.numeric(round(st_distance(matched, waterbody_boundary)))
      
      # and provide a list of ids for filtering unmatched
      matched_siteSR_id <- matched$siteSR_id
      
    } else { 
      # just return no matched info
      matched <- NULL
      matched_siteSR_id <- NA
    }
    
    # get any unmatched Lake points. Here, we will just grab the closest
    # waterbody and the distance to that waterbody. For each of them,
    # arrange by wbd_id for proper st_distance measure.
    unmatched <- huc4_lake_points %>%
      filter(!siteSR_id %in% matched_siteSR_id)
    nearest_wbd <- st_nearest_feature(unmatched, huc4_wbd)
    
    unmatched <- unmatched %>%
      mutate(wbd_id = huc4_wbd$wbd_id[nearest_wbd]) %>% 
      left_join(., huc4_wbd %>% st_drop_geometry()) %>%
      mutate(dist_to_wb = round(distance_to_nearest_feature(., huc4_wbd, nearest_wbd))) %>% 
      # if the distance to the waterbody is > 500m, recode all the waterbody info
      mutate(across(all_of(c("wb_nhd_id", "wb_gnis_id", "wb_gnis_name", "wb_areasqkm")),
                    ~ if_else(dist_to_wb > 500,
                              NA,
                              .))) %>%
      select(-wbd_id) %>% 
      # add for rbind ease
      mutate(dist_to_shore = NA)
    
    # join the matched and unmatched together, flag wbd assignment
    assignment <- rbind(matched, unmatched) %>%
      # 0 = point inside waterbody (nhd_id info, but no distance_to_wb)
      # 1 = point distance <= GEE site buffer (default 200) and not inside waterbody
      # 2 = point distance > GEE buffer from to waterbody, waterbody info is from
      # closest waterbody. (nhd_id info and distance info)
      # 3 = point unable to be assigned to waterbody (no nhd_id, but
      # distance info)
      # 4 = point does not have HUC8 assignment, so no waterbody assigned (not assigned here)
      mutate(flag_wb = case_when(!is.na(wb_nhd_id) & is.na(dist_to_wb) & !is.na(dist_to_shore) ~ 0,
                                 !is.na(wb_nhd_id) & dist_to_wb <= GEE_buffer & is.na(dist_to_shore) ~ 1,
                                 !is.na(wb_nhd_id) & dist_to_wb > GEE_buffer & is.na(dist_to_shore) ~ 2,
                                 is.na(wb_nhd_id) & !is.na(dist_to_wb) & is.na(dist_to_shore) ~ 3)) %>% 
      left_join(., intersecting_waterbodies)
    
    # return unique site info, huc code, and all the waterbody info
    list(
      assignment %>% 
        st_drop_geometry() %>% 
        select(siteSR_id, org_id, loc_id, HUCEightDigitCode, 
               harmonized_site_type, MonitoringLocationTypeName, site_tp_cd,
               all_of(starts_with("wb_")), dist_to_shore, dist_to_wb, flag_wb),
      intersecting_waterbodies
    )
    
  },
  
  # add error handling and note the huc4 if this fails
  
  error = function(e) {
    # if subset failed, note and go to next 
    message(paste0("HUC4 ", huc4, " was not able to be processed, 
                     noting in 'a_compile_sites/mid/huc4_wbd_no_process.txt'"))
    if (!file.exists("a_compile_sites/mid/huc4_wbd_no_process.txt")) {
      write_lines(paste(huc4, 
                        sf_subset %>% pull(harmonized_site_type) %>% first(),
                        sf_subset %>% pull(source) %>% first(), sep = " "), 
                  file = "a_compile_sites/mid/huc4_wbd_no_process.txt")
      return(NULL)
    } else {
      text <- read_lines("a_compile_sites/mid/huc4_wbd_no_process.txt")
      new_text <- c(text, 
                    paste(huc4, 
                          sf_subset %>% pull(harmonized_site_type) %>% first(),
                          sf_subset %>% pull(source) %>% first(), sep = " "))
      write_lines(new_text, "a_compile_sites/mid/huc4_wbd_no_process.txt")
      return(NULL)
    }
  })
  
}

