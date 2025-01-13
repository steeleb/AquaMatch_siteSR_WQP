#' @title Run GEE script per pathrow
#' 
#' @description
#' Function to run the Landsat Pull for a specified WRS2 pathrow.
#' 
#' @param WRS_pathrow pathrow to run the GEE pull on
#' @returns Silently writes a text file of the current pathrow (for use in the
#' Python script). Silently triggers GEE to start stack acquisition per pathrow.
#' 
#' 
run_GEE_per_pathrow <- function(WRS_pathrow) {
  write_lines(WRS_pathrow, "5_siteSR_stack/run/current_pathrow.txt", sep = "")
  source_python("5_siteSR_stack/py/run_GEE_per_pathrow.py")
}