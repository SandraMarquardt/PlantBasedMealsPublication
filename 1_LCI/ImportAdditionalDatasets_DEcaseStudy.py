"""Extract and link additional processes for the DE case study meals and save database
"""

## Imports
import os
from sys import argv
from brightway2 import *
import re


## Settings

inputPath = '/888_InputData/CaseStudyCustomDatasets/'
outputPath = '/999_Output/LCI/'

deMealsDataPath = os.path.dirname(os.getcwd())+inputPath+'/DE_Meals.XLSX'
deMealsAdditionalProcessesDataPath = os.path.dirname(os.getcwd())+inputPath+'/DE_AdditionalProcesses_2020_11_05.TXT'
ecoinventWFLDBLoaderFile = os.path.dirname(os.getcwd())+outputPath+'Ecoinvent_WFLBD.fl'

print(deMealsDataPath)
print(deMealsAdditionalProcessesDataPath)

project_name = 'EcoWFLDB_DE_ID'
projects.set_current(project_name)


## Specify extra  migration information
# Problem with unliked technosphere exchanges originate due to migration from ecoinvent 3.4 to 3.5
# Lorry transport not defined for RER and RoW in 3.4 and 'thermoforming' had a different
# name in 3.4

extra_migration = [
    [
        'Transport, freight, lorry, unspecified {RoW}| market for transport, freight, lorry, unspecified | Cut-off, U',
        'transport, freight, lorry, unspecified',
        'RoW',
        'market for transport, freight, lorry, unspecified',
        'EcoInvent 3.5 cut-off'
    ],
    [
        'Transport, freight, lorry, unspecified {RER}| market for transport, freight, lorry, unspecified | Cut-off, U',
        'transport, freight, lorry, unspecified',
        'RER',
        'market for transport, freight, lorry, unspecified',
        'EcoInvent 3.5 cut-off'
    ],
    [
        'Thermoforming, with calendering {RoW}| production | cut-off, U',
        'thermoforming, with calendering',
        'RoW',
        'thermoforming, with calendering', # name in 3.4 was 'thermoforming production, with calendering'
        'EcoInvent 3.5 cut-off'
    ]
]

formatted_data =  {
        'fields': ['name'],
        'data': [(
            (line[0], ),
            {
                'location': line[2],
                'name': line[3],
                'reference product': line[1],
                'system model': line[4],
                'simapro name': line[0],
            }
        ) for line in extra_migration]
}

extra_migration = Migration('truck migration')
extra_migration.write(formatted_data, 'sort out trucks')

## Load the custom additional processes for the case study meal from SimaPro CSV files
sd_importer = SimaProCSVImporter(deMealsAdditionalProcessesDataPath, name="DE_AddProcesses")
sd_importer.apply_strategies()

sd_importer.migrate('simapro-ecoinvent-3.5')
sd_importer.migrate('simapro-ecoinvent-3.4')

# Link with the 'additional mappings' defined at the start
sd_importer.migrate('truck migration')

# link to the relevant databases
sd_importer.match_database("ecoinvent3_5_cutoff", fields=('reference product', 'unit', 'location', 'name'))

sd_importer.match_database("WFLDB35", fields=('name', 'location'))

# Link the two remaining unlinked exchages to the biosphere database
sd_importer.add_unlinked_flows_to_biosphere_database()

sd_importer.statistics()

## Extract fully integrated database (SimaPro additional processes)
if sd_importer.statistics(False)[2] == 0: 
    sd_importer.write_database() 
    print('Database written')


# extract meal recipe
excel_importer = ExcelImporter(deMealsDataPath)

excel_importer.apply_strategies(verbose=True)

# Migrate meal recipes

excel_importer.migrate('default-units')
excel_importer.migrate('unusual-units')
excel_importer.migrate('simapro-ecoinvent-3.5')
excel_importer.migrate('simapro-ecoinvent-3.4')

# Harmonize with the relevant databases (incl the newly defined processes)
excel_importer.match_database("ecoinvent3_5_cutoff", fields=('reference product', 'location', 'name'))

excel_importer.match_database("WFLDB35", fields=('name', 'location'))

excel_importer.match_database("DE_AddProcesses", fields=('name',))

# Force the link of these 2 unlinked product assembly exchanges
def force_production_link(database):
    for dataset in database:
        possibles = [e for e in dataset['exchanges'] if e.get('type') == 'production']
        if len(possibles) != 1:
            raise ValueError("Can't find one production exchange: {}".format(dataset))
        product = possibles[0]
        
        if not product.get('input'):
            product['input'] = (dataset['database'], dataset['code'])
        
        if not product.get('output'):
            product['output'] = (dataset['database'], dataset['code'])
            
    return database

excel_importer.apply_strategy(force_production_link)
excel_importer.statistics() # after taking care of unlinked production exchanges

excel_importer.write_database() # writes new database that includes the product assembly

## For some activies the location needs to be extracted from the activity name
DE_AddProcesses = Database('DE_AddProcesses')
len(DE_AddProcesses)
locationless_activities = [x for x in DE_AddProcesses if not x.get('location')]

pattern = "/ ?([A-Z]{2,3})"
for a in locationless_activities:
    m = re.search(pattern, a['name'])
    new_location = m.group(1)
    
    a['location'] = new_location
    a.save()


