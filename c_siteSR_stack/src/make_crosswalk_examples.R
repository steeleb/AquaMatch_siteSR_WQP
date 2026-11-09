#' @title Select and collect map data for site-grouping examples
#'
#' @description
#' Builds the (small) spatial data sets used for the siteSR site-grouping
#' examples in the lakeSR bookdown (Section "Grouping sites to reduce redundant
#' extraction"). Examples are chosen by rule from the extraction site crosswalk
#' (target `c_site_crosswalk`) so that they are reproducible. The NHD geometries
#' for each example are read from the NHD Best Resolution HUC4 geopackages
#' (downloaded if they are not present), so this must be run before the
#' geopackages are removed (target `a_remove_NHD_gpkg`). The output is exported
#' to Drive and used by the lakeSR workflow.
#'
#' Examples:
#' - `largest`: the extraction site with the most sites in its group
#' - `largest_waterbody`: as above, for groups based on a waterbody
#' - `waterbody`: a (small) NHD waterbody that has several extraction sites and
#' where grouping removed at least half of the visible sites
#' - `flowline`: as above, for a single NHD flowline
#' - `flowline_sparse`: as `flowline`, but for a flowline with fewer sites and
#' few other sites nearby
#' - `singletons`: an extraction site that is not grouped with anything, where
#' there are several other ungrouped sites within a few hundred meters
#'
#' @param crosswalk tibble, the output of target `c_site_crosswalk`
#' @param site_info tibble, the output of target `a_sites_with_NHD_info`
#' @param HUC4_manifest tibble from `get_bestres_manifest()`, used to download
#' NHD geopackages that are not present locally
#' @param buffer numeric, buffer radius used for extraction in GEE, in meters
#'
#' @returns list with elements `largest`, `largest_waterbody`, `waterbody`,
#' `flowline`, `flowline_sparse`, and `singletons` (each the output of `collect_example()`) and `summary`, a list of
#' data frames summarizing the crosswalk. Plotted in the lakeSR bookdown with
#' `map_crosswalk_example()`.
#'
make_crosswalk_examples <- function(crosswalk,
                                    site_info,
                                    HUC4_manifest,
                                    buffer = 200) {

  info <- site_info %>%
    select(siteSR_id, harmonized_site_type, assigned_HUC, wb_nhd_id,
           wb_gnis_name, wb_areasqkm, fl_nhd_id, fl_gnis_name,
           WGS84_Latitude, WGS84_Longitude)

  cw <- crosswalk %>%
    left_join(info, by = "siteSR_id") %>%
    mutate(role = if_else(siteSR_id == extraction_siteSR_id,
                          "extraction", "grouped"))

  ex <- cw %>% filter(role == "extraction")

  # a) sites with the most sites in their group ------------------------------
  # the largest group overall, and the largest group that is grouped by waterbody
  # (the largest group overall is not necessarily a waterbody)
  largest_id <- ex %>%
    arrange(desc(n_sites_in_cluster), siteSR_id) %>%
    slice(1) %>%
    pull(siteSR_id)
  largest <- collect_example(
    cw = cw,
    focus = cw %>% filter(extraction_siteSR_id == largest_id),
    radius = 600, HUC4_manifest = HUC4_manifest, buffer = buffer,
    feature = if (ex$cluster_basis[ex$siteSR_id == largest_id] == "waterbody") "waterbody" else "flowline")

  largest_wb_id <- ex %>%
    filter(cluster_basis == "waterbody") %>%
    arrange(desc(n_sites_in_cluster), siteSR_id) %>%
    slice(1) %>%
    pull(siteSR_id)
  largest_waterbody <- collect_example(
    cw = cw,
    focus = cw %>% filter(extraction_siteSR_id == largest_wb_id),
    radius = 600, HUC4_manifest = HUC4_manifest, buffer = buffer,
    feature = "waterbody",
    # show the other groups in the window in full
    focus_all = TRUE)

  # b) waterbody with multiple extraction sites and a reduction --------------
  wb_pick <- ex %>%
    filter(cluster_basis == "waterbody", !is.na(wb_nhd_id),
           wb_areasqkm < 3) %>%
    group_by(wb_nhd_id) %>%
    summarize(n_extraction = n(),
              n_sites = sum(n_sites_in_cluster),
              n_groups_gt1 = sum(n_sites_in_cluster > 1),
              .groups = "drop") %>%
    filter(n_extraction >= 4, n_extraction <= 8, n_groups_gt1 >= 2,
           n_sites >= 2 * n_extraction, n_sites <= 40) %>%
    arrange(desc(n_sites), wb_nhd_id) %>%
    slice(1)
  waterbody <- collect_example(
    cw = cw,
    focus = cw %>% filter(wb_nhd_id == wb_pick$wb_nhd_id,
                          cluster_basis == "waterbody"),
    radius = NULL, HUC4_manifest = HUC4_manifest, buffer = buffer, feature = "waterbody")

  # c) flowline with multiple extraction sites and a reduction ----------------
  # Stream and Ditch/Canal sites are grouped by flowline (never by waterbody), so
  # the example is the first candidate with no NHD waterbody in the map window
  fl_cands <- ex %>%
    filter(cluster_basis == "flowline", !is.na(fl_nhd_id),
           !is.na(fl_gnis_name), fl_gnis_name != "") %>%
    group_by(fl_nhd_id) %>%
    summarize(n_extraction = n(),
              n_sites = sum(n_sites_in_cluster),
              n_groups_gt1 = sum(n_sites_in_cluster > 1),
              .groups = "drop") %>%
    filter(n_extraction >= 3, n_extraction <= 6, n_groups_gt1 >= 2,
           n_sites >= 2 * n_extraction, n_sites <= 40) %>%
    arrange(desc(n_sites), fl_nhd_id)
  flowline <- collect_flowline_example(fl_cands, cw = cw,
                                       HUC4_manifest = HUC4_manifest,
                                       buffer = buffer)

  # c2) a flowline with few sites, in an area with few other sites ------------
  # the example in (c) is in a corridor with many sites, which can make it hard
  # to see how the sites are grouped. Here, choose a flowline with a few sites
  # and few other sites nearby.
  fl_sparse_cand <- ex %>%
    filter(cluster_basis == "flowline", !is.na(fl_nhd_id),
           !is.na(fl_gnis_name), fl_gnis_name != "",
           !is.na(WGS84_Latitude)) %>%
    group_by(fl_nhd_id) %>%
    summarize(n_extraction = n(),
              n_sites = sum(n_sites_in_cluster),
              n_groups_gt1 = sum(n_sites_in_cluster > 1),
              lon = mean(WGS84_Longitude),
              lat = mean(WGS84_Latitude),
              .groups = "drop") %>%
    filter(n_extraction >= 3, n_extraction <= 4, n_groups_gt1 >= 2,
           n_sites >= 6, n_sites <= 12)
  # number of other RS-visible sites within 3 buffer radii of the center of the
  # candidate's sites (approximate planar coordinates, only used to pick the
  # example)
  all_xy <- cbind(cw$WGS84_Longitude * cos(cw$WGS84_Latitude * pi / 180) * 111320,
                  cw$WGS84_Latitude * 110540)
  cand_xy <- cbind(fl_sparse_cand$lon * cos(fl_sparse_cand$lat * pi / 180) * 111320,
                   fl_sparse_cand$lat * 110540)
  near <- RANN::nn2(all_xy, cand_xy, k = 500, searchtype = "radius",
                    radius = 3 * buffer)
  fl_sparse_cand$n_near <- rowSums(near$nn.idx > 0)
  fl_sparse_cands <- fl_sparse_cand %>%
    # `n_near` includes the candidate's own sites
    mutate(n_other = n_near - n_sites) %>%
    arrange(n_other, desc(n_sites), fl_nhd_id)
  flowline_sparse <- collect_flowline_example(fl_sparse_cands, cw = cw,
                                              HUC4_manifest = HUC4_manifest,
                                              buffer = buffer)

  # d) ungrouped sites that are close to other ungrouped sites ----------------
  singles <- ex %>%
    filter(n_sites_in_cluster == 1, cluster_basis %in% c("waterbody", "flowline"),
           !is.na(WGS84_Latitude)) %>%
    mutate(feat = coalesce(wb_nhd_id, fl_nhd_id))
  # approximate planar coordinates (m) for a neighbor count. Only used to pick
  # the example.
  xy <- cbind(singles$WGS84_Longitude * cos(singles$WGS84_Latitude * pi / 180) * 111320,
              singles$WGS84_Latitude * 110540)
  nn <- RANN::nn2(xy, k = 12, searchtype = "radius", radius = 3 * buffer)
  singles$n_near <- rowSums(nn$nn.idx > 0) - 1
  singles$n_features_near <- map_int(seq_len(nrow(singles)), \(i) {
    idx <- nn$nn.idx[i, ]
    n_distinct(singles$feat[idx[idx > 0]])
  })
  single_id <- singles %>%
    filter(n_near >= 3) %>%
    arrange(desc(n_features_near), desc(n_near), siteSR_id) %>%
    slice(1) %>%
    pull(siteSR_id)
  singletons <- collect_example(
    cw = cw,
    focus = cw %>% filter(siteSR_id == single_id),
    radius = 700, HUC4_manifest = HUC4_manifest, buffer = buffer, focus_all = TRUE,
    highlight = FALSE,
    feature = if_else(!is.na(cw$wb_nhd_id[cw$siteSR_id == single_id]) &
                        cw$cluster_basis[cw$siteSR_id == single_id] == "waterbody",
                      "waterbody", "flowline"))

  # summaries ---------------------------------------------------------------
  by_basis <- cw %>%
    group_by(cluster_basis) %>%
    summarize(sites = n(),
              extraction_sites = n_distinct(extraction_siteSR_id),
              .groups = "drop") %>%
    mutate(reduction_pct = round(100 * (1 - extraction_sites / sites), 1))

  by_type <- cw %>%
    group_by(harmonized_site_type) %>%
    summarize(sites = n(),
              extraction_sites = n_distinct(extraction_siteSR_id),
              .groups = "drop") %>%
    mutate(reduction_pct = round(100 * (1 - extraction_sites / sites), 1))

  list(largest = largest,
       largest_waterbody = largest_waterbody,
       waterbody = waterbody,
       flowline = flowline,
       flowline_sparse = flowline_sparse,
       singletons = singletons,
       summary = list(
         n_sites = nrow(cw),
         n_extraction = n_distinct(cw$extraction_siteSR_id),
         by_basis = by_basis,
         by_type = by_type,
         cluster_sizes = ex %>% select(siteSR_id, n_sites_in_cluster, cluster_basis),
         distances = cw %>%
           filter(role == "grouped") %>%
           select(siteSR_id, dist_to_extraction_site_m, cluster_basis)
       ))

}


