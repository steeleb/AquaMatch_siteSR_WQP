function(sites) {
  # Build datum/EPSG table - datum varies throughout the dataset.
  epsg_codes <- tribble(
    ~HorizontalCoordinateReferenceSystemDatumName, ~epsg,
    # American Samoa Datum
    "AMSMA", 4169,
    # Midway Astro 1961
    "ASTRO", 37224,
    # Guam 1963
    "GUAM", 4675,
    # High Accuracy Reference Network for NAD83
    "HARN", 4957,
    # Johnston Island 1961 (Spelled Johnson in WQX)
    "JHNSN", 6725,
    # North American Datum 1927
    "NAD27", 4267,
    # North American Datum 1983
    "NAD83", 4269,
    # Old Hawaiian Datum
    "OLDHI", 4135,
    # Assume WGS84
    "OTHER", 4326,
    # Puerto Rico Datum
    "PR", 4139,
    # St. George Island Datum
    "SGEOR", 4138,
    # St. Lawrence Island Datum
    "SLAWR", 4136,
    # St. Paul Island Datum
    "SPAUL", 4137,
    # Assume WGS84
    "UNKWN", 4326,
    # Wake-Eniwetok 1960
    "WAKE", 37229,
    # World Geodetic System 1972
    "WGS72", 4322,
    # World Geodetic System 1984
    "WGS84", 4326
  )
  
  # Add EPSG codes
  site_w_epsg <- sites %>%
    left_join(x = .,
              y = epsg_codes,
              by = "HorizontalCoordinateReferenceSystemDatumName")
  
  # Transform to common CRS WGS84 so we can have a single sf object
  site_sf_unified <- site_w_epsg %>%
    # Group by CRS 
    split(f = .$datum) %>%
    # Transform and re-stack
    map_df(.x = .,
           .f = ~ .x %>%
             st_as_sf(coords = c("LongitudeMeasure", "LatitudeMeasure"),
                      crs = unique(.x$epsg)) %>%
             st_transform(crs = 4326))

}
