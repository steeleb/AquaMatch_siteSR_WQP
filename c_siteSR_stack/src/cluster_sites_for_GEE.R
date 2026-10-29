#' @title Cluster RS-visible sites that share overlapping buffers
#'
#' @description
#' Many siteSR sites are very close to one another, so extracting the same pixels
#' for each of them is redundant compute in Earth Engine. This function groups
#' sites so that only one site per group (the "extraction site") is sent to EE.
#' Sites are grouped when:
#'
#' - every pair of sites in the group has buffers (of radius `buffer`) that
#' overlap by at least `min_overlap` of the buffer area, and
#' - the sites are attributed to the same feature: the same NHD waterbody
#' (`wb_nhd_id`) for Lake/Reservoir and Pond sites, or the same NHD flowline
#' (`fl_nhd_id`) for Stream and Ditch/Canal sites. Lake/Pond and Stream/Canal
#' sites without an assigned feature are never grouped. All other site types
#' (Estuary, Other) are grouped with sites of the same `harmonized_site_type`.
#'
#' Pairwise overlap for equal-radius circles is a function of the distance
#' between their centers, so the overlap criterion is converted into a maximum
#' center-to-center distance. Groups are built greedily: sites are ordered
#' spatially, the first unassigned site seeds a group, and nearby sites are
#' added only if they are within the maximum distance of every site already in
#' the group.
#'
#' The extraction site is a member of the group (so extracted data remain keyed
#' to a real `siteSR_id`). It is chosen as the member with the best waterbody
#' (lake) or flowline (river) assignment flag, then the smallest summed distance
#' to the other members (the medoid), then the lowest `siteSR_id`.
#'
#' @param sites tibble of RS-visible sites, the output of target `b_visible_sites`.
#' Must contain `id`.
#' @param site_info tibble of site information, the output of target
#' `a_sites_with_NHD_info`
#' @param buffer numeric value of the buffer for GEE site extraction in meters
#' @param min_overlap numeric between 0 and 1, the minimum proportion of buffer
#' area that must be shared by every pair of sites in a group
#'
#' @returns tibble with one row per site in `sites`, where `siteSR_id` is the
#' site, `extraction_siteSR_id` is the site sent to EE for that site's group,
#' and the remaining columns describe the grouping and the shoreline/assignment
#' flags at the extraction site.
#'
#' @note
#' Flags describe the area sampled by EE, so the flags of the extraction site
#' apply to all of the sites in its group.
#'
#'
cluster_sites_for_GEE <- function(sites,
                                  site_info,
                                  buffer,
                                  min_overlap = 0.75) {

  buffer <- as.numeric(buffer)

  # the overlap of two equal circles of radius r with centers d apart is
  # (2 r^2 acos(d / 2r) - (d / 2) sqrt(4 r^2 - d^2)) / (pi r^2)
  overlap_fn <- function(d) {
    (2 * buffer^2 * acos(d / (2 * buffer)) -
       (d / 2) * sqrt(4 * buffer^2 - d^2)) / (pi * buffer^2) - min_overlap
  }
  max_dist <- uniroot(overlap_fn, interval = c(0, 2 * buffer))$root
  message(paste0("Sites are grouped if they are <= ", round(max_dist, 2),
                 " m apart (", min_overlap * 100, "% buffer overlap)."))

  flag_cols <- c("flag_wb", "flag_fl", "dist_to_shore", "dist_to_fl",
                 "flag_optical_shoreline", "flag_thermal_TM_shoreline",
                 "flag_thermal_ETM_shoreline", "flag_thermal_TIRS_shoreline")

  info <- site_info %>%
    filter(siteSR_id %in% sites$id) %>%
    select(siteSR_id, harmonized_site_type, WGS84_Latitude, WGS84_Longitude,
           wb_nhd_id, fl_nhd_id, all_of(flag_cols)) %>%
    mutate(
      # which feature do sites need to share?
      grp = case_when(harmonized_site_type %in% c("Lake/Reservoir", "Pond") &
                        !is.na(wb_nhd_id) ~ paste0("wb_", wb_nhd_id),
                      harmonized_site_type %in% c("Stream", "Ditch/Canal") &
                        !is.na(fl_nhd_id) ~ paste0("fl_", fl_nhd_id),
                      !harmonized_site_type %in% c("Lake/Reservoir", "Pond",
                                                   "Stream", "Ditch/Canal") &
                        !is.na(harmonized_site_type) ~ paste0("loc_", harmonized_site_type),
                      .default = NA_character_),
      grp_basis = case_when(startsWith(grp, "wb_") ~ "waterbody",
                            startsWith(grp, "fl_") ~ "flowline",
                            startsWith(grp, "loc_") ~ "location_and_type",
                            .default = "unclustered"),
      # for choosing the extraction site: prefer sites that are assigned most
      # directly to the waterbody/flowline (lower flag is better).
      assign_flag = case_when(startsWith(grp, "wb_") ~ flag_wb,
                              startsWith(grp, "fl_") ~ flag_fl,
                              .default = 0),
      # work in a local UTM zone so that distances are in meters
      utm_epsg = if_else(WGS84_Latitude >= 0, 32600L, 32700L) +
        as.integer(pmin(pmax(ceiling((WGS84_Longitude + 180) / 6), 1), 60))
    )

  if (nrow(info) != nrow(sites) || anyNA(info$WGS84_Latitude)) {
    stop("All visible sites must be present in `site_info` with coordinates.")
  }

  # cluster within each UTM zone. Sites on opposite sides of a zone boundary will
  # not be grouped, which is a negligible loss.
  clustered <- map(
    split(info, info$utm_epsg),
    \(zone) {
      xy <- sf::sf_project(from = "EPSG:4326",
                           to = paste0("EPSG:", zone$utm_epsg[1]),
                           pts = as.matrix(zone[, c("WGS84_Longitude", "WGS84_Latitude")]))
      zone$x <- xy[, 1]
      zone$y <- xy[, 2]
      # order is what makes the greedy grouping reproducible
      zone <- zone %>% arrange(x, y, siteSR_id)
      zone$cluster <- greedy_cluster(x = zone$x, y = zone$y, grp = zone$grp,
                                     max_dist = max_dist)
      zone
    }) %>%
    bind_rows() %>%
    mutate(cluster = paste0(utm_epsg, "_", cluster))

  # pick the extraction site for each cluster (medoid, among the sites with the
  # best assignment flag)
  extraction <- clustered %>%
    group_by(cluster) %>%
    mutate(n_sites = n(),
           sum_dist = map_dbl(seq_len(n()),
                              \(i) sum(sqrt((x - x[i])^2 + (y - y[i])^2)))) %>%
    arrange(assign_flag, sum_dist, siteSR_id, .by_group = TRUE) %>%
    slice(1) %>%
    ungroup() %>%
    select(cluster, extraction_siteSR_id = siteSR_id, ex_x = x, ex_y = y,
           all_of(flag_cols)) %>%
    rename_with(~ paste0("extraction_", .x), all_of(flag_cols))

  clustered %>%
    group_by(cluster) %>%
    mutate(n_sites_in_cluster = n()) %>%
    ungroup() %>%
    left_join(extraction, by = "cluster") %>%
    mutate(dist_to_extraction_site_m = round(sqrt((x - ex_x)^2 + (y - ex_y)^2), 1)) %>%
    select(siteSR_id, extraction_siteSR_id, n_sites_in_cluster,
           cluster_basis = grp_basis, dist_to_extraction_site_m,
           starts_with("extraction_")) %>%
    arrange(siteSR_id)

}


