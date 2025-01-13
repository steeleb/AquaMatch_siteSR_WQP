#' @title Add NHD waterbody identifier to sites
#' 
#' @description
#' Using nhdPlusTools::get_waterbody() or NHD Best Resolution shapefile for 
#' non-CONUS HUC4's, assign a NHD identifier to each lake/reservoir site to 
#' associate them with a specific waterbody
#' 
#' @param sites_with_huc simple feature object of sites to pair with waterbodies
#' @param huc4 4-digit character string to filter sites by
#' 
#' @returns a simple feature object of sites with additional fields from 
#' NHDPlusV2 or NHD Best Resolution file, as well as flags for waterbody 
#' assignment
#' 
#' 
add_NHD_waterbody_to_sites <- function(sites_with_huc, huc4) {
  
  message(paste0("Assigning NHD waterbodies to sites within ", huc4))
  
  tryCatch({
    # filter sites for those in a single huc
    sf_subset <- sites_with_huc %>%
      filter(str_sub(HUCEightDigitCode, 1, 4) == huc4) %>% 
      rowid_to_column()
    
    # if huc4 < 1900 (conus points), we can use nhdplustools, otherwise we have to 
    # download from the national map.
    
    if (huc4 < 1900) {
      
      # get the aoi of the huc for grabbing waterbodies
      huc4_aoi <- get_huc(id = huc4, type = "huc04")
      
      # get the waterbodies in the huc
      huc4_wbd <- get_waterbodies(AOI = huc4_aoi) %>%
        # filter to match wbd type of lakeSR
        filter(ftype %in% c("Reservoir", "LakePond")) %>%
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
      if (!file.exists(file.path("4_compile_sites/nhd/",
                                 paste0("NHD_H_", huc4, "_HU4_GPKG.gpkg")))) {
        
        # but if it doesn't, download it!
        
        # set timeout so that... this doesn't timeout
        options(timeout = 60000)
        
        # url for the NHD Best Resolution for HUC4
        url = paste0("https://prd-tnm.s3.amazonaws.com/StagedProducts/Hydrography/NHD/HU4/GPKG/NHD_H_", huc4, "_HU4_GPKG.zip")
        download.file(url, destfile = file.path("4_compile_sites/nhd/", 
                                                paste0(huc4, ".zip")))
        
        unzip(file.path("4_compile_sites/nhd/", 
                        paste0(huc4, ".zip")), 
              exdir = "4_compile_sites/nhd/")
        
        # remove zip
        unlink(file.path("4_compile_sites/nhd/", 
                         paste0(huc4, ".zip")))
      }
      
      # open the NHDWaterbody layer, coerce to a {sf} object
      huc4_wbd <- st_read(file.path("4_compile_sites/nhd/",
                                    paste0("NHD_H_", huc4, "_HU4_GPKG.gpkg")),
                          layer = "NHDWaterbody") %>% 
        # filter the waterbodies for ftypes of interest. 390 = lake/pond; 436 = res
        filter(ftype %in% c(390, 436)) %>% 
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
    
    if (st_crs(huc4_wbd) != st_crs(sf_subset)) {
      sf_subset <- sf_subset %>% 
        st_transform(crs = st_crs(huc4_wbd))
    }
    
    # split the sites by Monitoring Location Type - for this, we'll just
    # pair lake/reservoir. river sites are paired in add_NHD_flowline_to_sites()
    huc4_lake_points <- sf_subset %>%
      filter(grepl("lake|reservoir", MonitoringLocationTypeName, ignore.case = T))
    
    # Assign waterbodies to Lake points -------------------------------------
    
    # check to see if there are any points overlapping, if so, run matching
    # process. otherwise, return NULL
    
    if (nrow(huc4_lake_points) > 0) {
      
      # grab the waterbody rowid for the points - without a buffer. While
      # there are more steps to this workflow, it's exceptionally faster
      # than st_intersection().
      huc4_wbd_intersect <- st_intersects(huc4_lake_points, huc4_wbd)
      
      # get lake points (just ids) to map by
      to_match <- huc4_lake_points %>%
        st_drop_geometry(.) %>%
        rowid_to_column("loc_id") %>%
        select(loc_id, rowid)
      
      matched <- map2(.x = to_match$rowid,
                      .y = to_match$loc_id,
                      .z = huc4_wbd_intersect,
                      .f = \(.x, .y, .z) {
                        tibble(rowid = .x,
                               wbd_id = .z[[.y]])
                      }) %>%
        bind_rows() %>%
        left_join(., huc4_wbd %>% st_drop_geometry()) %>%
        select(-wbd_id) %>%
        left_join(huc4_lake_points, .) %>%
        filter(!is.na(wb_nhd_id)) %>%
        # add distance to waterbody for rbind later
        mutate(dist_to_wb = NA)
      
      # get any unmatched Lake points. Here, we will just grab the closest
      # waterbody and the distance to that waterbody. For each of them,
      # arrange by wbd_id for proper st_distance measure.
      unmatched <- huc4_lake_points %>%
        filter(!rowid %in% matched$rowid) %>%
        mutate(wbd_id = st_nearest_feature(., huc4_wbd)) %>%
        left_join(., huc4_wbd %>% st_drop_geometry()) %>%
        arrange(wbd_id)
      
      huc4_unmatched <- unmatched %>%
        select(rowid, wbd_id) %>%
        st_drop_geometry() %>%
        right_join(huc4_wbd, .) %>%
        arrange(wbd_id)
      
      unmatched <- unmatched %>%
        mutate(dist_to_wb = st_distance(unmatched, huc4_unmatched, by_element = TRUE)) %>%
        mutate(dist_to_wb = as.numeric(dist_to_wb)) %>%
        # if the distance to the waterbody is > 500m, recode all the waterbody info
        mutate(across(all_of(c("wb_nhd_id", "wb_gnis_id", "wb_gnis_name", "wb_areasqkm")),
                      ~ if_else(dist_to_wb > 500,
                                NA,
                                .))) %>%
        select(-wbd_id)
      
      #join the matched and unmatched together, flag wbd assignment
      assignment <- rbind(matched, unmatched) %>%
        # 0 = point inside waterbody (nhd_id info, but no distance)
        # 1 = point <= 500m proximate to waterbody, waterbody info is from
        # closest waterbody. (nhd_id info and distance info)
        # 2 = point unable to be assigned to waterbody (no nhd_id, but
        # distance info)
        mutate(flag_wb = case_when(!is.na(wb_nhd_id) & is.na(dist_to_wb) ~ 0,
                                   !is.na(wb_nhd_id) & !is.na(dist_to_wb) ~ 1,
                                   is.na(wb_nhd_id) & !is.na(dist_to_wb) ~ 2))
      
      # return unique site info, huc code, and all the waterbody info
      assignment %>% 
        st_drop_geometry() %>% 
        select(MonitoringLocationIdentifier, HUCEightDigitCode,
               all_of(starts_with("wb_")), dist_to_wb, flag_wb)
      
    } else {
      
      # if there are no lake/res points in the HUC4, return NULL
      NULL
      
    }
    
  },
  
  # add error handling and note the huc4 if this fails
  
  error = function(e) {
    # if subset failed, note and go to next 
    message(paste0("HUC4 ", huc4, " was not able to be processed, 
                     noting in '4_compile_sites/mid/huc4_wbd_no_process.txt'"))
    if (!file.exists("4_compile_sites/mid/huc4_wbd_no_process.txt")) {
      write_lines(huc4, file = "4_compile_sites/mid/huc4_wbd_no_process.txt")
      return(NULL)
    } else {
      text <- read_lines("4_compile_sites/mid/huc4_wbd_no_process.txt")
      new_text <- c(text, huc4)
      write_lines(new_text, "4_compile_sites/mid/huc4_wbd_no_process.txt")
      return(NULL)
    }
  })
  
}

