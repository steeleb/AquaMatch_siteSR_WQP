# Target list to match SR product with harmonized AquaMatch products


# Source targets functions ------------------------------------------------

tar_source(files = "7_siteSR_matchup/src/")


# Define {targets} workflow -----------------------------------------------

# target objects in workflow
p7_siteSR_matchup <- list(
  # # make directories if needed
  # tar_target(
  #   name = p6_check_dir_structure,
  #   command = {
  #     directories = c("6_siteSR_stack/mid/",
  #                     "6_siteSR_stack/out/",
  #                     "6_siteSR_stack/out_files/",
  #                     "6_siteSR_stack/down/")
  #     
  #     walk(directories, function(dir) {
  #       if(!dir.exists(dir)){
  #         dir.create(dir)
  #       }
  #     })
  #   },
  #   cue = tar_cue("always"),
  #   priority = 1
  # ),
  

  # Load harmonized data files ----------------------------------------------
  # eventually this will grab from EDI, for now, we'll grab the feather from 
  # the harmonize pipeline
  
  # chlorophyll data
  tar_file_read(
    name = p7_chla_harmonized_data,
    command = {
      if (grepl("chla",  p0_siteSR_config$parameter)) {
        "../AquaMatch_harmonize_WQP/3_harmonize/out/chla_harmonized_grouped.feather"
      } else {
        NULL
      }
    },
    read = read_feather(!!.x),
    packages = "feather"
  ),
  
  # SDD data
  tar_file_read(
    name = p7_sdd_harmonized_data,
    command = {
      if (grepl("sdd", p0_siteSR_config$parameter)) {
        "../AquaMatch_harmonize_WQP/3_harmonize/out/sdd_harmonized_group.feather"
      } else {
        NULL
      }
    },
    read = read_feather(!!.x),
    packages = "feather"
  )
)
  