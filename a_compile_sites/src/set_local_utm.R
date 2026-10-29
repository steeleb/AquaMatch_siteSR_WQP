#' @title Transform points and features to a local UTM zone for planar analysis
#' 
#' @description
#' Spatial operations (nearest feature, intersects, distance, buffer) on 
#' lon/lat data use s2 in {sf}, which for large NHD layers (e.g., 1 million 
#' flowlines in a HUC4) takes minutes and tens of GB of memory per HUC4. 
#' Within a HUC4, the area is small enough that a single UTM zone (chosen from 
#' the mean longitude/latitude of the sites) gives accurate distances in meters, 
#' and planar GEOS operations are much faster and lighter. This is the same 
#' approach used to find distance to shore: we assume that all points in a 
#' HUC4 are in the same UTM zone.
#' 
#' @param points simple feature object of points
#' @param features simple feature object of polygons/lines
#' 
#' @returns a list with `points` and `features` transformed to UTM
#' 
#' 
set_local_utm <- function(points, features) {
  
  lonlat <- points %>% 
    st_transform("EPSG:4326") %>% 
    st_coordinates()
  utm_suffix <- ceiling((mean(lonlat[, 1]) + 180) / 6)
  utm_epsg <- if_else(mean(lonlat[, 2]) >= 0,
                      # EPSG prefix for N hemisphere
                      32600 + utm_suffix,
                      # for S hemisphere
                      32700 + utm_suffix)
  
  list(points = st_transform(points, crs = utm_epsg),
       features = st_transform(features, crs = utm_epsg))
}
