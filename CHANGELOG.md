# Changelog

All notable changes to this repository are documented in this file. Releases
are tagged by date (`vYYYY-MM-DD`) rather than semantic version, matching this
repo's [GitHub releases](https://github.com/AquaSat/AquaMatch_siteSR/releases).
The bookdown that documents this workflow is in the
[AquaMatch_lakeSR](https://github.com/AquaSat/AquaMatch_lakeSR) repository
(`bookdown/`); changes to it are noted below.

## [Unreleased]

### Added
- **One combined Earth Engine export per mission group and chunk** summarizes all
  configured DSWE variants (`DSWEcombo1-1a`, etc.), aligned with the lakeSR pull
  (`c_siteSR_stack/py/run_siteSR_per_pathrow.py`). Downloaded files are split
  into per-variant files by the new `c_siteSR_stack/src/split_combined_dswe.R`
  (target `c_split_combined_files`) before collation. Locations are sorted
  spatially before chunking, the hillshadow neighborhood is 100 pixels, the
  LS89 aerosol band is no longer used to screen for unrealistic values, and
  scene-level cloud filtering follows the `cloud_filter` config setting.
  Optional overrides to run outside of {targets}: `SITESR_YML_CSV`,
  `SITESR_PATHROW_FILE`.
- `python/pySetup.R` rewritten (from lakeSR) so a missing or empty `env/` is
  actually (re)built; Python 3.12 with pinned `earthengine-api`, `pandas`,
  `numpy`, `pyyaml` versions; dropped the unused `pyreadr`.

- **Sites with overlapping buffers are grouped before Earth Engine extraction**
  to reduce redundant EECU use (new `c_siteSR_stack/src/cluster_sites_for_GEE.R`;
  new targets `c_site_crosswalk` and `c_extraction_sites` in
  `c_siteSR_stack.R`). After the remote sensing visibility check, RS-visible
  sites are grouped when (1) the buffers (`site_buffer`, 200 m) of every pair
  of sites in the group overlap by at least `overlap_threshold` percent of the
  buffer area (75%, or sites within ~79 m of each other) and (2) the sites are
  attributed to the same NHD waterbody (`wb_nhd_id`, Lake/Reservoir and Pond
  sites) or the same NHD flowline (`fl_nhd_id`, Stream and Ditch/Canal sites),
  regardless of `flag_wb`/`flag_fl`. Lake/Pond and Stream/Canal sites without an
  assigned feature are not grouped; Estuary and Other sites are grouped with
  sites of the same `harmonized_site_type`. Only one site per group, the
  "extraction site", is sent to GEE. The extraction site is a member of its group
  (so acquired data stay keyed to a real `siteSR_id`), chosen as the member with
  the best `flag_wb`/`flag_fl`, then the medoid, then the lowest `siteSR_id`.
  Groups are built greedily from a deterministic spatial ordering, so that the
  groups are reproducible, using {RANN} for the neighbor search (new package
  dependency).
- **Extraction site crosswalk file**
  (`d_qa_stack/export/siteSR_extraction_site_crosswalk_v[run_date].csv`, new
  target `d_site_crosswalk_file`, shared with the other `d_qa_stack` export
  files): one row for every RS-visible `siteSR_id` with `extraction_siteSR_id`,
  `n_sites_in_cluster`, `cluster_basis` (waterbody, flowline,
  location_and_type, unclustered), `dist_to_extraction_site_m`, and the NHD
  assignment and shoreline flags and distances at the extraction site
  (`extraction_flag_wb`, `extraction_flag_fl`, `extraction_dist_to_shore`,
  `extraction_dist_to_fl`, `extraction_flag_optical_shoreline`,
  `extraction_flag_thermal_TM/ETM/TIRS_shoreline`). The flags describe the area
  summarized in GEE, so the extraction site's flags apply to every site in the
  group. Data files contain data only for extraction sites; join through the
  crosswalk to get data for all sites. Only created when `run_GEE` is TRUE.
- **Site-grouping examples for the lakeSR bookdown** (new
  `c_siteSR_stack/src/make_crosswalk_examples.R`; new targets
  `c_crosswalk_examples`, `c_export_crosswalk_examples`, and
  `c_crosswalk_examples_Drive_id`, only when `run_GEE` is TRUE). Selects example
  groups by rule from `c_site_crosswalk` and collects the NHD geometries for
  them, then exports the (small) result to Drive for the lakeSR workflow.
  `a_remove_NHD_gpkg` now depends on `c_crosswalk_examples` when `run_GEE` is
  TRUE, so the NHD GeoPackages are removed only after the examples are made.
- `overlap_threshold` setting in the `config.yml` (percent; 75). If missing, 75 is used.
- **NHD Best Resolution manifest and GeoPackage download**
  (`a_compile_sites/src/get_bestres_manifest.R`,
  `a_compile_sites/src/download_bestres_gpkg.R`; targets `a_HUC4_manifest`,
  `a_save_HUC4_manifest`, `a_HUC4_gpkg`): lists every NHD Best Resolution HU4
  GeoPackage on The National Map with its last-modified date and ETag, saves it
  as `a_compile_sites/out/siteSR_NHD_manifest_[collated_site_version].csv`, and
  downloads each HUC4's GeoPackage once before the branches that read it. A
  GeoPackage whose ETag differs from the manifest stops the run, so the NHD
  files are fixed for a version of the site list (to use updated files, run
  `tar_invalidate(a_HUC4_manifest)`). `a_remove_NHD_gpkg` removes the
  GeoPackages once all sites have been attributed.
- `a_sites_by_HUC4`: sites regrouped by HUC4 with only the columns needed for
  NHD assignment, so each waterbody/flowline branch loads only its HUC4.
- `a_compile_sites/src/set_local_utm.R` and `distance_to_nearest_feature.R`:
  spatial operations in a local UTM zone using planar geometry (faster and
  lighter than s2 for large NHD layers), and distance to the paired feature
  processed once per feature.
- `a_compile_sites/src/clean_text_fields.R`: removes double quotes, control
  characters (including line breaks) and extra whitespace from text fields.
- **Sites from the AquaMatch colored dissolved organic matter and water color
  harmonization pipelines** (targets `a_AquaMatch_cdom_sites`,
  `a_AquaMatch_wc_sites`; `a_compile_sites/in/cdom_drive_ids.csv`,
  `wc_drive_ids.csv`) in addition to chlorophyll *a*, dissolved organic carbon,
  Secchi disc depth, and total suspended solids. The TSS Drive IDs were
  updated, and `a_compile_sites/in/readme.md` was updated to note the 2026-10-26
  copy date.
- A second {crew} controller (`nhd`, three workers) for the NHD waterbody and
  flowline assignment targets, which read large GeoPackages (up to ~1 million
  flowlines per HUC4) and can use 5-20 GB each (`_targets.R`).
- `bookdown` (in AquaMatch_lakeSR): new section "Grouping sites to reduce
  redundant extraction" in `02-Data_Acquisition_Locations.Rmd`; descriptions of
  the grouping, the crosswalk file, `overlap_threshold`, and the new site
  sources in `01-Background.Rmd`; {hydrogeofetch} and {RANN} added to the
  package table in `03-Acquisition_Software_Settings.Rmd` and `references.bib`.

### Changed
- **`pCount_ir_glint` is dropped from the exported data**
  (`d_qa_stack/src/sort_qa_Landsat_data.R`). It counts pixels where Nir, Swir1,
  *and* Swir2 are all >= 0.1, which essentially never occurs in DSWE water, so it
  is 0 in every record. It is still calculated in Earth Engine (so it remains in
  `c_siteSR_stack/mid` and `d_qa_stack/qa`) but is not exported. The per-band
  `pCount_nir_ir_glint`, `pCount_swir1_ir_glint`, and `pCount_swir2_ir_glint`
  columns are retained. `pCount_ir_glint` values in previous releases are not
  comparable and should not be used.
- **The `pCount_*` mask diagnostic columns are retained in the exported data**
  (`d_qa_stack/src/sort_qa_Landsat_data.R`). Columns ending in `val`, `glint`,
  `thresh`, `zero`, `opac`, and `aero` were previously dropped from the HUC2
  `.csv` files because they did not tally correctly (#39, #40); the tallies are
  fixed (see Fixed), and the columns are sparsely populated by design (most
  values are 0 or missing), so all are kept except `pCount_ir_glint` (below). `.csv` and `.feather` files in
  `d_qa_stack/export` and `d_qa_stack/out` have more columns than in
  v2025-06-06 and are larger.
- **Ditch/Canal sites are treated like River/Stream sites for flowline
  assignment** (`a_compile_sites/src/add_NHD_flowline_to_sites.R`): flowline
  info is removed (`flag_fl` = 3) when the nearest flowline is > 500 m away.
- `run_targets.Rmd` package installer now includes `RANN`, `googledrive`,
  `data.table`, `dataRetrieval`, `curl`, `ggrepel`, `viridis`, and `stringi`.
- README updated for NHD Best Resolution, `clean_text_fields()`, and the
  `d_qa_stack` group.
- **NHD waterbody and flowline assignment uses NHD Best Resolution for all
  HUC4s** (`a_compile_sites/src/add_NHD_waterbody_to_sites.R`,
  `add_NHD_flowline_to_sites.R`, `a_compile_sites.R`). Previously, NHDPlusV2 was
  used for CONUS and NHD Best Resolution outside of CONUS. Branches are now one
  per HUC4 (`pattern = map(a_sites_by_HUC4)`) instead of every HUC4 crossed with
  every source/site type group (which loaded up to ~700k sites per branch and
  exhausted memory when branches ran in parallel); the flowline layer is read
  with a filtered query; and intersections, nearest feature, distances, and
  buffers are calculated in a local UTM zone. `wb_nhd_source` and
  `fl_nhd_source` are `NHDBestRes` for all sites in new runs. Flag definitions
  are unchanged.
- HUC8 assignment (`a_compile_sites/src/add_HUC8_to_sites.R`) intersects only
  the site point geometries with the WBD HUC8 polygons in planar geometry and
  keeps the first HUC8 for sites on a boundary, rather than joining the full
  site table to the national polygons (which used several GB per branch and
  crashed {crew} workers). The files of sites unable to be assigned a HUC8 are
  now named by source and harmonized site type
  (`a_compile_sites/out/failed_HUC/[source]_[site type]_sites_unable_to_assign_HUC08.csv`).
- {nhdplusTools} was replaced by {hydrogeofetch} (the renamed package) in
  `a_compile_sites.R` and `run_targets.Rmd`.
- `d_unique_huc2` in `d_qa_stack.R` uses the extraction sites
  (`c_extraction_sites`) to define the HUC2s to process. When `run_GEE` is
  FALSE, `c_extraction_sites` is `b_visible_sites`, since previously-collated
  data were acquired for all RS-visible sites.
- The siteSR location pipeline in the `admin_update` profile of `config.yml`
  writes to the `aquamatch_siteSR_wqp_2026` Drive folder, with
  `collated_site_version` 2026-10-26.
- `run_targets.Rmd`: package list and configuration description formatting.
- `README.md`: documents the grouping of sites before acquisition.
- `c_siteSR_stack/src/check_if_fully_within_pr.R` documentation updated for
  `c_extraction_sites`. Note that the path-row containment check is applied to
  the extraction site, so a site that is not in a path-row that contains the
  extraction site's buffer may have no data from that path-row.
- Full re-run of {targets} groups -a- through -d- is required to use these
  changes; the bookdown values will update once the siteSR data are re-run.

### Fixed
- **Landsat 8/9 aerosol mask was inverted** (#47, #66;
  `c_siteSR_stack/py/run_siteSR_per_pathrow.py`): `add_sr_aero_mask` returns 1
  for climatology/low aerosol, but the Landsat 8/9 pull took `.eq(0)` of it, so
  medium/high-aerosol pixels were *kept* and climatology/low-aerosol pixels were
  masked. The pull now takes `.eq(1)`, so medium/high-aerosol pixels are masked
  as documented. `pCount_high_aero` was inverted in the same way and now counts
  medium/high-aerosol pixels. All Landsat 8/9 summaries in previous releases
  (e.g. v2025-06-06) are affected; Landsat 4, 5, and 7 (atmospheric opacity
  mask) are not. Comparing the 2025-06-06 and 2026-10-29 runs at the same
  locations (DSWE1, scenes through 2024-12-30), Landsat 5/7 records are 98.5%
  common to both runs with identical band values, while only ~30% of Landsat
  8/9 site-scene records are common, mean `prop_clouds` falls from ~0.065 to
  ~0.017, and the share of records with a negative median Aerosol band falls
  from ~8.5% to ~0.9%. This is the same fix as in AquaMatch_lakeSR.
- **`prop_hillShadow` was inverted** (`run_siteSR_per_pathrow.py`): it was the
  mean of the `ee.Terrain.hillShadow` band (1 = illuminated), so it reported the
  proportion of the buffer that was *illuminated*, not shaded as documented. The
  band is now inverted before the reduction. Values in previous releases equal 1
  minus the documented value. This is a diagnostic tally only; masking of
  summarized pixels was not affected.
- **`pCount_unreal_val` and `pCount_sun_glint` were always 0**
  (`run_siteSR_per_pathrow.py`): they were tallied after the pixels they count
  had already been masked, so were 0 in every record of the 2025-06-06 data.
  The `pCount_*`
  diagnostic tallies (`high_aero`/`high_opac`, `unreal_val`, `sun_glint`,
  `ir_glint`, and the per-band `*_zero`, `*_thresh`, `*_glint`, and `*_ir_glint`
  columns) are now restricted to the DSWE water area for each variant after the
  hillshadow, cloud, and opacity/aerosol masks. Values are not comparable to
  previous releases.
- **UTM EPSG code was wrong for Alaska and Hawaii** in
  `c_siteSR_stack/src/check_if_fully_within_pr.R`: the code was built as
  `paste0("EPSG:326", zone)`, so UTM zones 1-9 were projected to
  EPSG:3261-3269, which are not UTM zones, and the site buffer was drawn in
  the wrong CRS when checking containment in the path-row. It is now
  `32600 + zone` (`32700 + zone` in the southern hemisphere).
- **Unclosed double quotes in the site list failed EDI requirements** (#45):
  `clean_text_fields()` now removes double quotes and control characters from
  `org_id`, `loc_id`, and `MonitoringLocationTypeName` when sites are collated
  (sites that become duplicates after this cleaning are dropped) and from all
  character columns of `a_sites_with_NHD_info` before the site file is written.
  Previously, a patch (`a_all_site_locations_patch.Rmd`) was applied to the
  written file.
- Sites from the WQP without a latitude or longitude are dropped before the CRS
  harmonization (`a_harmonized_WQP_sites`).

## [v2026-01-28] - 2026-01-28
Patched a single unclosed double quote in the `loc_id` column of the collated
site list (`a_all_site_locations_patch.Rmd`, #45) and added the
2026-01-28 version of the file; the {targets} were unchanged.

## [v2026-01-16] - 2026-01-16
Revised the data usage and quality standards disclaimer.

[Unreleased]: https://github.com/AquaSat/AquaMatch_siteSR/compare/v2026-01-28...HEAD
[v2026-01-28]: https://github.com/AquaSat/AquaMatch_siteSR/releases/tag/v2026-01-28
[v2026-01-16]: https://github.com/AquaSat/AquaMatch_siteSR/releases/tag/v2026-01-16
