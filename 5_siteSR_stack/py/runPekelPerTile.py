#import modules
import ee
import time
from datetime import date, datetime
import os 
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
    latlong =[x,y]
    loc_properties = {'system:index':str(df.id.iloc[i]), 'id':str(df.id.iloc[i])}
    g=ee.Geometry.Point(latlong, proj) 
    feature = ee.Feature(g, loc_properties)
    features.append(feature)
  return ee.FeatureCollection(features)

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
buffer = yml['site_buffer'][0]

# get extent info
extent = (yml['extent'][0]
  .split('+'))

if 'site' in extent:
  locations = read_csv('5_siteSR_stack/run/locs_with_WRS.csv', dtype = {"id": np.int32, "Latitude": np.float64, "Longitude": np.float64, "PR": str})
  filtered_locs = locations[locations['PR'] == tile]
  # convert locations to an eeFeatureCollection
  locs_feature = csv_to_eeFeat(filtered_locs, yml['location_crs'][0])

##############################################
##---- GET EE FEATURE COLLECTIONS       ----##
##############################################

wrs = (ee.FeatureCollection('projects/ee-ls-c2-srst/assets/WRS2_descending')
  .filterMetadata('PR', 'equals', tile))

wrs_path = int(tile[:3])
wrs_row = int(tile[-3:])

# get newest version of pekel
# Jean-Francois Pekel, Andrew Cottam, Noel Gorelick, Alan S. Belward, 
# High-resolution mapping of global surface water and its long-term changes. 
# Nature 540, 418-422 (2016). (doi:10.1038/nature20584)
pekel = (ee.Image("JRC/GSW1_4/GlobalSurfaceWater")
  .select("occurrence"))

# pull using V1 code from MR
def waterfunc(buf):
  #Define a 200m buffer around each point
  invBuf = buf.buffer(200).geometry()
  #Clip the pekel mask to this buffer
  pekclip = occ.clip(invBuf)
  #Reduce the buffer to pekel min and max
  pekMin = pekclip.reduceRegion(ee.Reducer.minMax(), invBuf, 30)
  #Add another reducer to get the median pekel occurnce
  pekMed = pekclip.reduceRegion(ee.Reducer.median(),invBuf,30)
  #Define the output features
  out = buf.set({'max':pekMin.get('occurrence_max')})\
          .set({'min':pekMin.get('occurrence_min')})\
          .set({'med':pekMed.get('occurrence')})
          
  return out

#Source function to limit number of tasks sent up to earth engine.
exec(open("2_rsdata/src/GEE_pull_functions.py").read())    
#Loop over the index stored in split
for x in range(0,len(splitStart)):
#turn our inventory into a feature collection by assigning lat longs and a site id.
#This is done via list comprehension which is similar to a for loop but faster and
#plays nice with earth engine.  Collections are limited for 5000 to avoid time outs
#on the server side.
  invOut = ee.FeatureCollection([ee.Feature(
    ee.Geometry.Point([inv['long'][i], inv['lat'][i]]),
    {'SiteID':inv['SiteID'][i]}) for i in range(splitStart[x], splitEnd[x])]) 
  #Map this function over the 5000 or so created sites
  outdata = invOut.map(waterfunc)
  #Define a data export 
  dataOut = ee.batch.Export.table.toDrive(collection = outdata,
                                          description = "LandsatSitePull" + str(x),
                                          folder='tempSiteWater',
                                          fileFormat = 'csv')
  #Send next task.
  dataOut.start()
#Make sure all Earth engine tasks are completed prior to moving on.  
maximum_no_of_tasks(1,60)
print('done')


