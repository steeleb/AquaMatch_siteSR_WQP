#' @title Move a GEE export folder into the project folder on Google Drive
#' 
#' @description
#' Earth Engine Drive exports take a folder *name* (not a path), so the export
#' folder is always created at the root of My Drive. This function finds that
#' root-level folder and moves it into the project's parent folder, so
#' downstream `drive_ls()` calls that expect
#' `<parent_folder>/<folder_name>/` work as intended. If the folder is already
#' in the parent folder, nothing is moved. If a copy exists in both places,
#' the files from the root-level folder are moved into the one in the parent
#' folder and the empty root-level folder is sent to the trash.
#' 
#' @param folder_name string; name of the GEE export folder (e.g., 
#' "pekel_v2026-11-10")
#' 
#' @param parent_folder string; Drive path of the folder the export folder
#' should live in. Must start with "~/" and end with "/".
#' 
#' @param google_email A string containing the gmail address to use for
#' Google Drive authentication.
#' 
#' @returns A dribble of the folder in its final location.
#' 
move_gee_folder_to_parent <- function(folder_name, parent_folder, google_email) {
  
  drive_auth(google_email)
  
  final_path <- paste0(parent_folder, folder_name, "/")
  
  # make sure the parent folder exists
  parent <- drive_get(parent_folder)
  if (nrow(parent) == 0) {
    stop("Parent folder ", parent_folder, " does not exist on Drive.")
  }
  
  # folder already in the parent folder?
  in_parent <- tryCatch(drive_get(final_path), error = function(e) NULL)
  has_in_parent <- !is.null(in_parent) && nrow(in_parent) > 0
  
  # folder at the root of My Drive (where EE puts it)
  at_root <- drive_ls("~/", type = "folder") %>% 
    dplyr::filter(name == folder_name)
  
  if (nrow(at_root) == 0) {
    if (has_in_parent) return(in_parent)
    stop("Could not find GEE export folder '", folder_name, 
         "' in My Drive or in ", parent_folder)
  }
  
  if (!has_in_parent) {
    # one or more root folders; move them all, merge below if there are extras
    drive_mv(at_root[1, ], path = parent)
    extras <- at_root[-1, ]
    final <- drive_get(final_path)
  } else {
    extras <- at_root
    final <- in_parent
  }
  
  # merge any remaining root-level copies into the final folder
  for (i in seq_len(nrow(extras))) {
    files <- drive_ls(extras[i, ])
    for (j in seq_len(nrow(files))) {
      drive_mv(files[j, ], path = final)
    }
    drive_trash(extras[i, ])
  }
  
  final
}
