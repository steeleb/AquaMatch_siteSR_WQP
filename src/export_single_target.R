#' @title Export a single target to Google Drive
#' 
#' @description
#' A function to export a single target (as a file) to Google Drive and return
#' the shareable Drive link as a file path.
#' 
#' @param target The name of the target to be exported (as an object not a string).
#' 
#' @param drive_path A path to the folder on Google Drive where the file
#' should be saved.
#' 
#' @param stable Logical value. If TRUE, also export the file to the "stable"
#' subfolder in Google Drive. If FALSE, use the path as provided by the user.
#' 
#' @param google_email A string containing the gmail address to use for
#' Google Drive authentication.
#' 
#' @param file_type Indication of destination file type. Acceptable types include
#' csv, feather, rds. Defaults to rds.
#' 
#' @param date_stamp character string to version target by
#' 
#' @returns
#' None. 
#' 
export_single_target <- function(target, drive_path, stable = FALSE, google_email,
                                 date_stamp, file_type = "rds"){
  
  if (!file_type %in% c("feather", "rds", "csv")) {
    stop("File type unrecognized. Acceptable arguments for `file_type` include feather, rds, csv.")
  }
  
  # get file extension
  if (file_type == "feather") {
    extension <- ".feather"
    write_function <- write_feather
  } 
  if (file_type == "rds") {
    extension <- ".rds"
    write_function <- write_rds
  }
  if (file_type == "csv") {
    extension <- ".csv"
    write_function <-  write_csv
  }
  
  # Authorize using the google email provided
  drive_auth(google_email)
  
  # Get target name as a string
  target_string <- deparse(substitute(target))
  
  # Create a temporary file exported locally, which can then be used to upload
  # to Google Drive
  file_local_path <- tempfile(fileext = extension)
  
  # save file using the write funciton
  # do not specify argument for file path, it is diff between readr and arrow
  write_function(x = target,
                 file_local_path) 
  
  if (!is.null(date_stamp)) {
    target_string <- paste0(target_string, "_v", date_stamp)
  }
  
  # Once locally exported, send to Google Drive
  out_file <- drive_put(media = file_local_path,
                        # The folder on Google Drive
                        path = drive_path,
                        # The filename on Google Drive
                        name = paste0(target_string,
                                      extension))
  
  # Make the Google Drive link shareable: anyone can view
  drive_share_anyone(out_file)
  
  # If stable == TRUE then export a second, dated file to the stable/ subfolder
  if(stable){
    
    drive_path_stable <- paste0(drive_path, "stable/")
    
    # Once locally exported, send to Google Drive
    out_file_stable <- drive_upload(media = file_local_path,
                                    # The folder on Google Drive
                                    path = drive_path_stable,
                                    # The filename on Google Drive
                                    name = paste0(target_string,
                                                  "_",
                                                  gsub(pattern = "-",
                                                       replacement = "",
                                                       x = date_stamp),
                                                  extension),
                                    # Error if file exists with same date
                                    # Note that we don't do this before this
                                    # instance because files will always have the
                                    # same name: no dates attached unless "stable"
                                    overwrite = FALSE)
    
    # Make the Google Drive link shareable: anyone can view
    drive_share_anyone(out_file_stable)
  }
  
  # Now remove the local file after upload is complete
  file.remove(file_local_path)
  
}