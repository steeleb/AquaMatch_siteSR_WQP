#' @title Add scene metadata to RS band summary data
#' 
#' @description
#' Function to combine a reduced set of scene metadata with the upstream collated RS
#' data for downstream use
#'
#' @param yaml contents of the yaml .csv file
#' @param collated_files list of file paths - output of the make_collated_data_files target
#' @param file_prefix specified string that matches the file group to collate
#' @param version_identifier user-specified string to identify the RS pull these
#' data are associated with
#' 
#' @returns silently creates collated .feather files from 'mid' folder and 
#' dumps into 'data'
#' 
#' 
add_metadata <- function(yaml,
                         collated_files,
                         file_prefix, 
                         version_identifier) {
  
  # load the metadata
  meta_file <- collated_files[grepl("metadata", collated_files)]
  metadata <- read_feather(meta_file)
  # do some metadata formatting
  metadata_light <- metadata %>% 
    # Landsat 4-7 and 8/9 store image quality differently, so here, we"re harmonizing this.
    mutate(IMAGE_QUALITY = if_else(is.na(IMAGE_QUALITY), 
                                   IMAGE_QUALITY_OLI, 
                                   IMAGE_QUALITY)) %>% 
    select(system.index = `system:index`, 
           WRS_PATH, 
           WRS_ROW, 
           "mission" = SPACECRAFT_ID, 
           "date" = DATE_ACQUIRED, 
           "UTC_time" = SCENE_CENTER_TIME, 
           CLOUD_COVER,
           IMAGE_QUALITY, 
           IMAGE_QUALITY_TIRS, 
           SUN_AZIMUTH, 
           SUN_ELEVATION) 
  
  # get file using extent
  files <- collated_files[grepl("point", collated_files)]
  
  walk(files, function(file) {
    # load file
    df <- read_feather(file) %>% 
      data.table(.)
    
    # get the mission type
    miss <- unique(df$mission)
    
    # filter the metadata to that mission
    meta_miss <- filter(metadata_light, mission == miss)
    
    spatial_info <- read_csv(file.path(yaml$data_dir,
                                       yaml$location_file)) %>% 
      rename(r_id = yaml$unique_id)%>% 
      mutate(r_id = as.character(r_id))
    
    # format system index for join - right now it has a rowid and the unique LS id
    # could also do this rowwise, but this method is a little faster
    df$r_id <- map_chr(.x = df$`system:index`, 
                       function(.x) {
                         parsed <- str_split(.x, '_')
                         last(unlist(parsed))
                       })
    df$system.index <- map_chr(.x = df$`system:index`, 
                               #function to grab the system index
                               function(.x) {
                                 parsed <- str_split(.x, '_')
                                 str_len <- length(unlist(parsed))
                                 parsed_sub <- unlist(parsed)[1:(str_len-1)]
                                 str_flatten(parsed_sub, collapse = '_')
                               })
    
    # combine with metadata and spatial info
    df <- df %>% 
      select(-`system:index`) %>% 
      left_join(., meta_miss) %>% 
      left_join(., spatial_info)
    
    # get the dswe type
    dswe <- unique(df$DSWE)
    write_feather(df,
                  file.path("5_siteSR_stack/out/",
                            paste0(file_prefix,
                                   "_collated_point_meta_",
                                   miss,
                                   "_",
                                   dswe,
                                   "_v",
                                   version_identifier,
                                   ".feather")))
  })
  
  # return the list of files from this process
  file.path("5_siteSR_stack/out/",
            pattern = file_prefix,
            full.names = TRUE) %>% 
    #but make sure they are the specified version
    .[grepl(version_identifier, .)] %>% 
    .[!grepl('filtered', .)]
  
}
