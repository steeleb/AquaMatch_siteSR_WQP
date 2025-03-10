#' @title Prep QA'd data for export
#' 
#' @description
#' This function adds additional metadata columns and optionally stores the file
#' in a version other than .feather. 
#'
#' @param file file path to feather file to be updated and prepared for export.
#' File name must include `_DSWE1_`, `_DSWE1a_` or `_DSWE3_`.
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
  
  if (!grepl("_DSWE1_|_DSWE1a_|_DSWE3_", file)) {
    stop("DSWE type not recognized from file name, this function does not operate
         without a valid DSWE type in the file name.")
  }
  
  data <- read_feather(file)
  # use set to silence warnings and increase efficiency
  setDT(data)
  # use data.table functions here (specifically for LS7, which is huge)
  # use stringi for better performance on large datasets
  data[, `:=`(
    siteSR_id = stri_extract_last_regex(`system:index`, "[^_]+"), 
    dswe_filter = stri_extract_first_regex(file, "DSWE\\d+a?"),
    mission = stri_extract_first_regex(`system:index`, "L[A-Z]0\\d"), 
    sat_id = stri_replace_last_regex(`system:index`, "_[^_]+$", ""),
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
  
  full_file_path
  
}
