from futura import *
import os

project_name = 'EcoWFLDB_DE_ID'
outputPath = '/999_Output/LCI/'

f = FuturaLoader()
f.database.extract_bw2_database(project_name, 'ID_Meals')
f.database.extract_bw2_database(project_name, 'ID_AddProcesses')
f.database.extract_bw2_database(project_name, 'ID_MealsSubassembly')

# Add DE Meals
f.database.extract_bw2_database(project_name, 'DE_AddProcesses')
f.database.extract_bw2_database(project_name, 'DE_Meals')

# Ecoinvent and WFLDB
f.database.extract_bw2_database(project_name, 'WFLDB35')
#f.database.extract_bw2_database(project_name, 'WFLDB35 additional biosphere')
f.database.extract_bw2_database(project_name, 'ecoinvent3_5_cutoff')


f.save(os.path.dirname(os.getcwd())+outputPath+'/Ecoinvent_WFLDB_PBM_DE_ID_save.fl')