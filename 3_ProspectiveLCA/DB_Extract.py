
"""
Load .fl file and extract database to a brightway project
Check results by printing out LCA score for DE - Spaghetti bolognese with lentils 

python DB_Extract.py EcoWFLDB_2050_SSP1.fl SSP1_2050 EcoWFLDB

"""

import os
from futura import *
from sys import argv

output_path = '/999_Output/ProspectiveLCA/'

args = argv[1:]
#args = ['2050_SSP1.fl', 'EcoWFLDB_DE_ID', 'SSP1_2050']
futura_loader_file = args[0]
futura_loader_file = '{}/{}/{}'.format(os.path.dirname(os.getcwd()), output_path,args[0])

db_name = args[1]

project_name =args[2]

print ("\n======================================================================")
print ("PBM - creating database {} in project {}".format(db_name,project_name))
print ("\n======================================================================\n")


f = FuturaLoader()
f.load(futura_loader_file)

print('writing db start')
f.write_database(project_name, db_name)

print('writing db finish')


###
from brightway2 import *
#from bw_recipe_2016 import add_recipe_2016

projects.set_current(project_name)
db = Database(db_name)
print("Database found, it contains {} items".format(len(db)))

process_of_interest=db.random()

functional_unit={process_of_interest:1}
m = ('ReCiPe Midpoint (H) V1.13', 'climate change', 'GWP100')

lca1=LCA(functional_unit, m)
lca1.lci()
lca1.lcia()
lca1.score

print(databases)

print(process_of_interest)

print("{} kgCO2-eq/{}".format(lca1.score, process_of_interest['unit']))
