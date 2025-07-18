#' @title Collate downloaded csv files into a feather file
#' 
#' @description
#' Function to grab all downloaded .csv files from the download 
#' folder, and collate them into .feather files subsetted per arguments in the
#' function. If left to default, this will create 3 files per DSWE setting: a 
#' metadata file, a LS457 file, and a LS89 file. For the purposes of this workflow
#' all files are compressed using the "lz4" method. 
#'
#' @param file_type text string; unique string for filtering files to be 
#' downloaded from Drive. Current options: "LS457", "LS89", "metadata", 
#' "pekel", NULL. Defaults to NULL. Use this argument if using mulitcore.
#' @param WRS_prefix text string; WRS path-row prefix to reduce memory use, only
#' can be used with file_type, dswe, and separate_missions options. 
#' @param yml dataframe; name of the target object from the -b- group that
#' stores the GEE run configuration settings as a data frame.
#' @param dswe text string; dswe value to filter input files by. Defaults to NULL.
#' Use this argument if multiple dswe settings have been extracted from GEE
#' @param separate_missions boolean; indication of whether the output should be
#' separated by individual Landsat missions. Defaults to FALSE. Use this if file
#' size is anticipated to be large. LS457 files will often push the limits of R 
#' memory on large GEE pulls.
#' @param depends target object; any target that must be run prior to this 
#' function. Defaults to NULL.
#' 
#' @returns none. Silently saves files to 'c_siteSR_stack/mid/'
#' 
#' 
collate_csvs_from_drive <- function(file_type = NULL, 
                                    WRS_prefix = NULL,
                                    yml, 
                                    dswe = NULL, 
                                    separate_missions = FALSE,
                                    depends = NULL) {
  
  if (!is.null(file_type)) {
    if (!file_type %in% c("LS457", "LS89", "metadata", "pekel")) {
      warning("The file type argument provided is not recognized.\n
              This may result in unintended downloads.")
    }
  }
  
  # if WRS_prefix provided
  if (!is.null(WRS_prefix)) {
    # check to make sure that all other arguments are satisfied
    if (is.null(file_type) | is.null(dswe) | separate_missions == FALSE) {
      stop("To use the WRS_prefix argument, `file_type`, `dswe`, and `separate_missions`\n
           arguments must all be used.",
           call. = TRUE)
    }
    if (file_type == "metadata") {
      warning("WRS_prefix argument is not supported for metadata file types. The \n
              output data will not be subset by the WRS_prefix.")
    }
  }
  
  # make directory path based on function arguments
  if (is.null(file_type)) {
    from_directory <- file.path("c_siteSR_stack/down/", yml$run_date)
  } else {
    from_directory <- file.path("c_siteSR_stack/down/", yml$run_date, file_type)
  }
  
  # make and store directory for collated files
  to_directory <- file.path("c_siteSR_stack/mid/", yml$run_date)
  if (!dir.exists(to_directory)) {
    dir.create(to_directory)
  }
  
  # get the list of files in the `in` directory 
  files <- list.files(from_directory,
                      full.names = TRUE) 
  
  # check to see if files need to subset for type
  if (!is.null(file_type)) {
    # subset for file type  
    type_subset <- files[grepl(file_type, files)]
    # if file type isn't metadata, then remove "metadata" from the filtered files,
    # since that has the LS label too
    if (file_type != "metadata") {
      type_subset <- type_subset[!grepl("metadata", type_subset)]
    }
    # make sure there are files present in this filter
    if (length(type_subset) == 0) {
      stop("You have used a `file_type` argument that is unrecognized.\n
              Acceptable `file_type` arguments are 'metadata', 'LS457', 'LS89'.",
           call. = TRUE)
    } 
    # rename to match workflow of non-subset files
    files <- type_subset
  }
  
  # check to see if files need to subset for dswe
  # need to have handling for null file type first, or won't work here with metadata
  if (!is.null(dswe) & is.null(file_type)) {
    # subset for dswe - but need to add "_" before and after
    dswe_subset <- files[grepl(paste0("_", dswe, "_"), files)]
    metadata <- files[grepl("metadata", files)]
    filtered_files <- c(dswe_subset, metadata)
    # make sure there are files present in this filter
    if (length(filtered_files) == 0) {
      stop("You have used a `dswe` argument that is unrecognized.\n
      Acceptable `dswe` arguments are 'DSWE1', 'DSWE1a', 'DSWE3'.",
           call. = TRUE)
    } 
    # rename to match workflow of non-subset files
    files <- filtered_files
  } else if (!is.null(dswe) & file_type != "metadata") {
    # subset for dswe - but need to add "_" before and after
    dswe_subset <- files[grepl(paste0("_", dswe, "_"), files)]
    # make sure there are files present in this filter
    if (length(dswe_subset) == 0) {
      stop("You have used a `dswe` argument that is unrecognized or you are\n
      attempting to subset metadata by DSWE, which is unnecessary.\n
      Acceptable `dswe` arguments are 'DSWE1', 'DSWE1a', 'DSWE3'.",
           call. = TRUE)
    } 
    # rename to match workflow of non-subset files
    files <- dswe_subset
  }
  
  if (!is.null(WRS_prefix)) {
    files <- files[grepl(paste0("_", WRS_prefix), files)]
  }
  
  # PROCESS METADATA --------------------------------------------------------
  
  # process metadata separately from site data
  metadata <- files[grepl("metadata", basename(files))]
  
  if (length(metadata) > 0) {
    
    # process LS457 and LS89 mission groups separately
    mission_groups <- c("LS457", "LS89")
    
    mission_groups %>% 
      walk(\(mg) {
        if (any(grepl(mg, metadata))) {
          
          subset_mg <- metadata[grepl(mg, metadata)]
          
          # if separating missions, iterate over mission to save independent files
          if (separate_missions) {
            if (mg == "LS457") {
              missions = c("LT04", "LT05", "LE07")
            } else {
              missions = c("LC08", "LC09")
            }
            
            missions %>% 
              walk(\(m) {
                m_collated <- subset_mg %>% 
                  map(\(mg) tryCatch({
                    fread(mg)[grepl(m, `system:index`)]
                  },
                  error = function(e) {
                    NULL
                  })) %>% 
                  rbindlist(., use.names = TRUE, fill = TRUE)
                
                # create file path
                fp <- file.path(to_directory,
                                paste0(yml$proj, 
                                       "_collated_metadata_",
                                       m,
                                       "_",
                                       yml$run_date, 
                                       ".feather"))
                
                write_feather(m_collated, 
                              fp,
                              compression = "lz4")
                
                # try to free up space here
                rm(m_collated)
                gc()
              }
              )
            
          } else { 
            
            # otherwise, read all the data and save the file
            data_mg <- subset_mg %>% 
              map(\(s) tryCatch({
                fread(s)
              },
              error = function(e) {
                return(NULL)
              })) %>% 
              rbindlist(., use.names = TRUE, fill = TRUE)
            
            write_feather(data_mg, 
                          file.path(to_directory,
                                    paste0(yml$proj, 
                                           "_collated_metadata_",
                                           mg, 
                                           "_",
                                           yml$run_date, 
                                           ".feather")),
                          compression = "lz4")
            
            
          } # end conditional for separate mission groups
          
        } # end sanity check of mission group in file list
        
      }) # end walk function 
    
  } # end metadata collation
  
  
  # PROCESS SITES -----------------------------------------------------------
  
  # process sites separately from metadata
  sites <- files[!grepl("metadata", files)]
  
  if (length(sites) > 0) {
    
    # process LS457 and LS89 mission groups separately
    if (is.null(file_type)) {
      
      mission_groups <- c("LS457", "LS89")
      
      mission_groups %>% 
        walk(\(mg) {
          
          # if sites file list contains the mission group
          if (any(grepl(mg, sites))) {
            
            subset_mg <- sites[grepl(mg, sites)]
            
            # if separating missions, iterate over mission to save independent files
            if (separate_missions) {
              if (mg == "LS457") {
                missions = c("LT04", "LT05", "LE07")
              } else {
                missions = c("LC08", "LC09")
              }
              
              missions %>% 
                walk(\(m) {
                  m_collated <- subset_mg %>% 
                    map(\(s) tryCatch({
                      df <- fread(s)[grepl(m, `system:index`)]
                      filename <- basename(s)
                      # get column names that need to be 
                      # coerced to numeric (all but index)
                      df_names <- names(df)[2:length(names(df))]
                      # coerce columns to numeric and add
                      # source/file name
                      df[, (df_names) := lapply(.SD, as.numeric), .SDcols = df_names]
                      df[, source := filename]
                    },
                    error = function(e) { 
                      NULL 
                    } 
                    ))
                }) %>% 
                rbindlist(., use.names = TRUE, fill = TRUE)
              
              # check for dswe subset, name accordingly
              fp <- if_else(!is.null(dswe),
                            file.path(to_directory,
                                      paste0(yml$proj, 
                                             "_collated_sites_",
                                             dswe,
                                             "_",
                                             m,
                                             "_",
                                             yml$run_date, 
                                             ".feather")),
                            file.path(to_directory,
                                      paste0(yml$proj, 
                                             "_collated_sites_",
                                             m,
                                             "_",
                                             yml$run_date, 
                                             ".feather")))
              
              write_feather(m_collated,
                            fp,
                            compression = "lz4")              
              
              
              # try to free up space here
              rm(m_collated)
              gc()
              
            } else { # end separate missions
              
              # just map mission groups
              mg_collated <- subset_mg %>% 
                map(\(s) tryCatch({
                  df <- fread(s) 
                  filename <- basename(s)
                  # get column names that need to be 
                  # coerced to numeric (all but index)
                  df_names <- names(df)[2:length(names(df))]
                  # coerce columns to numeric and add
                  # source/file name
                  df[, (df_names) := lapply(.SD, as.numeric), .SDcols = df_names]
                  df[, source := filename]
                },
                error = function(e) { 
                  stop("There was an error when collating by mission-group.") 
                })) %>% 
                rbindlist(., use.names = TRUE, fill = TRUE)
              
              # check for dswe subset, name accordingly
              fp <- if_else(!is.null(dswe),
                            file.path(to_directory,
                                      paste0(yml$proj, 
                                             "_collated_sites_",
                                             dswe,
                                             "_",
                                             mg,
                                             "_",
                                             yml$run_date, 
                                             ".feather")),
                            file.path(to_directory,
                                      paste0(yml$proj, 
                                             "_collated_sites_",
                                             mg,
                                             "_",
                                             yml$run_date, 
                                             ".feather")))
              
              write_feather(mg_collated,
                            fp,
                            compression = "lz4")      
            } # end separate mission groups
            
          } else {
            
            # otherwise, read all the data and save the file
            
            data_mg <- sites %>% 
              map(\(s) tryCatch({
                df <- fread(s)[grepl(m, `system:index`)]
                filename <- basename(s)
                # get column names that need to be 
                # coerced to numeric (all but index)
                df_names <- names(df)[2:length(names(df))]
                # coerce columns to numeric and add
                # source/file name
                df[, (df_names) := lapply(.SD, as.numeric), .SDcols = df_names]
                df[, source := filename]
              },
              error = function(e) {
                NULL
              }
              )) %>% 
              rbindlist(., use.names = TRUE, fill = TRUE)
            
            # check for dswe subset, name accordingly
            fp <- if_else(!is.null(dswe),
                          file.path(to_directory,
                                    paste0(yml$proj, 
                                           "_collated_sites_",
                                           dswe,
                                           "_",
                                           mg, 
                                           "_",
                                           yml$run_date, 
                                           ".feather")),
                          file.path(to_directory,
                                    paste0(yml$proj, 
                                           "_collated_sites_",
                                           mg, 
                                           "_",
                                           yml$run_date, 
                                           ".feather")))
            write_feather(data_mg,
                          fp,
                          compression = "lz4")
            
            # try to free up space here
            rm(data_mg)
            gc()
            
          } # end NULL file_type subset
          
        }) # end walk of mission groups
      
      
    } else {
      
      # if file_type specified, use that to define missions/filter
      if (any(grepl(file_type, sites))) {
        
        subset_mg <- sites[grepl(file_type, sites)]
        
        # if separating missions, iterate over mission to save independent files
        if (separate_missions) {
          
          if (file_type == "LS457") {
            missions = c("LT04", "LT05", "LE07")
          } else {
            missions = c("LC08", "LC09")
          }
          
          missions %>% 
            walk(\(m) {
              m_collated <- subset_mg %>% 
                map(\(s) {
                  tryCatch({
                    df <- fread(s)[grepl(m, `system:index`)]
                    filename <- basename(s)
                    # get column names that need to be 
                    # coerced to numeric (all but index)
                    df_names <- names(df)[2:length(names(df))]
                    # coerce columns to numeric and add
                    # source/file name
                    df[, (df_names) := lapply(.SD, as.numeric), .SDcols = df_names]
                    df[, `system:index` := as.character(`system:index`)]
                    df[, source := filename]
                    return(df)
                  },
                  error = function(e) {
                    return(NULL)
                  })}) %>% 
                rbindlist(., use.names = TRUE, fill = TRUE)
              
              ## file path prefix (incorporate WRS_prefix)
              fp_prefix <- if_else(!is.null(WRS_prefix),
                                   file.path(to_directory,
                                             paste0(yml$proj, 
                                                    "_collated_sites_",
                                                    m,
                                                    "_",
                                                    WRS_prefix)),
                                   file.path(to_directory,
                                             paste0(yml$proj, 
                                                    "_collated_sites_",
                                                    m)))
              ## file path suffix (incorporate dswe)
              fp_suffix <- if_else(!is.null(dswe), 
                                   paste0("_",
                                          dswe,
                                          "_",
                                          yml$run_date, 
                                          ".feather"),
                                   paste0("_",
                                          yml$run_date, 
                                          ".feather"))
              
              write_feather(m_collated, 
                            paste0(fp_prefix, fp_suffix),
                            compression = "lz4")
              
              # try to free up space here
              rm(m_collated)
              gc()
              
            }) # end separate by mission  
          
        } else { # if not separating by mission
          
          # read all the data and save the file
          data_mg <- subset_mg %>% 
            map(\(s) {
              tryCatch({
                df <- fread(s)[grepl(m, `system:index`)]
                filename <- basename(s)
                # get column names that need to be 
                # coerced to numeric (all but index)
                df_names <- names(df)[2:length(names(df))]
                # coerce columns to numeric and add
                # source/file name
                df[, (df_names) := lapply(.SD, as.numeric), .SDcols = df_names]
                df[, `system:index` := as.character(`system:index`)]
                df[, source := filename]
              },
              error = function(e) {
                NULL
              })
            }) %>% 
            rbindlist(., use.names = TRUE, fill = TRUE)
          
          # create filepath using dswe setting
          fp <- if_else(!is.null(dswe),
                        file.path(to_directory,
                                  paste0(yml$proj, 
                                         "_collated_sites_",
                                         dswe,
                                         "_",
                                         file_type, 
                                         "_",
                                         yml$run_date, 
                                         ".feather")),
                        file.path(to_directory,
                                  paste0(yml$proj, 
                                         "_collated_sites_",
                                         file_type, 
                                         "_",
                                         yml$run_date, 
                                         ".feather")))
          
          write_feather(data_mg, 
                        fp,
                        compression = "lz4")
          
          # try to free up space here
          rm(data_mg)
          gc()
          
        } # end conditional for separate mission
        
      } # end separate by file_type
      
    } # end conditional for file_type
    
  } # end site collation
  
  # no return in function
  return ( NULL )
  
}