#' @title Collect the map data for a single example
#'
#' @param cw tibble, the crosswalk joined to site information
#' @param focus rows of `cw` for the sites the example is about
#' @param radius numeric radius (m) of the map window around the focus sites'
#' centroid, or `NULL` to size the window to the focus sites (and, for a
#' waterbody, the waterbody)
#' @param HUC4_manifest tibble from `get_bestres_manifest()`
#' @param buffer numeric, the GEE buffer radius in meters
#' @param feature one of "waterbody" or "flowline", which NHD feature is
#' highlighted
#' @param focus_all logical, if TRUE all of the sites in the window are treated
#' as part of the example (not faded as context)
#' @param highlight logical, whether the feature is highlighted in the map. The
#' feature is still used for the title.
#'
#' @returns list of {sf} objects in a local UTM zone: `sites` (all visible
#' sites in the window, with the example's sites flagged as `focus`),
#' `links` (lines from grouped sites to their extraction site), `buffers`
#' (extraction site buffers), `wb` and `fl` (NHD features in the window, with
#' the highlighted feature flagged `focus`) and the window `bbox`.
#'
collect_example <- function(cw, focus, radius = NULL, HUC4_manifest, buffer = 200,
                            feature = c("waterbody", "flowline"),
                            focus_all = FALSE,
                            highlight = TRUE) {

  feature <- match.arg(feature)

  ctr <- c(mean(focus$WGS84_Longitude), mean(focus$WGS84_Latitude))
  utm <- if_else(ctr[2] >= 0, 32600L, 32700L) +
    as.integer(floor((ctr[1] + 180) / 6) + 1)

  to_sf <- function(df) {
    df %>%
      st_as_sf(coords = c("WGS84_Longitude", "WGS84_Latitude"),
               crs = 4326, remove = FALSE) %>%
      st_transform(utm)
  }

  focus_sf <- to_sf(focus)

  # NHD features ---------------------------------------------------------------
  huc4 <- str_sub(names(sort(table(focus$assigned_HUC), decreasing = TRUE))[1], 1, 4)
  gpkg <- download_bestres_gpkg(huc4, HUC4_manifest)

  focus_id <- if (feature == "waterbody") unique(focus$wb_nhd_id) else unique(focus$fl_nhd_id)
  focus_id <- focus_id[!is.na(focus_id)]

  # window: a circle around the focus sites, or the extent of the sites padded
  # (and of the waterbody, which is read first)
  if (!is.null(radius)) {
    win <- st_bbox(st_buffer(st_union(focus_sf), radius))
  } else {
    win <- st_bbox(st_buffer(st_union(focus_sf), 0.25 * buffer))
    if (feature == "waterbody") {
      wb_focus <- read_nhd_layer(gpkg, "NHDWaterbody", id = focus_id, utm = utm)
      win <- st_bbox(st_union(st_as_sfc(win), st_as_sfc(st_bbox(wb_focus))))
    }
    # a little extra room for the buffers
    pad <- 1.5 * buffer
    win[c("xmin", "ymin")] <- win[c("xmin", "ymin")] - pad
    win[c("xmax", "ymax")] <- win[c("xmax", "ymax")] + pad
  }
  win_sfc <- st_as_sfc(win)

  wb <- read_nhd_layer(gpkg, "NHDWaterbody", window = win_sfc, utm = utm,
                       where = "ftype IN (390, 436, 493)") %>%
    mutate(focus = highlight & permanent_identifier %in% focus_id & feature == "waterbody")
  fl <- read_nhd_layer(gpkg, "NHDFlowline", window = win_sfc, utm = utm) %>%
    mutate(focus = highlight & permanent_identifier %in% focus_id & feature == "flowline")

  # all visible sites in the window --------------------------------------------
  sites_in_win <- cw %>%
    filter(!is.na(WGS84_Latitude),
           between(WGS84_Longitude, ctr[1] - 0.05, ctr[1] + 0.05),
           between(WGS84_Latitude, ctr[2] - 0.05, ctr[2] + 0.05)) %>%
    to_sf() %>%
    .[st_intersects(., win_sfc, sparse = FALSE)[, 1], ] %>%
    mutate(focus = focus_all | siteSR_id %in% focus$siteSR_id)

  # the extraction site for every group that has a member in the window might be
  # outside of the window. include it so that every group is drawn completely.
  missing_ex <- setdiff(sites_in_win$extraction_siteSR_id, sites_in_win$siteSR_id)
  if (length(missing_ex) > 0) {
    sites_in_win <- bind_rows(
      sites_in_win,
      cw %>% filter(siteSR_id %in% missing_ex) %>% to_sf() %>% mutate(focus = FALSE))
  }

  # a group is part of the example if its extraction site is
  focus_ex <- sites_in_win %>%
    filter(focus | focus_all) %>%
    pull(extraction_siteSR_id)
  sites_in_win <- sites_in_win %>%
    mutate(focus = focus | extraction_siteSR_id %in% focus_ex)
  extraction_sites <- sites_in_win %>% filter(role == "extraction")

  links <- sites_in_win %>%
    filter(role == "grouped", dist_to_extraction_site_m > 0) %>%
    st_drop_geometry() %>%
    select(siteSR_id, extraction_siteSR_id) %>%
    left_join(sites_in_win %>% select(siteSR_id, geometry) %>%
                rename(from = geometry), by = "siteSR_id") %>%
    left_join(extraction_sites %>% select(extraction_siteSR_id = siteSR_id, geometry) %>%
                rename(to = geometry), by = "extraction_siteSR_id")
  if (nrow(links) > 0) {
    links <- links %>%
      mutate(geometry = map2(from, to, \(a, b) st_cast(st_union(a, b), "LINESTRING")) %>%
               st_sfc(crs = utm)) %>%
      select(siteSR_id, extraction_siteSR_id, geometry) %>%
      st_as_sf()
  } else {
    links <- NULL
  }

  # name of the feature (for the title) and the nearest city and state
  focus_name <- if (feature == "waterbody") focus$wb_gnis_name else focus$fl_gnis_name
  focus_name <- unique(focus_name[!is.na(focus_name) & focus_name != ""])[1]
  if (is.na(focus_name)) {
    focus_name <- paste("Unnamed", if (feature == "waterbody") "waterbody" else "flowline")
  }
  location <- nearest_place(lon = ctr[1], lat = ctr[2])

  list(sites = sites_in_win,
       links = links,
       buffers = st_buffer(extraction_sites %>% filter(focus), buffer),
       wb = wb,
       fl = fl,
       bbox = win,
       crs = utm,
       n_sites_focus = nrow(focus),
       n_extraction_focus = n_distinct(focus$extraction_siteSR_id),
       focus_name = focus_name,
       focus_basis = unique(focus$cluster_basis),
       focus_type = unique(focus$harmonized_site_type),
       location = location,
       title = if (is.na(location)) focus_name else paste0(focus_name, ", near ", location),
       focus_extraction_id = unique(focus$extraction_siteSR_id)[1])

}


