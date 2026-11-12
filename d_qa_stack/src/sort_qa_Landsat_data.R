#' @title Sort/collate QA'd Landsat data for data sharing
#' 
#' @description
#' This function sorts large Landsat mission data sets (LS 5-8) into .csv data sets by
#' HUC2 and smaller Landsat mission data sets (LS4/9) into a single .csv file per
#' mission for data publication. All columns in the QA'd files are retained, 
#' including the `pCount_*` mask diagnostic columns (e.g. `pCount_high_aero`, 
#' `pCount_unreal_val`, `pCount_*_thresh`), which are sparsely populated by design.
#' The exception is `pCount_ir_glint`, which is dropped (it is 0 in every record; 
#' see the per-band `pCount_*_ir_glint` columns).
#' 
#' The QA'd data are keyed to the site that was sent to EE (the extraction site). 
#' Here the data are back-joined to every RS-visible site in the extraction site's 
#' group using `crosswalk`, so each visible `siteSR_id` has its own rows. The 
#' extraction site is retained in `extraction_siteSR_id`, and 
#' `flag_grouped_extraction` is 1 when more than one site was in the group 
#' (0 otherwise). Site-level descriptors (huc2, grouping details, extraction site 
#' flags) are in the site information file, not in these data.
#' 
#' @param qa_files vector of file paths to the qa'd Landsat data files 
#' to be processed. Assumed to be arrow::feather() files. 
#' @param gee_identifier date string formatted yyyy-mm-dd used to version the 
#' qa process. This is set in the general configuration yaml under `pekel_gee_version`
#' @param mission_info data.frame/tibble/data.table containing the columns 'mission_id'
#' (e.g. 'LT05') and 'mission_names' (e.g. 'Landsat 5'). 
#' @param site_info targets object containing the siteSR site info with NHD info
#' @param crosswalk targets object `d_crosswalk`, containing the columns 
#' `siteSR_id`, `extraction_siteSR_id`, and `n_sites_in_cluster`
#' @param dswe character string indicating the DSWE setting to filter the files
#' by.
#' @param HUC2 character string indicating the HUC2 the data belong to
#' 
#' @returns file path name where output file is stored. Silently saves a .csv file
#' of the data in the folder path `d_qa_stack/export`.
#' 
sort_qa_Landsat_data <- function(qa_files,
                                 gee_identifier,
                                 mission_info, 
                                 site_info,
                                 crosswalk,
                                 dswe, 
                                 HUC2 = NULL) {
  
  # filter files for those in arguments
  fps <- qa_files %>% 
    .[grepl(mission_info$mission_id, .)] %>% 
    .[grepl(paste0(gee_identifier, "_filtered"), .)] %>% 
    .[grepl(paste0("_", dswe, "_"), .)]
  
  # quick reality check
  if (length(fps) > 0) {
    # grab siteSR id and assigned huc for site joins
    site_info_lite <- site_info %>% select(siteSR_id, assigned_HUC) %>% 
      setDT()
    # crosswalk of extraction site to all visible sites in its group
    crosswalk_lite <- crosswalk %>% 
      transmute(siteSR_id,
                extraction_siteSR_id,
                flag_grouped_extraction = as.integer(n_sites_in_cluster > 1)) %>% 
      setDT()
    
    # back-join the data (keyed by extraction site) to all sites in the group
    backjoin <- function(dt) {
      n_extraction_sites <- uniqueN(dt$siteSR_id)
      setnames(dt, "siteSR_id", "extraction_siteSR_id")
      dt <- merge(dt, crosswalk_lite, by = "extraction_siteSR_id", 
                  allow.cartesian = TRUE)
      if (uniqueN(dt$extraction_siteSR_id) < n_extraction_sites) {
        warning("Some extraction sites were not found in the crosswalk and were dropped.")
      }
      dt
    }
    
    # leading columns of the output
    lead_cols <- c("siteSR_id", "flag_grouped_extraction", "extraction_siteSR_id",
                   "dswe_filter", "mission", "sat_id", "date")
    
    if (!is.null(HUC2)) {
      
      # get and process data, filter by HUC2
      data <- map(fps, 
                  \(fp) {
                    dt <- read_feather(fp) 
                    # convert to DT by reference
                    setDT(dt)
                    # drop pCount_ir_glint: it requires Nir, Swir1, and Swir2 to all be
                    # >= 0.1, so it is 0 in every record. The per-band *_ir_glint 
                    # columns are retained.
                    if ("pCount_ir_glint" %in% names(dt)) dt[, pCount_ir_glint := NULL]
                    # back-join to all visible sites
                    dt <- backjoin(dt)
                    # join with site info, huc2 is only used to split the files
                    dt <- merge(dt, site_info_lite, by = "siteSR_id", all.x = TRUE)
                    dt[, huc2 := str_sub(assigned_HUC, 1, 2)]
                    # filter for desired huc2
                    if (is.na(HUC2)) {
                      dt[is.na(huc2)]
                    } else {
                      dt[huc2 == HUC2]
                    }
                  }) %>% 
        rbindlist() 
      
      # drop huc info (in the site information file), and pull id columns to the front
      data[, c("assigned_HUC", "huc2") := NULL]
      setcolorder(data, c(lead_cols, setdiff(names(data), lead_cols)))
      
      if (!is.na(HUC2)) {
        #make a file path name
        save_to_fpn <- file.path("d_qa_stack/export/",
                                 paste0("siteSR_HUC2_",
                                        HUC2,
                                        "_", 
                                        str_replace(mission_info$mission_names, " ", ""),
                                        "_", 
                                        dswe,
                                        "_v",
                                        gee_identifier, 
                                        ".csv"))
      } else {
        #make a file path name
        save_to_fpn <- file.path("d_qa_stack/export/",
                                 paste0("siteSR_noHUC2_",
                                        str_replace(mission_info$mission_names, " ", ""),
                                        "_", 
                                        dswe,
                                        "_v",
                                        gee_identifier, 
                                        ".csv"))
        
      }
      
      # write that csv file in the out folder
      fwrite(data, save_to_fpn)
      
      return(save_to_fpn)
      
    } else {
      
      # get and process data
      data <- map(fps, 
                  \(fp) {
                    dt <- read_feather(fp) 
                    # convert to DT by reference
                    setDT(dt)
                    # drop pCount_ir_glint: it requires Nir, Swir1, and Swir2 to all be
                    # >= 0.1, so it is 0 in every record. The per-band *_ir_glint 
                    # columns are retained.
                    if ("pCount_ir_glint" %in% names(dt)) dt[, pCount_ir_glint := NULL]
                    dt
                  }) %>% 
        rbindlist()
      
      # back-join to all visible sites
      data <- backjoin(data)
      
      # and now pull id columns to the front
      setcolorder(data, c(lead_cols, setdiff(names(data), lead_cols)))
      
      #make a file path name
      save_to_fpn <- file.path("d_qa_stack/export/",
                               paste0("siteSR_",
                                      str_replace(mission_info$mission_names, " ", ""),
                                      "_", 
                                      dswe,
                                      "_v",
                                      gee_identifier, 
                                      ".csv"))
      
      # write that csv file in the out folder
      fwrite(data, save_to_fpn)
      
      return(save_to_fpn)
    } 
    
  }
  
}