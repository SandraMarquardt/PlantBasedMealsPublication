from futura import *
import os

project_name = 'EcoWFLDB'
outputPath = '/999_Output/LCI/'

f = FuturaLoader()
# Ecoinvent and WFLDB
f.database.extract_bw2_database(project_name, 'WFLDB35')
f.database.extract_bw2_database(project_name, 'ecoinvent3_5_cutoff')


f.save(os.path.dirname(os.getcwd())+outputPath+'/Ecoinvent_WFLDB_save.fl')