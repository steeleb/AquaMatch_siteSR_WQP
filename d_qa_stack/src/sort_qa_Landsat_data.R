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
#' @param qa_files vector of file paths to the qa'd Landsat data files 
#' to be processed. Assumed to be arrow::feather() files. 
#' @param gee_identifier date string formatted yyyy-mm-dd used to version the 
#' qa process. This is set in the general configuration yaml under `pekel_gee_version`
#' @param mission_info data.frame/tibble/data.table containing the columns 'mission_id'
#' (e.g. 'LT05') and 'mission_names' (e.g. 'Landsat 5'). 
#' @param site_info targets object containing the siteSR site info with NHD info
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
                    # join with site info
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
      
      # and now pull those new columns to the front
      new_cols <- c("siteSR_id", "dswe_filter", "mission", "sat_id", "date", "huc2")
      setcolorder(data, c(new_cols, setdiff(names(data), new_cols)))
      # drop assigned_HUC from site info file
      data[, assigned_HUC := NULL]
      
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
      
      # add huc info
      data <- merge(data, site_info_lite, by = "siteSR_id", all.x = TRUE)
      
      # get HUC2, drop assigned huc
      data[, huc2 := str_sub(assigned_HUC, 1, 2)]
      data[, assigned_HUC := NULL]
      
      # and now pull those new columns to the front
      setcolorder(data, c("siteSR_id", "dswe_filter", "mission", "sat_id", "date", "huc2"))
      
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