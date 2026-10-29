#' @title Distance from points to their nearest feature
#' 
#' @description
#' Measure the distance between each point and the feature it has been paired 
#' with (usually the output of `st_nearest_feature()`). Calling `st_distance()`
#' with `by_element = TRUE` on a subset of features that repeats the same 
#' feature once per point re-processes (and for large polygons, such as 
#' estuaries, uses huge amounts of memory for) that feature for every point. 
#' Here, each unique feature is processed once.
#' 
#' @param points simple feature object of points
#' @param features simple feature object of polygons/lines
#' @param feature_idx integer vector, the row of `features` paired with each 
#' point, same length as `nrow(points)`
#' 
#' @returns numeric vector of distances (meters), one per point
#' 
#' 
distance_to_nearest_feature <- function(points, features, feature_idx) {
  
  distances <- rep(NA_real_, nrow(points))
  
  for (idx in unique(feature_idx)) {
    pts_idx <- which(feature_idx == idx)
    distances[pts_idx] <- as.numeric(st_distance(points[pts_idx, ], 
                                                 features[idx, ]))
  }
  
  distances
}
