#' @title Prep QA'd data for export
#' 
#' @description
#' This function adds additional metadata columns and optionally stores the file
#' in a version other than .feather. 
#'
#' @param file file path to feather file to be updated and prepared for export.
#' File name must include `_DSWE1_`, `_DSWE1a_`, `_DSWE3_`, or `metadata`.
#' @param file_type output file type (either "csv" or "feather")
#' @param out_path Directory where updated files should be saved. 
#' 
#' @returns full relative file path of saved file.
#' 
prep_Landsat_for_export <- function(file, file_type, out_path) {
  
  # make sure file type is accepted
  if (!file_type %in% c("csv", "feather")) {
    stop("file_type argument unrecognized, only 'csv' and 'feather' are acceptable")
  }
  
  if (!grepl("_DSWE1_|_DSWE1a_|_DSWE3_|metadata", file)) {
    stop("File type not recognized from file name, this function does not operate
         without a valid DSWE type or `metadata` in the file name.")
  }
  
  data <- read_feather(file)
  # use set to silence warnings and increase efficiency
  setDT(data)
  
  # if point data, add some columns for use
  if (!grepl('metadata', file)) {
    # use data.table functions here (specifically for LS7, which is huge)
    # use stringi for better performance on large datasets
    data[, `:=`(
      siteSR_id = stri_extract_last_regex(`system:index`, "[^_]+"), 
      dswe_filter = stri_extract_first_regex(file, "DSWE\\d+a?"),
      mission = stri_extract_first_regex(`system:index`, "L[A-Z]0\\d"), 
      date = as.IDate(stri_extract_first_regex(`system:index`, "\\d{8}"), format = "%Y%m%d") 
    )]
    
    # and now pull those new columns to the front
    new_cols <- c("siteSR_id", "dswe_filter", "mission", "sat_id", "date")
    setcolorder(data, c(new_cols, setdiff(names(data), new_cols)))
    
    # get the basename of the file, without the extension
    out_file_base <- file_path_sans_ext(basename(file)) 
    
    if (file_type == "csv") {
      full_file_path <- file.path(out_path,
                                  paste0(str_replace(out_file_base, "filtered", "export"), ".csv"))
      write_csv(data,
                full_file_path)
    }
    if (file_type == "feather") {
      full_file_path <- file.path(out_path,
                                  paste0(str_replace(out_file_base, "filtered", "export"), ".feather"))
      write_feather(data,
                    full_file_path,
                    compression = "lz4")
    }

  } else {
     
    setnames(data, "system:index", "sat_id")
    
    # filter out images with poor Image Quality (we do this for all sites)
    # make the name for image quality, since it changes through mission groups
    image_qual_name <- if (grepl("LS457", file)) {
      "IMAGE_QUALITY"
    } else {
      "IMAGE_QUALITY_OLI"
    }
    data[image_qual_name >= 8]
    
    # we'll export a handful of columns of the metadata that may be useful in 
    # diagnostics/modeling
    
    column_names <- names(data)
    
    pull_cols <- c("sat_id", "ALGORITHM_SOURCE_SURFACE_REFLECTANCE",
                   "ALGORITHM_SOURCE_SURFACE_TEMPERATURE", "CLOUD_COVER",
                   "CLOUD_COVER_LAND", "DATA_SOURCE_REANALYSIS", "DATE_ACQUIRED",
                   "EARTH_SUN_DISTANCE", 
                   column_names[startsWith(column_names, "GEOMETRIC_RMSE")],
                   column_names[startsWith(column_names, "GROUND_CONTROL")],
                   "PROCESSING_SOFTWARE_VERSION", "NADIROFFNADIR", 
                   "IMAGE_QUALITY", "IMAGE_QUALITY_OLI", "IMAGE_QUALITY_TIRS",
                   "UTM", "WRS_ROW", "WRS_PATH", "SUN_AZIMUTH", "SUN_ELEVATION")

    # Filter drop_cols to include only existing columns for transfer between data groups
    pull_cols <- pull_cols[pull_cols %in% names(data)]
    
    # select desired columns
    data <- data %>% select(all_of(pull_cols))
    
    # get the basename of the file, without the extension
    fn <- basename(file)
    
    if (file_type == "csv") {
      full_file_path <- file.path(out_path,
                                  paste0(str_replace(fn, ".feather", "_export.csv")))
      write_csv(data,
                full_file_path)
    }
    if (file_type == "feather") {
      full_file_path <- file.path(out_path,
                                  paste0(str_replace(fn, ".feather", "_export.feather")))
      write_feather(data,
                    full_file_path,
                    compression = "lz4")
    }
    
  }
  
  full_file_path
  
}