#' @title Read an NHD layer for a map window
#'
#' @param gpkg path to the NHD HUC4 geopackage
#' @param layer name of the layer
#' @param id `permanent_identifier` to read (only this feature), or NULL
#' @param window {sf} geometry (in `utm`) of the window to read, or NULL
#' @param utm EPSG code of the CRS to return
#' @param where optional SQL `WHERE` clause to add
#'
#' @returns {sf} object in `utm` with the `permanent_identifier`, `gnis_name`,
#' and `ftype` columns
#'
read_nhd_layer <- function(gpkg, layer, id = NULL, window = NULL, utm,
                           where = NULL) {

  lyr_crs <- st_layers(gpkg)$crs[[which(st_layers(gpkg)$name == layer)]]

  clauses <- c(where,
               if (!is.null(id)) paste0("permanent_identifier IN (",
                                        paste0("'", id, "'", collapse = ","), ")"))
  q <- paste0("SELECT permanent_identifier, gnis_name, ftype, SHAPE FROM ", layer,
              if (length(clauses) > 0) paste0(" WHERE ", paste(clauses, collapse = " AND ")))

  wkt <- if (!is.null(window)) {
    window %>% st_transform(st_crs(lyr_crs)) %>% st_as_text()
  } else {
    NA_character_
  }

  out <- if (is.na(wkt)) {
    st_read(gpkg, query = q, quiet = TRUE)
  } else {
    st_read(gpkg, query = q, wkt_filter = wkt, quiet = TRUE)
  }

  out %>%
    st_zm() %>%
    st_make_valid() %>%
    mutate(permanent_identifier = as.character(permanent_identifier)) %>%
    st_transform(utm)

}


