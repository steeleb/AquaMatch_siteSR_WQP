#' @title Read and format yaml file
#' 
#' @description 
#' Function to read in yaml, reformat and pivot for easy use in scripts
#' 
#' @param yaml user-specified file containing configuration details for the
#' pull read in using read_yaml
#' @param out_folder folder path where the output should be saved
#' 
#' @returns dataframe of the reformatted yaml file. Silently saves 
#' the .csv in the `out_folder` directory path.
#' 
#' 
format_yaml <-  function(yaml, out_folder) {
  # create a nested tibble from the yaml file
  nested <-  map_dfr(names(yaml), 
                     function(x) {
                       tibble(set_name = x,
                              param = yaml[[x]])
                     })
  # create a new column to contain the nested parameter name and unnest the name
  nested$desc <- NA_character_
  unnested <- map_dfr(seq(1:length(nested$param)),
                      function(x) {
                        name <- names(nested$param[[x]])
                        nested$desc[x] <- name
                        nested <- nested %>% 
                          unnest(param) %>% 
                          mutate(param = as.character(param))
                        nested[x,]
                      })
  # re-orient to make it easy to grab necessary info in future functions
  unnested <- unnested %>% 
    select(desc, param) %>% 
    pivot_wider(names_from = desc, 
                values_from = param)
  write_csv(unnested, file.path(out_folder, "yml.csv"))
  unnested
}

