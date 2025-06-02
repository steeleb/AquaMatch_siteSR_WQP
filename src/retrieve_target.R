#' @title Retrieve a target from Google Drive
#' 
#' @description
#' A function to retrieve a target from Google Drive after it has been uploaded
#' in a previous step.
#' 
#' @param target A string containing the name of the target to be retrieved.
#' 
#' @param id_df A dataframe containing the cols `name` and `id` to use for
#' retrieving the uploaded dataset from Google Drive.
#' 
#' @param local_folder A string specifying the folder where the file should be
#' downloaded to.
#' 
#' @param google_email A string containing the gmail address to use for
#' Google Drive authentication.
#' 
#' @param file_type A string giving the file extension to be used. ("rds", "csv", or 
#' "feather")
#' 
#' @param date_stamp A string containing an eight-digit date (i.e., in
#' ISO 8601 "basic" format: YYYYMMDD) that should be used to identify the
#' correct file version on Google Drive.
#' 
#' @returns 
#' The dataset after being downloaded and read into the pipeline from Google Drive.
#' 
retrieve_target <- function(target, id_df, local_folder, 
                          google_email, file_type = "rds", 
                          date_stamp = NULL){
  
  if (!file_type %in% c("feather", "rds", "csv")) {
    stop("File type unrecognized. Acceptable arguments for `file_type` include feather, rds, csv.")
  }
  
  extension <- paste0(".", file_type)
  
  # Authorize using the google email provided
  drive_auth(google_email)
  
  # Local file download location
  local_path <- file.path(local_folder, paste0(target, extension))
  
  if(!is.null(date_stamp)){
    
    file_name <- paste0(target, "_v", date_stamp, extension)
    
  } else {
    
    file_name <- paste0(target, extension)
    
  }
  
  # Filter the contents to the file requested and obtain its ID
  drive_file_id <- id_df %>%
    filter(name == file_name) %>%
    pull(id) %>%
    as_id(.)
  
  # Run the download
  drive_download(file = drive_file_id,
                 path = local_path,
                 overwrite = TRUE)
  
  # store read function and then read file
  if (file_type == "rds") {
    read_function <- read_rds
  }
  if (file_type == "feather") {
    read_function <- read_feather
  }
  if (file_type == "csv") {
    read_function <- read_csv
  }
  
  return(read_function(local_path))

  unlink(local_path)
  
}