#' @title Find the nearest city and state for a location
#'
#' @description
#' Looks up the state containing a point and the nearest incorporated or census
#' designated place in that state from the US Census Bureau cartographic
#' boundary files, using {tigris}. If the lookup fails (e.g. no internet
#' connection) `NA` is returned and the example is titled without a place.
#'
#' @param lon,lat numeric, WGS84 coordinates
#'
#' @returns character string "Place, ST", or `NA_character_`
#'
nearest_place <- function(lon, lat) {

  tryCatch({
    old_opts <- options(tigris_use_cache = TRUE)
    on.exit(options(old_opts), add = TRUE)
    pt <- st_sfc(st_point(c(lon, lat)), crs = 4269)

    states <- tigris::states(cb = TRUE, year = 2022, progress_bar = FALSE)
    st_row <- states[st_intersects(states, pt, sparse = FALSE)[, 1], ]
    if (nrow(st_row) == 0) {
      # e.g. points just offshore
      st_row <- states[st_nearest_feature(pt, states), ]
    }
    abbr <- st_row$STUSPS[1]

    places <- tigris::places(state = abbr, cb = TRUE, year = 2022,
                             progress_bar = FALSE)
    place <- places[st_nearest_feature(pt, places), ]
    paste0(place$NAME[1], ", ", abbr)
  }, error = function(e) NA_character_)

}


