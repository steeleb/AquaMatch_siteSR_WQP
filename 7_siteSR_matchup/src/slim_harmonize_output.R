format_limit_parameter_data <- function(parameter_data, 
                                        site_data = p4_sites_with_NHD_attribution) {
  param_df <- harmonized_data %>% 
    select(OrganizationIdentifier, MonitoringLocationIdentifier, ResolvedMonitoringLocationTypeName,
           harmonized_utc:harmonized_value) %>% 
    select(-c(lon:parameter_name_description)) %>% 
    relocate(subgroup_id) 
  site_df <- site_data %>% 
    select(OrganizationIdentifier, MonitoringLocationIdentifier, HUCEightDigitCode,
           WGS84_Latititude, WGS84_Longitude, ...flow..., ...wbd...)
           
  
    
}