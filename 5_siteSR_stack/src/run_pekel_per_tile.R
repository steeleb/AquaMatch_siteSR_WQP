#' @title Run Pekel water occurence script per tile
#' 
#' @description
#' Function to run the Pekel water ocurrence script for a specified WRS2 tile.
#' 
#' @param WRS_tile tile to run the GEE pull on
#' @returns Silently writes a text file of the current tile (for use in the
#' Python script). Silently triggers GEE to start Pekel acquisition per tile.
#' 
#' 
run_pekel_per_tile <- function(WRS_tile) {
  write_lines(WRS_tile, "5_siteSR_stack/run/current_tile.txt", sep = "")
  source_python("5_siteSR_stack/py/runPekelPerTile.py")
}