#' @title Collect a flowline example that is not near a waterbody
#'
#' @description
#' Stream and Ditch/Canal sites are grouped by NHD flowline, never by waterbody.
#' To avoid suggesting otherwise, return the first candidate (in the order given)
#' for which no NHD waterbody (lake, pond, reservoir, or estuary polygon) falls
#' within the map window and the window is roughly square (height/width between
#' 0.6 and 1.4). If there is none among the first `max_tries`
#' candidates, the first candidate is returned with a warning.
#'
#' @param candidates tibble with `fl_nhd_id`, in order of preference
#' @param cw tibble, the crosswalk joined to site information
#' @param HUC4_manifest tibble from `get_bestres_manifest()`
#' @param buffer numeric, the GEE buffer radius in meters
#' @param max_tries maximum number of candidates to check
#'
#' @returns output of `collect_example()`
#'
collect_flowline_example <- function(candidates, cw, HUC4_manifest, buffer,
                                     max_tries = 50) {

  first <- NULL
  for (i in seq_len(min(nrow(candidates), max_tries))) {
    out <- collect_example(
      cw = cw,
      focus = cw %>% filter(fl_nhd_id == candidates$fl_nhd_id[i],
                            cluster_basis == "flowline"),
      radius = NULL, HUC4_manifest = HUC4_manifest, buffer = buffer,
      feature = "flowline")
    if (is.null(first)) first <- out
    # also require a map window that is not extremely tall or wide
    aspect <- (out$bbox[["ymax"]] - out$bbox[["ymin"]]) /
      (out$bbox[["xmax"]] - out$bbox[["xmin"]])
    if (nrow(out$wb) == 0 && between(aspect, 0.6, 1.4)) return(out)
  }
  warning("No flowline example without a waterbody and a roughly square map ",
          "window was found ",
          "in the first ", max_tries, " candidates.")
  first

}
