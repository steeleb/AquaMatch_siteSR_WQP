#' @title Download csv files from specified Drive folder
#' 
#' @description
#' description Function to download all csv files from a specific drive folder 
#' to the untracked 5_siteSR_stack/down/ folder
#'
#' @param drive_folder_name text string; name of folder in Drive, must be unique
#' @param google_email text string; google email address for Drive authentication
#' @param version_identifier user-specified string to identify the RS pull these
#' data are associated with
#' @param download_type text string; either "stack" or "pekel"
#' 
#' @returns downloads all .csvs from the specified folder name to the
#' 5_siteSR_stack/down/ folder
#' 
#' 
download_csvs_from_drive <- function(drive_folder_name, 
                                     google_email, 
                                     version_identifier,
                                     download_type) {
  drive_auth(email = google_email)
  dribble_files <- drive_ls(path = drive_folder_name)
  dribble_files <- dribble_files %>% 
    filter(grepl(".csv", name))
  # filter files for download types
  if (download_type == "stack") {
    dribble_files <- dribble_files[grepl(version_identifier, dribble_files$name), ]
  } else {
    if (download_type == "pekel") {
      dribble_files <- dribble_files[grepl("pekel", dribble_files$name, ignore.case = T), ]
    } else {
      print("Download type not recognized, make sure it is either 'stack' or 'pekel'.")
      stop()
    }
  }
  # check for version_identifier subfolder and download_type subfolder
  if (!dir.exists(file.path("5_siteSR_stack/down/",
                            version_identifier,
                            download_type))) {
    dir.create(file.path("5_siteSR_stack/down/",
                         version_identifier,
                         download_type),
               recursive = TRUE)
  }
  walk2(.x = dribble_files$id,
        .y = dribble_files$name, 
        .f = function(.x, .y) {
          try(drive_download(file = .x,
                             path = file.path("5_siteSR_stack/down/",
                                              version_identifier,
                                              download_type,
                                              .y),
                             overwrite = TRUE)) 
        })
}
