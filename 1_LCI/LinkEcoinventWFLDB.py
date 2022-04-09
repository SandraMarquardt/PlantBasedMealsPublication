"""Extract and link ecoinvent cutoff 3.5 to WFLDB and save database
"""

## Imports
import os
from sys import argv
from brightway2 import *
import pickle
import re

## Settings

inputPath = '/888_InputData/'
outputPath = '/999_Output/LCI/'

ecoinventDataPath = os.path.dirname(os.getcwd())+inputPath+'/Ecoinvent/datasets/'
migrationDataPath = os.path.dirname(os.getcwd())+inputPath+'/Ecoinvent/35_migration_2.pickle'
wfldbDataPath = os.path.dirname(os.getcwd())+inputPath+'/WFLDB/WFLDB35_20200109_edited.CSV'

project_name = 'EcoWFLDB'


projects.set_current(project_name)

bw2setup()

## Import ecoinvent 3.5 cutoff database

if 'ecoinvent3_5_cutoff' in databases:
    print('Ecoinvent 3.5 cutoff already imported.')
else:
    eco_importer = SingleOutputEcospold2Importer(ecoinventDataPath, 'ecoinvent3_5_cutoff',use_mp=False)
    eco_importer.apply_strategies()
    eco_importer.write_database()


## Load the custom migration data (35_mirgration_2.pickle)
with open(migrationDataPath, 'rb') as f:
    data = pickle.load(f)

ecoinvent_35_migration = Migration('simapro-ecoinvent-3.5')

ecoinvent_35_migration.write(data, 'ecoinvent 3.5 migration from WFLDB processes')

## Create the unit fixes migration 

WFLDB_unit_fixes = { 
    'fields': ['name', 'unit'], 
    'data': [ 
        ( 
            ('treatment of wastewater, average, capacity 1E9l/year', 'litre'), 
            { 
                'unit': 'cubic meter', 
                'multiplier': 1e-3 
            } 
        ),
        ( 
            ('treatment of wastewater, average, capacity 5E9l/year', 'litre'), 
            { 
                'unit': 'cubic meter', 
                'multiplier': 1e-3 
            } 
        ),
        ( 
            ('market for wastewater, average', 'litre'), 
            { 
                'unit': 'cubic meter', 
                'multiplier': 1e-3 
            } 
        ),
        (
            ('heat production, natural gas, at industrial furnace >100kW', 'kilowatt hour'),
            {
                'unit': 'megajoule',
                'multiplier': 3.6
            }
        )
    ] 
} 

Migration("WFLDB-unit-fixes").write( 
    WFLDB_unit_fixes, 
    description="Fix some unit conversions" 
) 

## Load the edited csv file
"""
### Edits to csv file:
*These have already been made in the file*
- Replace `;min;` with `;minute;`
- Replace `yield` with `crop_yield`
- Replace `^` with `**`
- Change `Methane;` to `Methane, fossil;` (in chick hatching and petrol use in mower/machine)
- Add cutoff processes (see `additional_waste_cutoffs.csv` for :
  - Core board (waste treatment) {GLO}| recycling of core board | Cut-off, U
  - Mixed plastics (waste treatment) {GLO}| recycling of mixed plastics | Cut-off, U
  - Steel and iron (waste treatment) {GLO}| recycling of steel and iron | Cut-off, U
"""

importer = SimaProCSVImporter(wfldbDataPath, 'WFLDB35')


## Fix the allocation parameters (custom function)
def fix_wfldb_allocation_parameters(importer):
    for x in importer.data:
    
        if isinstance(x['exchanges'][0].get('allocation'), str):
            AlF = x['parameters']['alf']['amount']
            for e in x['exchanges']:
                if e['type'] == 'production':
                    e['allocation'] = eval(e['allocation'].replace('AlF', str(AlF)))

fix_wfldb_allocation_parameters(importer)


## Apply strategies and migrations
importer.apply_strategies()

importer.migrate('simapro-ecoinvent-3.5')

importer.migrate('simapro-ecoinvent-3.4')

importer.migrate('WFLDB-unit-fixes')

## Put superfluous biosphere flows into a separate database
db_name = "WFLDB35 additional biosphere"
Database(db_name).register() 
importer.add_unlinked_flows_to_biosphere_database(db_name) 

## Match and write the database

importer.match_database("ecoinvent3_5_cutoff", fields=('reference product', 'unit', 'location', 'name'))
importer.match_database("WFLDB35 additional biosphere", kind="biosphere")

importer.statistics() 

importer.write_database()

## For some activies the location needs to be extracted from the activity name
wfldb = Database('WFLDB35')
assert len(wfldb)
locationless_activities = [x for x in wfldb if not x.get('location')]

pattern = "/ ?([A-Za-z\-]*)"
for a in locationless_activities:
    m = re.search(pattern, a['name'])
    new_location = m.group(1)
    
    a['location'] = new_location
    a.save()
