
#%%
"""Add new methods to projects' methods: ReCiPe 2016 and BII
"""

## Imports
from brightway2 import *
from bw_recipe_2016 import add_recipe_2016
import pandas as pd
from sys import argv
import os

## Check projects and set current project
print(projects)

#args = argv[1:]
#args = ['PBM_March_2022']
projects.set_current(args[0])

print('Current project is ' + args[0])

## 1) Add ReCiPe 2016

print('Add ReCiPe 2016 to methods')
# add_recipe_2016() # call after selecting project; adds new recipe to biosphere
if [m for m in methods if 'ReCiPe 2016' in m[0]]:
    print('ReCiPe 2016 is already included')
else:
    print('Adding Recipe 2016 to methods')
    add_recipe_2016()

#%%
## 2) Add BII 
print('Add BII to methods')
## Extract all relevant flows from biosphere3 with their keys as a list and conver to dataframe
ToMap = []
for flow in Database('biosphere3'):
    if 'Occupation' in flow['name']:
        LandFlows = [
                flow['name'],
                flow['code']]
        ToMap.append(LandFlows)
        #print(flow.as_dict())

## Convert to dataframe
ToMap_df = pd.DataFrame(ToMap, columns=['Substance', 'code'])

#%%
## Get BII factors from Excel
#BII_df= pd.read_excel('E:/RELIEF/4_4_PaperMeals/1_Data/Mappings/Ecoinvent2BII_2021_01_12.xlsx')
BII_df= pd.read_excel('{}/888_InputData/Mappings/Ecoinvent2BII_2021_01_12.xlsx'.format(os.path.dirname(os.getcwd())))
## Join biosphere3 codes to relevant BII identifers

BII_df= BII_df.merge(ToMap_df, how = 'left', on = 'Substance')
### Note: 28 cases don't have a code match in biosphere3 ==> bad? are these even used in brightway/SimaPro?

## Define new CF mapping
CFs = []

for t in BII_df['code'].dropna().unique():
    #print(BII_df[BII_df['code'] == t]['Factor'])
    CF_tuple = (('biosphere3', t ),BII_df[BII_df['code'] == t]['Factor'].iloc[0] )
    CFs.append(CF_tuple)

#%% 
## Define the new method and add it to biosphere3

BII_land = Method(('BII', 'land'))

BII_land.register(**{
    'unit': 'm2 BII loss/m2a',
    'num_cfs':33,
    'abbreviation': 'nonexistent',
    'description': 'Biodiversity Intactness Index loss based on factors from Newbold et al. (2016)',
    'filename': 'nonexistent'
})

BII_land.write(CFs)
#%%
## Let's try an LCA
"""
print('Running a test LCA')
#db = Database('pbm_All_2015_SSP2')
db_name = '{}'.format('pbm_2050_SSP1')
print(db_name)
db = Database(db_name)
ProcessOfInterest=db.search('Spaghetti Bolognese {Germany} - lentils')[0]

#%%

#ProcessOfInterest=db.search('Tomato, fresh grade, greenhouse, heated')[2]

LCIA_methods=[('ReCiPe 2016',  '1.1 (20180117)',  'Midpoint',  'Global Warming', 
 '100 year timescale',  'Hierarchist'),
 ('BII', 'land')]

functional_unit={ProcessOfInterest:1}
#m = ('ReCiPe Midpoint (H) V1.13', 'climate change', 'GWP100')

all_scores = {}
lca1 = LCA(functional_unit,LCIA_methods[0])
lca1.lci()
lca1.lcia()
for meth in LCIA_methods:
    lca1.switch_method(meth)
    lca1.lcia()
    all_scores[meth] = {}
    all_scores[meth]['score'] = lca1.score
    all_scores[meth]['unit'] = Method(meth).metadata['unit']
    print('The score for {} is: \n {:f} {} for impact category {}'.format(ProcessOfInterest,
        lca1.score, 
        Method(meth).metadata['unit'],
        Method(meth).name))

"""

# %%
