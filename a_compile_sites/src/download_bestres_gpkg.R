#' @title Download the NHD Best Resolution GeoPackage for a HUC4
#'
#' @description
#' Download and unzip the NHD Best Resolution HU4 GeoPackage from The National
#' Map if it is not already present locally. The file is checked against the
#' ETag recorded in the manifest so that the source data are consistent with
#' the manifest.
#'
#' @param huc4 4-digit character string of the HUC4
#' @param HUC4_manifest tibble from `get_bestres_manifest()` with huc4, url, and 
#' etag columns
#' @param dl_dir directory to store downloaded files
#'
#' @returns path to the GeoPackage
#'
#'
download_bestres_gpkg <- function(huc4, 
                                  HUC4_manifest, 
                                  dl_dir = "a_compile_sites/nhd/") {
  
  gpkg_name <- paste0("NHD_H_", huc4, "_HU4_GPKG.gpkg")
  gpkg_path <- file.path(dl_dir, gpkg_name)
  
  if (!file.exists(gpkg_path)) {
    
    manifest_row <- HUC4_manifest[HUC4_manifest$huc4 == huc4, ]
    if (nrow(manifest_row) != 1) {
      stop(paste0("HUC4 ", huc4, " is not in the NHD Best Resolution manifest."))
    }
    
    # make sure the file on The National Map is the same version recorded in the
    # manifest
    header <- curl::curl_fetch_memory(manifest_row$url,
                                      handle = curl::new_handle(nobody = TRUE))
    current_etag <- str_remove_all(curl::parse_headers_list(header$headers)$etag, '"')
    if (!identical(current_etag, manifest_row$etag)) {
      stop(paste0("The NHD GeoPackage for HUC4 ", huc4, " has changed since the ",
                  "manifest was created. Run `tar_invalidate(a_HUC4_manifest)` to ",
                  "use the updated files."))
    }
    
    # set timeout so that... this doesn't timeout
    options(timeout = 60000)
    # download and unzip in a HUC4-specific folder, removed upon exit, then 
    # move the GeoPackage into place so that an interrupted run never leaves a 
    # partial file at `gpkg_path`
    huc_dir <- file.path(dl_dir, paste0("tmp_", huc4))
    dir.create(huc_dir, showWarnings = FALSE)
    on.exit(unlink(huc_dir, recursive = TRUE))
    zip_file <- file.path(huc_dir, paste0(huc4, ".zip"))
    download.file(manifest_row$url, destfile = zip_file, quiet = TRUE)
    unzip(zip_file, files = gpkg_name, exdir = huc_dir)
    file.rename(file.path(huc_dir, gpkg_name), gpkg_path)
  }
  
  gpkg_path
}
