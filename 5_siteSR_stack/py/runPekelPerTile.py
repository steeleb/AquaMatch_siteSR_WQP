#import modules
import ee
import os 
import time
from pandas import read_csv
import numpy as np

# LOAD ALL THE CUSTOM FUNCTIONS -----------------------------------------------

def csv_to_eeFeat(df, proj):
  """Function to create an eeFeature from the location info

  Args:
      df: point locations .csv file with Latitude and Longitude
      proj: CRS projection of the points

  Returns:
      ee.FeatureCollection of the points 
  """
  features=[]
  for i in range(df.shape[0]):
    x,y = df.Longitude.iloc[i],df.Latitude.iloc[i]
    latlong = [x,y]
    loc_properties = ({'system:index':str(df.id.iloc[i]), 
                      'id':str(df.id.iloc[i])})
    g = ee.Geometry.Point(latlong, proj) 
    feature = ee.Feature(g, loc_properties)
    features.append(feature)
  return ee.FeatureCollection(features)


# pull using AquaSat V1 code from MR
def get_occurrence(point):
  """ Function to buffer a point and pull summary statistics for Pekel water ocurrence
  
  Args:
    point: earth engine point feature to extract Pekel summaries for
    
  Returns:
    out: earth engine point feature with max, min, median summaries for Pekel occurrence
  """
  # Define a buffer around each point, buffer must be hardcoded here, for unknown
  # reasons
  buff_point = ee.Feature(point).buffer(200).geometry() 
  # Clip the pekel mask to this buffer
  pekclip = pekel.clip(buff_point)
  # Reduce the buffer to pekel min and max
  pekMM = pekclip.reduceRegion(ee.Reducer.minMax(), buff_point, 30)
  # Add another reducer to get the median pekel occurnce
  pekMed = pekclip.reduceRegion(ee.Reducer.median(), buff_point, 30)
  # Define the output features
  out = (point.set({'occurrence_max': pekMM.get('occurrence_max')})
              .set({'occurrence_min': pekMM.get('occurrence_min')})
              .set({'occurrence_med': pekMed.get('occurrence')}))
  return out


def maximum_no_of_tasks(MaxNActive, waitingPeriod):
  """ Function to limit the number of tasks sent to Earth Engine at one time to avoid time out errors
  
  Args:
      MaxNActive: maximum number of tasks that can be active in Earth Engine at one time
      waitingPeriod: time to wait between checking if tasks are completed, in seconds
      
  Returns:
      None.
  """
  ## maintain a maximum number of active tasks
  ## initialize submitting jobs
  ts = list(ee.batch.Task.list())
  NActive = 0
  for task in ts:
     if ('RUNNING' in str(task) or 'READY' in str(task)):
         NActive += 1
  ## wait if the number of current active tasks reach the maximum number
  ## defined in MaxNActive
  while (NActive >= MaxNActive):
    time.sleep(waitingPeriod) # if reach or over maximum no. of active tasks, wait for 2min and check again
    ts = list(ee.batch.Task.list())
    NActive = 0
    for task in ts:
      if ('RUNNING' in str(task) or 'READY' in str(task)):
        NActive += 1
  return()


# get locations and yml from data folder
yml = read_csv('5_siteSR_stack/run/yml.csv')

eeproj = yml['ee_proj'][0]
#initialize GEE
ee.Initialize(project = eeproj)

# get current tile
with open('5_siteSR_stack/run/current_tile.txt', 'r') as file:
  tile = file.read()

# get EE/Google settings from yml file
proj = yml['proj'][0]
proj_folder = yml['proj_folder'][0]

run_date = yml['run_date'][0]

# gee processing settings
site_buffer = yml['site_buffer'][0]

# get extent info
extent = (yml['extent'][0]
  .split('+'))

if 'site' in extent:
  locations = (read_csv('5_siteSR_stack/run/locs_with_WRS.csv', 
                        dtype = ({"id": np.int32, 
                                  "Latitude": np.float64, 
                                  "Longitude": np.float64, 
                                  "WRSPR": str})))
  filtered_locs = locations[locations['WRSPR'] == tile]
  # convert locations to an eeFeatureCollection
  locs_feature = csv_to_eeFeat(filtered_locs, yml['location_crs'][0])


##############################################
##---- GET EE FEATURE COLLECTIONS       ----##
##############################################

# get newest version of pekel
# Jean-Francois Pekel, Andrew Cottam, Noel Gorelick, Alan S. Belward, 
# High-resolution mapping of global surface water and its long-term changes. 
# Nature 540, 418-422 (2016). (doi:10.1038/nature20584)
pekel = (ee.Image("JRC/GSW1_4/GlobalSurfaceWater")
  .select("occurrence"))

# Map this function over the 5000 or so created sites
outdata = locs_feature.map(get_occurrence)
#Define a data export 
dataOut = (ee.batch.Export.table.toDrive(collection = outdata,
                                        description = "Pekel_Visibility_" + str(tile),
                                        folder = proj_folder,
                                        fileFormat = 'csv'))

# check for number of tasks running
maximum_no_of_tasks(20, 60)

# send next task if there isn't too much in the queue!
dataOut.start()


