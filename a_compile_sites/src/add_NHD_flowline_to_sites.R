#' @title Locate the closest flowline to a site and measure distance
#' 
#' @description
#' Given a site that is geolocated, find the nearest NHDPlusHR flowline, assign
#' the permanent_identifier to the site and measure the distance to the flowline
#' assigning that distance to the site as well
#' 
#' @param sites_with_huc a spatial feature object of sites that have a huc assigned
#' for spatial subsetting
#' @param huc4 4-digit character string to filter sites by
#' @param GEE_buffer numeric value of buffer for GEE site extraction in meters
#' @param HUC4_manifest tibble from `get_bestres_manifest()` with huc4, url, and
#' etag columns
#' 
#' @returns a list containing dataframe of the spatial feature information with 
#' flowline and distance to flowline assignment as well as a dataframe of the 
#' number of intersections
#' 
#' 
add_NHD_flowline_to_sites <- function(sites_with_huc, 
                                      huc4,
                                      GEE_buffer,
                                      HUC4_manifest) {
  
  message(paste0("Assigning NHD HR flowlines to sites within ", huc4))
  
  tryCatch({
    
    # filter sites for those in a single huc4
    sf_subset <- sites_with_huc %>%
      filter(str_sub(assigned_HUC, 1, 4) == huc4) 
    
    # check to make sure there are obs in this huc/group combo, if not, go to next.
    if (nrow(sf_subset) == 0) { return( NULL ) }
    
    # all HUC4s (including those in CONUS) use NHD Best Resolution, downloaded
    # from The National Map if not already present locally
    gpkg_path <- download_bestres_gpkg(huc4, HUC4_manifest)
    
    # open the NHD flowline layer, coerce to a {sf} object
    # only grab stream/river, canal/ditch and artificial path
    # 556 = coastline, 428 = pipeline, 336 = canal/ditch
    # 460 = stream/river, 468 = drainageway, 558 = artificial path (in waterbody),
    # 420 = underground conduit, 334 = connector
    # filter in the query - some HUC4s have > 1 million flowlines, so reading 
    # only the needed rows is much faster
    #
    # further restrict the read to a bounding box around the sites in this HUC4
    # (padded by ~0.02 degrees, >> the 500 m assignment distance), since the
    # rest of the flowlines can't be the nearest or intersecting ones for sites
    # in sparse HUC4s. the filter must be in the CRS of the layer.
    fl_layer_crs <- st_layers(gpkg_path)$crs[[which(st_layers(gpkg_path)$name == "NHDFlowline")]]
    site_bbox <- st_bbox(st_transform(sf_subset, 4326))
    pad <- 0.02
    site_bbox[c("xmin", "ymin")] <- site_bbox[c("xmin", "ymin")] - pad
    site_bbox[c("xmax", "ymax")] <- site_bbox[c("xmax", "ymax")] + pad
    bbox_wkt <- site_bbox %>%
      st_as_sfc() %>%
      st_transform(fl_layer_crs) %>%
      st_as_text()

    fl_query <- "SELECT * FROM NHDFlowline WHERE ftype IN (336, 460, 558)"
    # (SELECT * since the geometry column name differs between files)
    huc4_fl <- st_read(gpkg_path,
                       query = fl_query,
                       wkt_filter = bbox_wkt,
                       quiet = TRUE)

    # if no flowlines fall in the bbox (very sparse area), fall back to reading
    # the whole layer so that every site still gets a nearest flowline
    if (nrow(huc4_fl) == 0) {
      huc4_fl <- st_read(gpkg_path, query = fl_query, quiet = TRUE)
    }

    huc4_fl <- huc4_fl %>%
      # drop Z/M dimensions, which aren't needed
      st_zm() %>% 
      select(fl_nhd_id = permanent_identifier, 
             fl_gnis_id = gnis_id, 
             fl_gnis_name = gnis_name, 
             fl_fcode = fcode) %>% 
      rowid_to_column("fl_id") %>% 
      mutate(fl_stream_order = NA, # add this column in for binding, no streamorder
             # in best res
             fl_nhd_id = as.character(fl_nhd_id))
    
    # per usual, make sure geo is valid
    # try to make valid polygons 
    # (only repairing the invalid features, since checking is much faster than
    # repairing all of the features)
    not_valid <- which(!st_is_valid(huc4_fl))
    if (length(not_valid) > 0) {
      st_geometry(huc4_fl)[not_valid] <- st_geometry(st_make_valid(huc4_fl[not_valid, ]))
    }
    
    # pull out geometries that are still invalid, if any
    invalid <- huc4_fl[!st_is_valid(huc4_fl), ]
    
    # if there are any, simplify (st_simplify usually fails here, so using 
    # rmapshaper::ms_simplify())
    if (nrow(invalid) > 0) {
      sf_use_s2(TRUE) # make sure that we're using spherical geometry here
      fl_less <- huc4_fl[!huc4_fl$fl_nhd_id %in% invalid$fl_nhd_id, ]
      # for the rare cases that this doesn't work, we include a little error
      # handling here
      try(fixed <- invalid %>% 
            ms_simplify(keep = 0.75))
      if ("fixed" %in% ls()) {
        huc4_fl <- bind_rows(fl_less, fixed)
      } else {
        huc4_fl <- fl_less
      }
    }
    
    # work in a local UTM zone using planar geometry (see set_local_utm())
    s2_state <- sf_use_s2()
    on.exit(sf_use_s2(s2_state), add = TRUE)
    sf_use_s2(FALSE)
    local <- set_local_utm(sf_subset, huc4_fl)
    sf_subset <- local$points
    huc4_fl <- local$features
    
    # walk through all of the sites and calculate how many flowlines they
    # intersect with given the buffer for GEE extraction. this assumes that the
    # buffer does not extend beyond the HUC boundary
    buffered_points <- st_buffer(sf_subset, GEE_buffer)
    intersections <- st_intersects(buffered_points, huc4_fl)
    intersecting_flowlines <- tibble(
      siteSR_id = sf_subset$siteSR_id,
      number_int_fl = lengths(intersections)
    )
    
    # Assign flowline info to flowline points -------------------------------------
    # we'll associate flowlines across all sites. locs are paired to
    # waterbodies in add_NHD_waterbody_to_sites()
    
    # Here, we will just grab the closest flowline and the distance to that 
    # flowline. For each of them, arrange by fl_id for proper st_distance measure.
    nearest_idx <- st_nearest_feature(sf_subset, huc4_fl)
    matched <- sf_subset %>%
      mutate(fl_id = huc4_fl$fl_id[nearest_idx]) %>%
      left_join(., huc4_fl %>% st_drop_geometry())
    
    matched <- matched %>%
      mutate(dist_to_fl = distance_to_nearest_feature(., huc4_fl, nearest_idx),
             # for river/stream/canal/ditch sites: if the distance to the flowline is > 500m, 
             # recode all the flowline info 
             # for lake/res sites: the distance can be retained, since the distance 
             # could be large for large waterbodies
             across(all_of(c("fl_nhd_id", "fl_gnis_id", "fl_gnis_name", "fl_stream_order", "fl_fcode")),
                    ~ if_else(dist_to_fl > 500 & grepl("river|stream|ditch|canal", harmonized_site_type, ignore.case = T),
                              NA,
                              .))) %>%
      select(-fl_id)
    
    # join the matched and matched together, flag fl assignment
    assignment <- matched %>%
      # 0 = point <= 100m from a flowline 
      # 1 = point between 100m and GEE buffer distance (200m) from a flowline (nhd_id info and distance info)
      # 2 = point between GEE buffer distance and 500m proximate to a flowline (nhd_id info and distance info)
      # 3 = point unable to be assigned to a flowline for a stream/canal/ditch site (no nhd_id, but
      #     distance info, dist > 500m)
      # 4 = point > 500m proximate to flowline, but a lake/res site
      # 5 = point does not have HUC8 assignment, so no flowline assigned (not assigned here)
      mutate(flag_fl = case_when(!is.na(fl_nhd_id) & dist_to_fl <= 100 ~ 0,
                                 !is.na(fl_nhd_id) & between(dist_to_fl, 100, GEE_buffer) ~ 1,
                                 !is.na(fl_nhd_id) & between(dist_to_fl, GEE_buffer, 500) ~ 2,
                                 is.na(fl_nhd_id) & !is.na(dist_to_fl) ~ 3,
                                 !is.na(fl_nhd_id) & dist_to_fl > 500 & 
                                   grepl("lake|pond|reservoir", harmonized_site_type, ignore.case = T) ~ 4))
    
    # return unique site info, huc code, and all the flowline info; also intersecting
    # flowlines for all sites in huc
    list(assignment %>% 
           st_drop_geometry() %>% 
           select(siteSR_id, org_id, loc_id, HUCEightDigitCode,
                  harmonized_site_type, MonitoringLocationTypeName, site_tp_cd,
                  all_of(starts_with("fl_")), dist_to_fl, flag_fl),
         intersecting_flowlines
    )
    
  },
  
  # add error handling and note the huc4 if this fails
  error = function(e) {
    # if subset failed, note and go to next 
    message(paste0("HUC4 ", huc4, " was not able to be processed, 
                     noting in 'a_compile_sites/mid/huc4_fl_no_process.txt'"))
    if (!file.exists("a_compile_sites/mid/huc4_fl_no_process.txt")) {
      write_lines(paste(huc4, 
                        sf_subset %>% pull(harmonized_site_type) %>% first(),
                        sf_subset %>% pull(source) %>% first(), sep = " "), 
                  file = "a_compile_sites/mid/huc4_fl_no_process.txt")
      return(NULL)
    } else {
      text <- read_lines("a_compile_sites/mid/huc4_fl_no_process.txt")
      new_text <- c(text, 
                    paste(huc4, 
                          sf_subset %>% pull(harmonized_site_type) %>% first(),
                          sf_subset %>% pull(source) %>% first(), sep = " "))
      write_lines(new_text, "a_compile_sites/mid/huc4_fl_no_process.txt")
      return(NULL)
    }
  })
  
}
