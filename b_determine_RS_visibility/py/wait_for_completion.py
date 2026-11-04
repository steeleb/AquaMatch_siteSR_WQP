import ee
from pandas import read_csv
import time

# get configs from yml file
yml = read_csv("b_determine_RS_visibility/run/yml.csv")
# assign proj
eeproj = yml["ee_proj"][0]
#initialize GEE with proj
ee.Initialize(project = eeproj)

# only track tasks created by this pipeline's pekel pull (see description in
# run_pekel_per_pathrow.py), so other projects' tasks (e.g. lakeSR) don't block us
task_prefix = "Pekel_Visibility_"

def count_active_pekel_tasks():
  # ee.batch.Task.list() returns all tasks for the project; filter by description
  # and only count those that are still queued or running
  n = 0
  for task in ee.batch.Task.list():
    desc = task.config.get("description", "")
    if desc.startswith(task_prefix) and task.state in ("READY", "RUNNING"):
      n += 1
  return n

n_active = count_active_pekel_tasks()
# loop to track if n_active is greater than zero
while (n_active > 0):
  # if it is, wait 2 minutes
  time.sleep(120)
  # and then repeat!
  n_active = count_active_pekel_tasks()

print('All Pekel tasks completed')
