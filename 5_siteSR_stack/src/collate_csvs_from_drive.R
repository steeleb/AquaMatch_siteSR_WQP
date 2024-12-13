#' @title Collate downloaded csv files into a feather file
#' 
#' @description
#' Function to grab all downloaded .csv files from the 6_siteSR_stack/in/ folder with a specific
#' file prefix, collate them into a .feather files with version identifiers
#'
#' @param file_prefix specified string that matches the file group to collate
#' @param version_identifier user-specified string to identify the RS pull these
#' data are associated with
#' 
#' @returns Silently saves a feather file.
#' 
#' 
collate_csvs_from_drive <- function(file_prefix, version_identifier) {
  # get the list of files in the `in` directory 
  files <- list.files(file.path("5_siteSR_stack/down/stack/",
                                version_identifier),
                      pattern = file_prefix,
                      full.names = TRUE) 
  
  meta_files <- files[grepl("meta", files)]
  all_meta <- map_dfr(meta_files, read_csv) 
  write_feather(all_meta, file.path("5_siteSR_stack/mid/",
                                    paste0(file_prefix, "_collated_metadata_",
                                           version_identifier, ".feather")))
  
  # if point data are present, subset those, collate, and save
  if (any(grepl("site", files))) {
    point_files <- files[grepl("site", files)]
    
    # check for DSWE1 and collate
    if (length(grepl("DSWE1_", point_files)) > 0) {
      DSWE1_files <- point_files[grepl("DSWE1_", point_files)]
      # collate files, but add the filename, since this *could be* is DSWE 1 + 3
      all_DSWE1_points <- map_dfr(.x = DSWE1_files, 
                                  .f = function(.x) {
                                    file_name = last(str_split(.x, '/')[[1]])
                                    df <- read_csv(.x) %>% 
                                      data.table(.)
                                    # grab all column names except system:index
                                    df_names <- colnames(df)[2:length(colnames(df))]
                                    # and coerce them to numeric for joining later
                                    df %>% 
                                      mutate(across(all_of(df_names),
                                                    ~ as.numeric(.)))%>% 
                                      mutate(source = file_name)
                                  }) 
      # filter for each mission to reduce file size
      walk(list("LT04", "LT05", "LE07", "LC08", "LC09"),
           function(miss) {
             df <- all_DSWE1_points %>% 
               filter(grepl(miss, `system:index`)) %>% 
               mutate(DSWE = "DSWE1") %>% 
               mutate(mission = case_when(miss == "LT04" ~ "LANDSAT_4",
                                          miss == "LT05" ~ "LANDSAT_5",
                                          miss == "LE07" ~ "LANDSAT_7",
                                          miss == "LC08" ~ "LANDSAT_8",
                                          miss == "LC09" ~ "LANDSAT_9",
                                          TRUE ~ NA_character_))
             #save that mission's feather file
             write_feather(df, file.path("5_siteSR_stack/mid/",
                                         paste0(file_prefix, 
                                                "_collated_points_",
                                                miss,
                                                "_DSWE1_",
                                                version_identifier, 
                                                ".feather")))
           })
    } 
    
    # check for DSWE1a and collate
    if (length(grepl("DSWE1a", point_files)) > 0) {
      DSWE1a_files <- point_files[grepl("DSWE1a", point_files)]
      # collate files, but add the filename, since this *could be* is DSWE 1 + 3
      all_DSWE1a_points <- map_dfr(.x = DSWE1a_files, 
                                   .f = function(.x) {
                                     file_name = last(str_split(.x, '/')[[1]])
                                     df <- read_csv(.x) %>% 
                                       data.table(.)
                                     # grab all column names except system:index
                                     df_names <- colnames(df)[2:length(colnames(df))]
                                     # and coerce them to numeric for joining later
                                     df %>% 
                                       mutate(across(all_of(df_names),
                                                     ~ as.numeric(.)))%>% 
                                       mutate(source = file_name)
                                   }) 
      # filter for each mission to reduce file size
      walk(list("LT04", "LT05", "LE07", "LC08", "LC09"),
           function(miss) {
             df <- all_DSWE1a_points %>% 
               filter(grepl(miss, `system:index`)) %>% 
               mutate(DSWE = "DSWE1a") %>% 
               mutate(mission = case_when(miss == "LT04" ~ "LANDSAT_4",
                                          miss == "LT05" ~ "LANDSAT_5",
                                          miss == "LE07" ~ "LANDSAT_7",
                                          miss == "LC08" ~ "LANDSAT_8",
                                          miss == "LC09" ~ "LANDSAT_9",
                                          TRUE ~ NA_character_))
             #save that mission's feather file
             write_feather(df, file.path("5_siteSR_stack/mid/",
                                         paste0(file_prefix, 
                                                "_collated_points_",
                                                miss,
                                                "_DSWE1a_",
                                                version_identifier, 
                                                ".feather")))
           })
    } 
    
  } else {
    message("No site files have been downloaded.")
  }
  
  # return the list of files from this process
  list.files("5_siteSR_stack/mid/",
             pattern = file_prefix,
             full.names = TRUE) %>% 
    #but make sure they are the specified version
    .[grepl(version_identifier, .)]
  
}