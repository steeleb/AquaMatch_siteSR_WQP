#import modules
import ee
import os 
import time
import pandas as pd
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
yml = pd.read_csv('5_siteSR_stack/run/yml.csv')

eeproj = yml['ee_proj'][0]
#initialize GEE
ee.Initialize(project = eeproj)

# get EE/Google settings from yml file
proj = yml['proj'][0]
proj_folder = yml['proj_folder'][0]

run_date = yml['run_date'][0]

# gee processing settings
site_buffer = yml['site_buffer'][0]

# get extent info
extent = (yml['extent'][0]
  .split('+'))

locations = (pd.read_csv('5_siteSR_stack/run/locs_with_WRS.csv', 
                        dtype = ({"id": np.int32, 
                                  "Latitude": np.float64, 
                                  "Longitude": np.float64, 
                                  "WRSPR": str})))

# the locations file above actually has dupes from overlapping WRSPRs, so just
# grab unique locs
locations_unique = locations.drop_duplicates(subset = "id", keep = "first")

##############################################
##---- GET EE FEATURE COLLECTIONS       ----##
##############################################

# get newest version of pekel
# Jean-Francois Pekel, Andrew Cottam, Noel Gorelick, Alan S. Belward, 
# High-resolution mapping of global surface water and its long-term changes. 
# Nature 540, 418-422 (2016). (doi:10.1038/nature20584)
pekel = (ee.Image("JRC/GSW1_4/GlobalSurfaceWater")
  .select("occurrence"))

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


# Map the get_occurrence function over the 5000 or so created sites
def process_subset(df_subset, chunk):
    """
    This function processes a subset of the DataFrame.
    Replace this with your actual processing function.
    """
    locs_feature = csv_to_eeFeat(df_subset, yml['location_crs'][0])

    outdata = locs_feature.map(get_occurrence)
    #Define a data export 
    dataOut = (ee.batch.Export.table.toDrive(collection = outdata,
                                            description = "Pekel_Visibility_" + str(chunk),
                                            folder = proj_folder,
                                            fileFormat = 'csv'))
    
    # check for number of tasks running
    maximum_no_of_tasks(20, 60)
    
    # send next task if there isn't too much in the queue!
    dataOut.start()
    
    return ()


def process_dataframe_in_chunks(df, chunk_size=5000):
    """
    Process a DataFrame in chunks of specified size.
    
    Args:
    df (pandas.DataFrame): The input DataFrame
    chunk_size (int): The number of rows in each chunk (default: 5000)
    
    Returns:
    list: A list of results from processing each chunk
    """
    results = []
    
    # Calculate the number of chunks
    num_chunks = len(df) // chunk_size + (1 if len(df) % chunk_size != 0 else 0)
    
    for i in range(num_chunks):
        # Calculate start and end indices for the current chunk
        start_idx = i * chunk_size
        end_idx = min((i + 1) * chunk_size, len(df))
        
        # Subset the DataFrame
        df_subset = df.iloc[start_idx:end_idx]
        
        # Process the subset and store the result
        result = process_subset(df_subset, i)
        results.append(result)
        
        print(f"Processed chunk {i+1}/{num_chunks}")
    
    return ()

# and then actualy process the chunks!
process_dataframe_in_chunks(locations_unique)
