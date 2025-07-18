#' @title Add NHD waterbody identifier to sites
#' 
#' @description
#' Using nhdPlusTools::get_waterbody() or NHD Best Resolution shapefile for 
#' non-CONUS HUC4's, assign a NHD identifier to each lake/reservoir site to 
#' associate them with a specific waterbody
#' 
#' @param sites_with_huc simple feature object of sites to pair with waterbodies
#' @param huc4 4-digit character string to filter sites by
#' @param GEE_buffer numeric value of buffer for GEE site extraction in meters
#' @param huc8_wbd sf object containing staged huc8 objects from TNM
#' 
#' @returns a list object of a simple feature object of sites with additional fields from 
#' NHDPlusV2 or NHD Best Resolution file, as well as flags for waterbody 
#' assignment and a dataframe of intersections
#' 
#' 
add_NHD_waterbody_to_sites <- function(sites_with_huc, huc4, GEE_buffer, huc8_wbd) {
  
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
      filter(harmonized_site_type %in% c("Lake/Reservoir", "Estuary", "Other"))
    
    # check to make sure there are obs when filtered for lake/reservoir/other, otherwise
    # return null from function
    if (nrow(huc4_lake_points) == 0) { return( NULL ) }
    
    # if huc4 < 1900 (conus points), we can use nhdplustools, otherwise we have to 
    # download from the national map.
    if (huc4 < 1900) {
      
      # getting the huc04 AOI can fail along boundaries of the US/Canada & US/Mexico
      # so here, if the huc4 call doesn't work, we'll use the wbd sf object used
      # to define the HUC8's to begin with.
      # get the aoi of the huc for grabbing waterbodies
      huc4_aoi <- get_huc(id = huc4, type = "huc04")
      
      if (is.null(huc4_aoi)) {
        if (st_crs(huc8_wbd) != st_crs(huc4_lake_points)) {
          huc4_lake_points <- st_transform(huc4_lake_points, st_crs(huc8_wbd))
        }
        # filter huc8 by huc4 digits
        huc4_aoi <- huc8_wbd %>% 
          filter(grepl(huc4, huc8))
        # and then make sure that there are no huc8's that we included that we
        # don't care about
        huc4_aoi <- huc4_aoi[huc4_lake_points, ] %>% 
          st_bbox() %>% 
          st_as_sfc()
      }
      
      # get the waterbodies in the huc
      huc4_wbd <- get_waterbodies(AOI = huc4_aoi) %>%
        # filter to match wbd type of lakeSR
        filter(ftype %in% c("Reservoir", "LakePond", "Estuary")) %>%
        select(wb_nhd_id = comid, 
               wb_gnis_id = gnis_id, 
               wb_gnis_name = gnis_name, 
               wb_fcode = fcode, 
               wb_areasqkm = areasqkm) %>%
        # add column to merge after st_intersects()
        rowid_to_column("wbd_id") %>% 
        mutate(wb_nhd_source = "NHDPlusv2",
               wb_nhd_id = as.character(wb_nhd_id))
      
    } else {
      
      # if huc4 >= 1900, process differently, as nhdtools wbd is limited to CONUS
      
      # make sure the geopackage hasn't already been downloaded
      if (!file.exists(file.path("a_compile_sites/nhd/",
                                 paste0("NHD_H_", huc4, "_HU4_GPKG.gpkg")))) {
        
        # but if it isn't, download it!
        
        # set timeout so that... this doesn't timeout
        options(timeout = 60000)
        
        # url for the NHD Best Resolution for HUC4
        url = paste0("https://prd-tnm.s3.amazonaws.com/StagedProducts/Hydrography/NHD/HU4/GPKG/NHD_H_", huc4, "_HU4_GPKG.zip")
        download.file(url, destfile = file.path("a_compile_sites/nhd/", 
                                                paste0(huc4, ".zip")))
        
        unzip(file.path("a_compile_sites/nhd/", 
                        paste0(huc4, ".zip")), 
              exdir = "a_compile_sites/nhd/")
        
        # remove zip
        unlink(file.path("a_compile_sites/nhd/", 
                         paste0(huc4, ".zip")))
      }
      
      # open the NHDWaterbody layer, coerce to a {sf} object
      huc4_wbd <- st_read(file.path("a_compile_sites/nhd/",
                                    paste0("NHD_H_", huc4, "_HU4_GPKG.gpkg")),
                          layer = "NHDWaterbody") %>% 
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
    }
    
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
    
    # NHD Best res is often in other crs (NAD83), so the points need to be converted if 
    # the polygons are.
    
    if (st_crs(huc4_wbd) != st_crs(huc4_lake_points)) {
      huc4_lake_points <- huc4_lake_points %>% 
        st_transform(crs = st_crs(huc4_wbd))
    }
    
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
      
      # get coordinates to calculate UTM zone. This is an adaptation of code from
      # Xiao Yang's code in EE - Yang, Xiao. (2020). Deepest point calculation 
      # for any given polygon using Google Earth Engine JavaScript API 
      # (Version v1). Zenodo. https://doi.org/10.5281/zenodo.4136755
      # we're going to make the assumption that all points in the HUC4 are in the
      # same UTM zone
      coord_for_UTM <- matched %>% st_coordinates()
      mean_x <- mean(coord_for_UTM[, 1])
      mean_y <- mean(coord_for_UTM[, 2])
      # calculate the UTM zone using the mean value of Longitude for the sites
      utm_suffix <- as.character(ceiling((mean_x + 180) / 6))
      utm_code <- if_else(mean_y >= 0,
                          # EPSG prefix for N hemisphere
                          paste0('EPSG:326', utm_suffix),
                          # for S hemisphere
                          paste0('EPSG:327', utm_suffix))
      # transform points and waterbodies to UTM
      transformed_waterbodies <- st_transform(huc4_wbd, 
                                              crs = utm_code)
      transformed_points <- st_transform(matched,
                                         crs = utm_code)
      
      
      # cast the waterbodies into a linestrings to measure distance
      waterbody_boundary <- st_cast(st_geometry(transformed_waterbodies), "MULTILINESTRING") %>% 
        # dissolve these into a single geometry, since the identity of the line doesn't
        # matter
        st_union()
      
      # measure the distance, rounded to integer, set as numeric (otherwise comes back as a matrix)
      matched$dist_to_shore <- as.numeric(round(st_distance(transformed_points, waterbody_boundary)))
      
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
      filter(!siteSR_id %in% matched_siteSR_id) %>%
      mutate(wbd_id = st_nearest_feature(., huc4_wbd)) %>%
      left_join(., huc4_wbd %>% st_drop_geometry()) %>%
      arrange(wbd_id)
    
    huc4_unmatched <- unmatched %>%
      select(siteSR_id, wbd_id) %>%
      st_drop_geometry() %>%
      right_join(huc4_wbd, .) %>%
      arrange(wbd_id)
    
    unmatched <- unmatched %>%
      mutate(dist_to_wb = as.numeric(round(st_distance(unmatched, huc4_unmatched, by_element = TRUE)))) %>% 
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