#' @title Greedy clique grouping of points
#'
#' @description
#' Group points so that every pair within a group is within `max_dist` of each
#' other and shares a value of `grp`. Points with an `NA` `grp` are never
#' grouped.
#'
#' @param x,y numeric vectors of planar coordinates (meters), assumed to be in
#' the order desired for seeding groups
#' @param grp vector of the same length as x, the value that points must share
#' in order to be grouped
#' @param max_dist numeric, the maximum distance between any pair in a group
#'
#' @returns integer vector of group id (the row index of the seed point)
#'
#'
greedy_cluster <- function(x, y, grp, max_dist) {

  n <- length(x)
  # neighbors within max_dist of each point, nearest first. If any point has as
  # many neighbors as we asked for, the list may be truncated, so ask again for
  # more.
  k <- min(n, 500)
  repeat {
    nn <- RANN::nn2(cbind(x, y), k = k, searchtype = "radius", radius = max_dist)
    if (k >= n || all(nn$nn.idx[, k] == 0)) break
    k <- min(n, k * 4)
  }

  cluster <- rep(NA_integer_, n)
  for (i in seq_len(n)) {
    if (!is.na(cluster[i])) next
    cluster[i] <- i
    if (is.na(grp[i])) next
    nb <- nn$nn.idx[i, ]
    nb <- nb[nb > 0 & nb != i]
    # same feature/type and not yet assigned
    nb <- nb[is.na(cluster[nb]) & !is.na(grp[nb]) & grp[nb] == grp[i]]
    members <- i
    for (j in nb) {
      # a site joins only if it is close enough to every current member
      if (all((x[members] - x[j])^2 + (y[members] - y[j])^2 <= max_dist^2)) {
        cluster[j] <- i
        members <- c(members, j)
      }
    }
  }

  cluster
}
