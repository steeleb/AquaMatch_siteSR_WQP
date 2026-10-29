#' @title Remove characters from text fields that cause issues in csv files
#'
#' @description
#' Some location identifiers and names contain characters (e.g. unclosed double 
#' quotes, line breaks, tabs, other control characters) that break csv parsing 
#' or fail EDI requirements. This function removes double quotes and control 
#' characters from the specified (or all) character columns and trims 
#' whitespace.
#'
#' @param df dataframe (or sf object) to clean
#' @param cols character vector of column names to clean. If NULL, all character
#' columns are cleaned.
#'
#' @returns df with cleaned text fields
#'
#'
clean_text_fields <- function(df, cols = NULL) {
  if (is.null(cols)) {
    cols <- names(df)[map_lgl(df, is.character)]
  }
  df %>% 
    mutate(across(all_of(cols),
                  ~ .x %>% 
                    # double quotes (straight and curly)
                    str_remove_all('["“”]') %>% 
                    # control characters, including line breaks and tabs
                    str_remove_all("[[:cntrl:]]") %>% 
                    str_squish()))
}
