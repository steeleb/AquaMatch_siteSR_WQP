#' @title Retrieve and clean site metadata for all WQP and NWIS sites in the US
#' and territories
#' 
#' @description
#' Function to retrieve site metadata from the WQP/NWIS using FIPS state codes 
#' and the functions dataRetrieval::whatWQPsites() and dataRetrieval::whatNWISsites().
#' Metadata are filtered to those for surface water sites only.
#' 
#' @param fips_state_code_desc state code description provided at 
#' "https://www.waterqualitydata.us/Codes/statecode?countrycode=US", previously
#' filtered in an existing {target} to map over
#' @param site_source either "WQP" or "NWIS" - indicating which {dataRetrieval} 
#' function to use
#' 
#' @returns 
#' Returns a data frame containing site metadata associated with WQP or NWIS
#' surface water sites
#' 
#' @note FIPS code value will only work for US states, for that reason, we use the
#' code descriptions in this function in order to grab for territories, too. This
#'  code is adapted from 'get_site_info()' used in the AquaMatch Harmonize pipeline.
#' 
#' 
get_site_info <- function(fips_state_code_desc, site_source){
  
  if (!site_source %in% c("WQP", "NWIS")) {
    stop("Site source unrecognized. site_source argument must be either 'WQP' or 'NWIS'.")
  }
  
  # Use safely() when requesting data to prepare for the possibility of failures
  # also make a list of the surface water location types specific to the site
  # source argument
  if (site_source == "WQP") {
    safe_site <- safely(.f = ~whatWQPsites(statecode = .x))
    filter_param <- sym("MonitoringLocationTypeName")
    filter_list <- c("Stream: Ditch", "Stream", "Lake, Reservoir, Impoundment",
                     "Estuary", "Stream: Canal", "River/Stream", "Lake", 
                     "Great Lake", "River/Stream Intermittent", "Reservoir",
                     "Other-Surface Water", "River/Stream Perennial", "Channelized Stream")
    
  } else {
    safe_site <- safely(.f = ~whatNWISsites(statecode = .x))
    filter_param <- sym("site_tp_cd")
    filter_list <- c("ES", "LK", "ST", "ST-CA", "ST-DCH")
  }
  
  # Map pull, returning a list of result/error list item pairs for the state code.
  # Each result, if not an error, will be a data frame
  raw_sites <- safe_site(fips_state_code_desc)
  
  # Grab the results list:
  metadata <- raw_sites$result 
  
  # Check for data, and return the dataframe if it's not NULL
  if (!is.null(metadata)) {
    metadata <- metadata %>%
      # filter for site types that include surface water
      filter(!!filter_param %in%
               filter_list) %>% 
      # make sure all columns are character for later collation
      mutate(across(everything(),
                     ~ as.character(.))) %>% 
      # add source column
      mutate(source = site_source)
    return(metadata)
  }
  
}
