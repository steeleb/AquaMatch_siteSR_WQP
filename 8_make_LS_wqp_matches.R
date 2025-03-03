# Targets list to gather Landsat stack at WQP site locations

# Source targets functions ------------------------------------------------

tar_source(files = "8_make_LS_wqp_matches/src/")


# Define {targets} workflow -----------------------------------------------

# target objects in workflow
p8_make_LS_wqp_matches <- list(
  
  tar_target(p8_)
  
)