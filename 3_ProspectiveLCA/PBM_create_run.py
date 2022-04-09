# You will need:
# - The latest version of Futura
# - the futura_image package
# - the following files:
#   - Futura:
#     - `WFLDB_ecoinvent35.fl` (this can be generated using a couple of the other notebooks from the raw databases, 
#       but it's easier to have that step done)
#   - Electricity mixes and efficiency:
#     - `IMAGE_Electricity_SSP2.xlsx`
#     - `Ecoinv2IMAGE_Electricity.xlsx`
#   - Crops:
#     - `EcoinvWFLDB2IMAGE_Crops.xlsx`
#     - `IMAGE_Area_CropYield_SSP2.xlsx`
#   - Livestock:
#     - `WFLDB2IMAGE_Livestock_2020_08_19_JJ.xlsx`
#     - `IMAGE_FeedIntake_Eff_SSP2_2020_08_20.xlsx`




from futura import *
from futura_image import *
from futura.recipe import FuturaRecipeExecutor
from futura_image.mendoza_beltran_utilities import find_other_ecoinvent_regions_in_image_region
import pandas as pd
from copy import deepcopy
from tqdm import tqdm
import sys
from sys import argv
import os.path
import yaml
from pprint import pprint
from collections import defaultdict

outputPath = '999_Output/'

args = argv[1:]
# args should contain [{Scen}, {Year}]
#args = ['SSP1', '2050']
# `analysis_year` is the year to create the new databases for, `base_year` is the year the original datasets represent (2015) for making changes based on relative values
base_year = 2015

scen = args[0]
analysis_year = int(args[1]) # 2030


futura_loader_file = '{}/{}LCI/Ecoinvent_WFLDB_PBM_DE_ID_save.fl'.format(os.path.dirname(os.getcwd()), outputPath)


# electricity
pbm_image_data_path = '{}/{}IMAGEParameterFiltering/{}/IMAGE_Electricity_{}.xlsx'.format(os.path.dirname(os.getcwd()), outputPath, scen,scen)
electricity_mapping_file = '{}/{}IMAGEParameterFiltering/Ecoinv2IMAGE_Electricity.xlsx'.format(os.path.dirname(os.getcwd()), outputPath)

# crops
crop_mapping_file = '{}/{}IMAGEParameterFiltering/EcoinvWFLDB2IMAGE_Crops.xlsx'.format(os.path.dirname(os.getcwd()), outputPath) 
yield_file = '{}/{}IMAGEParameterFiltering/{}/IMAGE_Area_CropYield_{}.xlsx'.format(os.path.dirname(os.getcwd()), outputPath, scen, scen)



# livestock
livestock_mapping_file = '{}/{}IMAGEParameterFiltering/WFLDB2IMAGE_Livestock.xlsx'.format(os.path.dirname(os.getcwd()), outputPath)
feed_file = '{}/{}IMAGEParameterFiltering/{}/IMAGE_FeedIntake_Eff_{}.xlsx'.format(os.path.dirname(os.getcwd()), outputPath, scen,scen)


inputFiles = [futura_loader_file, 
	pbm_image_data_path,electricity_mapping_file,
	crop_mapping_file,yield_file,
	livestock_mapping_file, feed_file]

for file in inputFiles:
    assert os.path.isfile(file), "{} doesn't exist".format(file)




print ("\n======================================================================")
print ("PBM Futura run for {} for the year {}".format(scen, analysis_year))
print()
print('Using files:\n')
print("\n".join([futura_loader_file, pbm_image_data_path, electricity_mapping_file, crop_mapping_file, yield_file, livestock_mapping_file, feed_file]))
print ("\n======================================================================\n")

#assert 0

# ## Step 2. Regionalise the electricity generation technologies and change the grid mixes

# ### Step 2a. Set up some useful functions

image_translation_dict = {'RUS': 'Russia Region',
 'CHN': 'China Region',
 'RSAF': 'Rest of Southern Africa',
 'MEX': 'Mexico',
 'INDO': 'Indonesia Region',
 'JAP': 'Japan',
 'RSAM': 'Rest of South America',
 'WAF': 'Western Africa',
 'UKR': 'Ukraine region',
 'INDIA': 'India',
 'ME': 'Middle east',
 'WEU': 'Western Europe',
 'NAF': 'Northern Africa',
 'KOR': 'Korea Region',
 'EAF': 'Eastern Africa',
 'STAN': 'Central Asia',
 'CEU': 'Central Europe',
 'RCAM': 'Central America',
 'CAN': 'Canada',
 'RSAS': 'Rest of South Asia',
 'SAF': 'South Africa',
 'BRA': 'Brazil',
 'TUR': 'Turkey',
 'OCE': 'Oceania',
 'USA': 'USA',
 'SEAS': 'South Asia'}

def get_image_region(target_region):
    
    rest_of_map = {
            'RER': 'WEU',
            'RNA': 'USA',
            'RLA': 'RSAM',
            'OCE': 'OCE'
        }
        
    final_image_region = rest_of_map.get(target_region)
    
    if not final_image_region:
        
        image_region = [x for x in geomatcher.within(target_region) if x[0] == 'IMAGE']

        if ('IMAGE', 'World') in image_region:
            image_region.pop(image_region.index(('IMAGE', 'World')))

        if len(image_region) == 1:
            final_image_region = image_region[0][1]

        elif len(image_region) > 1:

            print('This area is in more than one IMAGE region, defaulting to the first one found ({})'.format(image_region[0][1]))
            final_image_region = image_region[0][1]

            
    if final_image_region:
        return image_translation_dict[final_image_region]
    else:    
        print('No image region found for {}'.format(target_region))
        return('World')





def electricity_filter(grid_locations=None, voltage='high', description=False):

    elec_filter_base = [
        {'filter': 'equals', 'args': ['unit', 'kilowatt hour']},
        {'filter': 'startswith', 'args': ['name', 'market for electricity, {} voltage'.format(voltage)]},
        {'filter': 'doesnt_contain_any', 'args': ['name', ['aluminium industry',
                                                           'internal use in coal mining',
                                                           'Swiss Federal Railways',
                                                           'label-certified',
                                                           'electricity, from municipal waste incineration'
                                                           ]]},
    ]

    if grid_locations:
        elec_filter_base += [{'filter': 'either', 'args':
            [{'filter': 'equals', 'args': ['location', x]} for x in grid_locations]
                              }]
    if description:
        return elec_filter_base
    else:
        return create_filter_from_description(elec_filter_base)





def get_Electricity_Image2Ecoinvent_mapping(file):
    df = pd.read_excel(file, sheet_name="Technologies").dropna() #sheet_name=1
    possibles_dict = {'high':{}, 'low':{}}
    grouper = df.groupby('IMAGE_NTC2')
    for name, items in grouper:
        high = list(items['activity_name'].loc[df['product_name'] == 'electricity, high voltage'])
        low = list(items['activity_name'].loc[df['product_name'] == 'electricity, low voltage'])
        if high:
            possibles_dict['high'][name] = high
        if low:
            possibles_dict['low'][name] = low
    return possibles_dict





def check_current_techs(loader, target_region, year, mapping):
    image_region =get_image_region(target_region)
    techs = pbm.regional_technologies_for_year(year)[image_region]
    current_names = {'high':[], 'low':[]}
    
    current_metadata = {'high':[], 'low':[]}
    found_techs_metadata = []
    
    hv_elec = w.get_one(f.database.db, *electricity_filter([target_region], 'high'))
    current_names['high'].extend([x['name'] for x in hv_elec['exchanges']])
    
    current_metadata['high'].extend([{'name': x.get('name'), 'location': x.get('location'), 'unit':x.get('unit')} for x in hv_elec['exchanges']])
    
    lv_elec = w.get_one(f.database.db, *electricity_filter([target_region], 'low'))
    current_names['low'].extend([x['name'] for x in lv_elec['exchanges']])
    
    current_metadata['low'].extend([{'name': x.get('name'), 'location': x.get('location'), 'unit':x.get('unit')} for x in lv_elec['exchanges']])
    
    found_techs = defaultdict(list)
    missing_techs = []
    
    for t in techs:
        
        found_techs[t] = []
        
        if t in mapping['high'].keys():
            #print('{} is high voltage'.format(t))
            voltage = 'high'
            
        elif t in mapping['low'].keys():
            #print('{} is LOW voltage'.format(t))
            voltage = 'low'
            
        else:
            #print('No voltage level for this technology ({})'.format(t))
            voltage = None
            
            
        if voltage:
            check_techs = mapping[voltage][t]
            #print(check_techs)
            for ct in check_techs:
                if ct in current_names[voltage]:
                    ix = current_names[voltage].index(ct)
                    found_techs[t].append(ct)
                    current_metadata[voltage][ix]['image_tech'] = t
                    found_techs_metadata.append(current_metadata[voltage][ix])
                
                                
    missing_techs = [k for k, v in found_techs.items() if not len(v)]
    
    return found_techs, missing_techs, found_techs_metadata





def get_names_from_locations(loader, names, locations=None, ref_product=None):
    
    if not isinstance(names, list):
        names = [names]
        
    if locations:
        if not isinstance(locations, list):
            locations = [locations]
        
    filter_desc = [
            {'filter': 'either', 'args':[
                 {'filter': 'equals', 'args':['name', x]} for x in names 
            ]},
        ]
    if ref_product:
        filter_desc += [{'filter': 'equals', 'args':['reference product', ref_product]}]
    
    _filter = create_filter_from_description(filter_desc)
    
    found = w.get_many(loader.database.db, *_filter)  
    
    
    if locations:
        filter_desc2 = [
            {'filter': 'either', 'args':[
                 {'filter': 'equals', 'args':['location', x]} for x in locations
            ]}
        ]
        
        _filter2 = create_filter_from_description(filter_desc2)
        
        found = w.get_many(found, *_filter2)  
    
        #print(_filter2)
      
    return found





def get_missing_processes(loader, missing, target_region, mapping):

    alt_location_list = list(find_other_ecoinvent_regions_in_image_region(target_region))

    non_specific_locations = ['GLO', 'RoW']

    new_found_techs = {}

    for tech in missing:

        if tech in mapping['high'].keys():
            voltage_level = 'high'
        elif tech in mapping['low'].keys():
            voltage_level = 'low'
        else:
            #print('No data for {}'.format(tech))
            continue

        these_found_techs = list(get_names_from_locations(loader, mapping[voltage_level][tech], target_region, ref_product='electricity, {} voltage'.format(voltage_level)))

        if not len(these_found_techs):
            these_found_techs = list(get_names_from_locations(loader, mapping[voltage_level][tech], alt_location_list, ref_product='electricity, {} voltage'.format(voltage_level)))

        if not len(these_found_techs):
            these_found_techs = list(get_names_from_locations(loader, mapping[voltage_level][tech], non_specific_locations, ref_product='electricity, {} voltage'.format(voltage_level)))

        if not len(these_found_techs):
            these_found_techs = list(get_names_from_locations(loader, mapping[voltage_level][tech], ref_product='electricity, {} voltage'.format(voltage_level)))

        new_found_techs[tech] = these_found_techs
        
    filter_attributes = []
    code_list = []
    name_list = []
    regionalisation_code_list = []
    
    for k, v in new_found_techs.items():
        for t in v:
            if t['name'] not in name_list:
                filter_attributes.append({
                    'name':t['name'],
                    'reference product': t['reference product'],
                    'location': t['location'],
                    'unit': t['unit'],
                    'image_tech': tech
                })
                code_list.append(t['code'])
                name_list.append(t['name'])
                
                if t['location'] != target_region:
                    regionalisation_code_list.append(t['code'])

    filter_desc = [
                {'filter': 'either', 'args':[
                     {'filter': 'equals', 'args':['code', c]} for c in regionalisation_code_list 
                ]},
            ]

    #_filter = create_filter_from_description(filter_desc)
        
    return filter_desc, {'code_list': code_list, 'regionalisation_code_list': regionalisation_code_list, 'filter_attributes':filter_attributes}


# ### Step 2b. Grab all the relevant data to do the electricity transformations


pbm = FuturaPBMImageElectricityMix(pbm_image_data_path)

mapping = get_Electricity_Image2Ecoinvent_mapping(electricity_mapping_file)

f = FuturaLoader()
f.load(futura_loader_file)
f.recipe = {'metadata': {'output_database': 'Final_PBM',
  'ecoinvent_version': '3.5',
  'ecoinvent_system_model': 'cutoff',
  'description': ''},
 'actions': []
}


# ### Step 2c. Write the recipe entry to regionalise the electricity processes

# Get list of regions we care about

geomatcher_image_regions = [x for x in w.geomatcher.keys() if 'IMAGE' in x]


edited_geomatcher_image_regions =[
    ('IMAGE', 'RUS'),
 ('IMAGE', 'CHN'),
 ('IMAGE', 'MEX'),
 ('IMAGE', 'INDO'),
 ('IMAGE', 'INDIA'),
 ('IMAGE', 'WEU'),
 ('IMAGE', 'CEU'),
 ('IMAGE', 'CAN'),
 ('IMAGE', 'SAF'),
 ('IMAGE', 'BRA'),
 ('IMAGE', 'TUR'),
 ('IMAGE', 'OCE'),
 ('IMAGE', 'USA'),
 ('IMAGE', 'SEAS')]





from wurst.errors import NoResults


edited_image_regions = []
no_grid_list = []
for region in edited_geomatcher_image_regions:
    region_list = [x for x in w.geomatcher.contained(region) if x[0] != 'IMAGE']
    edited_region_list = []
    for r in region_list:
        if isinstance(r, tuple):
            #print(r)
            r = r[1]
        
        try:
            hv_elec = w.get_one(f.database.db, *electricity_filter([r], 'high'))
            edited_region_list.append(r)
        except NoResults:
            no_grid_list.append(r)            

    edited_image_regions.extend(edited_region_list)


# ### Step 2.d Setup functions for the efficiency bit

efficiency_technologies = ['Biomass CC',
                           'Biomass CHP',
                           'Biomass ST',
                           'Coal CHP',
                           'Coal ST',
                           'IGCC',
                           'Natural gas CC',
                           'Natural gas CHP',
                           'Natural gas OC',
                           'Oil CC',
                           'Oil CHP',
                           'Oil ST']


def get_efficiency_df(file, efficiency_technologies=efficiency_technologies):
    df = pd.read_excel(file, sheet_name="ElecEffAvg").dropna() # sheet_name=1
    df = df[df['t'] >= 2020]
    df = df[df['Value'] != 1]    
    df = df[df['NTC2'].isin(efficiency_technologies)]
    
    return df


def get_efficiencies(region, year, df):
    
    temp_df = df[df['NRC2'] == region]
    temp_df = temp_df[temp_df['t'] == year]
    temp_df = temp_df[['NTC2', 'Value']]
    temp_df = temp_df[['NTC2', 'Value']]
    temp_df = temp_df.set_index('NTC2')
    
    return temp_df.to_dict()['Value']
    

def efficiency_filter(name, location, unit):
    
    _filter = [
        {'filter': 'equals', 'args': ['name', name]},
        {'filter': 'equals', 'args': ['location', location]},
        {'filter': 'equals', 'args': ['unit', unit]},
    ]
    
    return _filter #create_filter_from_description(_filter)


# ### Step 2e. The efficiency bit


efficency_df = get_efficiency_df(pbm_image_data_path)

efficiency_dict = {}

for region in edited_image_regions:
    efficiency_dict[region] = get_efficiencies(get_image_region(region),analysis_year, efficency_df)
    
region = "RoW"
efficiency_dict[region] = get_efficiencies(get_image_region(region),analysis_year, efficency_df)


def get_mix(target_region, year, voltage='high'):
    mix_df = pbm.get_mixes(year)
    image_region =get_image_region(target_region)
    
    techs = pbm.regional_technologies_for_year(year)[image_region]
    
    mix = {}
    for t in techs:
        if t not in missing:
            mix[t] = mix_df.loc[image_region][t]
            
    voltage_total = sum([mix.get(x, 0) for x in mapping[voltage].keys()])
    
    voltage_mix = {k:v/voltage_total for k, v in mix.items() if k in mapping[voltage].keys()}
    
    return voltage_mix


def get_stratification(target_region, analysis_year, voltage, found_techs, mapping):
    
    mix = get_mix(target_region, analysis_year, voltage)
    
    fm2 = w.get_one(f.database.db, *electricity_filter([target_region], voltage))
    
    pv_df = pd.DataFrame(
        [{'input': x['name'], 'production volume': x['production volume']} for x in fm2['exchanges'] if x.get('product') == 'electricity, {} voltage'.format(voltage) and not x['name'].startswith('market')]
    )
    
    if pv_df.empty:
        print('empty')
        return 
    
    exchange_dict = {}
    for k, v in found_techs.items():
        for x in v:
            exchange_dict[x] = k
            
    exchange_dict['electricity voltage transformation from medium to low voltage'] = 'Transformation'
    
    pv_df['Group'] = pv_df['input'].apply(lambda x: exchange_dict.get(x, 'None'))

    in_scope_total = pv_df.loc[~pv_df['Group'].isin(["None", "Transformation"])]['production volume'].sum()
    
    transformation_total = pv_df.loc[pv_df['Group'].isin(["Transformation"])]['production volume'].sum()
    
    grand_total = pv_df['production volume'].sum()
    
    
    mix_stratification = {k: v * in_scope_total for k, v in mix.items()}
    
    stratification_data = {}

    for g, v in pv_df.groupby('Group'):
        this_total = v['production volume'].sum()
        stratification_data[g] = {}

        # print(v)
        for row_index, row in v.iterrows():
            if g == 'None':
                #print ('This is the None group')
                if 'transformation' in row['input']:
                    stratification_data[g][row['input']] = row['production volume']    
                else:
                    stratification_data[g][row['input']] = 0
                

            elif this_total != 0:
                stratification_data[g][row['input']] = row['production volume'] / this_total
            else:
                stratification_data[g][row['input']] = 0
    
    final_dict = {}
    for k, v in stratification_data.items():
        this_pv = mix_stratification.get(k, 0)
        if not this_pv and k == 'Transformation':
            this_pv = transformation_total
        # if this_pv == 0:
        #    print ('No {} in {}'.format(k, market['location']))
        for x, n in v.items():
            final_dict[x] = n * this_pv
            
    return final_dict
    
    
recipe_entries = []
efficiency_metadata = []
for target_region in tqdm(edited_image_regions):
    
    found_techs, missing, current_metadata = check_current_techs(f, target_region, analysis_year, mapping)
    regionalisation_filter, metadata = get_missing_processes(f, missing, target_region, mapping)
    
    efficiency_metadata.extend(current_metadata)
    efficiency_metadata.extend([{'name':x.get('name'), 'location':target_region, 'unit': x.get('unit'), 'image_tech': x.get('image_tech')} for x in metadata['filter_attributes']])
    
    new_recipe_entries =[{'action': 'regionalisation',
                          'tasks': [
                              {
                                  'function': 'regionalise_multiple_processes',
                                  'kwargs': {
                                      'locations': [target_region],
                                      'base_activity_filter': regionalisation_filter
                                  }
                              }
                          ]
                         }]
    
    high_recipe_item = {'action': 'alter_market',
                          'tasks': [
                              {
                                  'function': 'set_market',
                                  'kwargs': {
                                      'market_filter': electricity_filter([target_region], 'high', description=True)
                                  }
                              },
                              {
                                  'function': 'add_alternative_exchanges',
                                  'args': []
                              },
                          ]
                         }
    
    high_final_dict = get_stratification(target_region, analysis_year, 'high', found_techs, mapping)
    
    if high_final_dict:
        for k, v in high_final_dict.items():
            high_recipe_item['tasks'].append(
                {'function': 'set_pv', 'kwargs': {'process_name': k, 'new_pv': v }}
               )

        high_recipe_item['tasks'].append({'function': 'relink', 'args': []})

    new_recipe_entries.append(high_recipe_item)
    
    
    
    low_recipe_item = {'action': 'alter_market',
                          'tasks': [
                              {
                                  'function': 'set_market',
                                  'kwargs': {
                                      'market_filter': electricity_filter([target_region], 'low', description=True)
                                  }
                              },
                              {
                                  'function': 'add_alternative_exchanges',
                                  'args': []
                              },
                          ]
                         }
    
    low_final_dict = get_stratification(target_region, analysis_year, 'low', found_techs, mapping)
    
    if low_final_dict:

        for k, v in low_final_dict.items():
            low_recipe_item['tasks'].append(
                {'function': 'set_pv', 'kwargs': {'process_name': k, 'new_pv': v }}
               )

        low_recipe_item['tasks'].append({'function': 'relink', 'args': []})
    
    new_recipe_entries.append(low_recipe_item)
                        
    recipe_entries.extend(new_recipe_entries)
    
    # GET RID OF THESE 2 LINES TO DO THE WHOLE WORLD
    #if i > 2:
        #break




executor = FuturaRecipeExecutor(f)
errors = []
for recipe_entry in tqdm(recipe_entries):
    try:
        executor.execute_recipe_action(recipe_entry)
        f.recipe['actions'].append(recipe_entry)
    except Exception as e:
        print("*** ERROR IN STEP ***\n\n{}\n*********************".format(recipe_entry))
        err, value, traceback = sys.exc_info()
        errors.append((e, err, value, traceback))
        #break
    f.recipe['actions'].append(recipe_entry)


print("Electricity - Done")


efficiency_recipe_entries = []

for r in tqdm(edited_image_regions):
    
    metadata_set = [x for x in efficiency_metadata if x['location'] == r]
    
    for m in metadata_set:
    
        eff_filter_desc = efficiency_filter(m['name'], m['location'], m['unit'])
        eff_filter = create_filter_from_description(eff_filter_desc)
        t = w.get_one(f.database.db, *eff_filter)
        this_eff = t['parameters'].get('efficiency', t['parameters'].get('efficiency_electrical', t['parameters'].get('efficiency_oil_country')))
        if isinstance(this_eff, dict):
            this_eff = this_eff['amount']
        new_eff = efficiency_dict[m['location']].get(m['image_tech'])
        if new_eff:
            #print(new_eff, this_eff)
            eff_ratio = new_eff/this_eff
            production_amount = list(w.production(t))[0]['amount']
            new_amount = production_amount*eff_ratio

            this_recipe_entry = {
                'action': 'target_processes',
                'tasks': [{'function': 'set_process',
                           'kwargs': {'process_filter': eff_filter_desc}
                          },
                          {'function':'change_production_amount',
                           'kwargs': {'new_amount': new_amount},
                          }
                         ]
            }

            efficiency_recipe_entries.append(this_recipe_entry)


executor = FuturaRecipeExecutor(f)

for recipe_entry in tqdm(efficiency_recipe_entries):
    executor.execute_recipe_action(recipe_entry)
    f.recipe['actions'].append(recipe_entry)


print("Efficiency - Done")

# ## Crops



def get_crop_map(file):
    
    df = pd.read_excel(file, sheet_name="Technologies") # sheet_name=0

    crop_map = {}
    
    for index, row in df.iterrows():

        if row['Source'] == 'WFLDB':
            this_name = row['ActivityName']
        elif row['Source'] == 'Ecoinvent':
            this_name = row['activity_name']

        crop_map[this_name] = row['NFCT_mod']
        
    return crop_map



crop_map = get_crop_map(crop_mapping_file)


def get_yield_df(file):
    df = pd.read_excel(file, sheet_name="YIELD_DM").dropna() # sheet_name=0 
    df = df[df['t'] >= base_year]
    df = df[df['Value'] != 1]    
    
    return df


yield_df = get_yield_df(yield_file)

def get_yield_ratio(region, crop, year, irrigated, yield_df, base_year=2015):
    
    if irrigated:
        irrigation = 'irrigated'
    else:
        irrigation = 'rainfed'
        
    base_yield_row = yield_df[(yield_df['NRC2']==region) & (yield_df['t']==base_year) & (yield_df['NFCAREAT']==irrigation) & (yield_df['NFCT_mod']==crop)]
    future_yield_row = yield_df[(yield_df['NRC2']==region) & (yield_df['t']==year) & (yield_df['NFCAREAT']==irrigation) & (yield_df['NFCT_mod']==crop)]
    
    if len(base_yield_row):
    
        base_yield = base_yield_row.iloc[0]['Value']
        future_yield = future_yield_row.iloc[0]['Value']
        
        #print(base_yield, future_yield, future_yield/base_yield)
        if base_yield == 0:
            return 0
        else:
    
            return(future_yield/base_yield)
    else:
        return 0





def create_name_filter(name):

    filter_desc = [
            {'filter': 'equals', 'args': ['name', name]},
    ]

    name_filter = create_filter_from_description(filter_desc)
    
    return name_filter





water_list = ['2404b41a-2eed-4e9d-8ab6-783946fdf5d6',
 '2256a142-8242-4b4f-b9aa-a167803989ca',
 'db4566b1-bd88-427d-92da-2d25879063b9',
 '06d4812b-6937-4d64-8517-b69aabce3648',
 '4f0f15b3-b227-4cdc-b0b3-6412d55695d5',
 '51254820-3456-4373-b7b4-056cf7b16e01']





water_filter_desc = [
    {'filter': 'contains', 'args': ['name', 'Water']}
]
water_filter = create_filter_from_description(water_filter_desc)


def create_item_filter(name, location):

    filter_desc = [
            {'filter': 'equals', 'args': ['name', name]},
        {'filter': 'equals', 'args': ['location', location]},
        {'filter':'exclude', 'args': [
            {'filter': 'equals', 'args': ['reference product', 'straw']}
        ]
        },
        {'filter':'exclude', 'args': [
            {'filter': 'equals', 'args': ['reference product', 'stalk']}
        ]
        },
        {'filter':'exclude', 'args': [
            {'filter': 'equals', 'args': ['reference product', 'cotton seed']}
        ]
        },
        {'filter':'exclude', 'args': [
            {'filter': 'equals', 'args': ['reference product', 'straw, organic']}
        ]
        },
        
    ]

    return filter_desc


crop_yield_info = []
crop_recipe_entries = []

for crop_name, image_crop in crop_map.items():
    #print(crop_name, image_crop)
    crop_filter = create_name_filter(crop_name)
    found_names = w.get_many(f.database.db, *crop_filter)
    for item in found_names:
        if item.get('location') in ['GLO', 'RoW', 'RER']:
            continue
        image_region = get_image_region(item.get('location'))
        water_flows = [x for x in list(w.get_many(w.biosphere(item), *water_filter)) if x.get('flow') in water_list]
        if len(water_flows):
            irrigated = True
        else:
            irrigated = False
            
        #print(image_region, image_crop, year, irrigated)
            
        yield_ratio = get_yield_ratio(image_region, image_crop, analysis_year, irrigated, yield_df)
        
        if yield_ratio:
            
            production = [x for x in item['exchanges'] if x['type']=='production']
            #print(production[0]['name'], production[0]['location'], production[0]['amount'])
            if len(production) != 1:
                print('multiple production flows')
                continue
                
            new_amount = production[0]['amount'] * yield_ratio
            
            this_process_filter = create_item_filter(item['name'], item['location'])
            
            this_recipe_entry = {
            'action': 'target_processes',
            'tasks': [{'function': 'set_process',
                       'kwargs': {'process_filter': this_process_filter}
                      },
                      {'function':'change_production_amount',
                       'kwargs': {'new_amount': new_amount},
                      }
                     ]
            }

            crop_recipe_entries.append(this_recipe_entry)
            
            #test = list(w.get_many(f.database.db, *create_filter_from_description(this_process_filter)))
            #if len(test) != 1:
            #    print ([[x['name'], x['location'], x['reference product']] for x in test])

            
            crop_yield_info.append({'crop_dataset': item, 'yield_ratio': yield_ratio})


executor = FuturaRecipeExecutor(f)

for recipe_entry in crop_recipe_entries:
    executor.execute_recipe_action(recipe_entry)
    f.recipe['actions'].append(recipe_entry)

# ### Livestock

def get_livestock_map(file):
    
    df = pd.read_excel(file, sheet_name="Technologies") # sheet_name=0

    livestock_map = {}
    
    for index, row in df.iterrows():

        this_name = row['ActivityName']

        livestock_map[this_name] = {'animal_type': row['NA'], 'system_type': row['NGST']}
        
    return livestock_map





def get_basket_map(file):
    
    df = pd.read_excel(file, sheet_name="LivestBaskets") # sheet_name=2

    basket_map = {}
    
    for index, row in df.iterrows():

        this_name = row['ActivityName']

        basket_map[this_name] = {'animal_type': row['NA'], 'system_type': row['NGST']}
        
    return basket_map





def get_input_map(file):
    
    df = pd.read_excel(file, sheet_name="LivestFeedInpt") # sheet_name=3

    input_map = {}
    
    for index, row in df.iterrows():

        this_name = row['ActivityName']

        input_map[this_name] = row['NFPT']
        
    return input_map





livestock_map = get_livestock_map(livestock_mapping_file)
basket_map = get_basket_map(livestock_mapping_file)
input_map = get_input_map(livestock_mapping_file)





def create_livestock_process_filter(name):

    filter_desc = [
            {'filter': 'equals', 'args': ['name', name]},
    ]

    name_filter = create_filter_from_description(filter_desc)
    
    return name_filter





def create_detailed_livestock_process_filter_desc(name, location, reference_product, unit):

    filter_desc = [
            {'filter': 'equals', 'args': ['name', name]},
            {'filter': 'equals', 'args': ['location', location]},
            {'filter': 'equals', 'args': ['reference product', reference_product]},
            {'filter': 'equals', 'args': ['unit', unit]},
    ]

    #name_filter = create_filter_from_description(filter_desc)
    
    return filter_desc





def get_feed_df(file):
    df = pd.read_excel(file, sheet_name="FEEDEFF").dropna() # sheet_name=1
    df = df[df['t'] >= base_year]
    #df = df[df['Value'] != 0]    
    
    return df





feed_df = get_feed_df(feed_file)





def get_feed_info(region, animal_type, system_type, year, feed_df, base_year=2015):
    
      
    base_feed_rows = feed_df[(feed_df['NRC2']==region) & (feed_df['t']==base_year) & (feed_df['NA']==animal_type) & (feed_df['NGST']==system_type)]
    future_feed_rows = feed_df[(feed_df['NRC2']==region) & (feed_df['t']==year) & (feed_df['NA']==animal_type) & (feed_df['NGST']==system_type)]
    
    if len(base_feed_rows):
        base_info = {}
        future_info = {}

        for i, row in base_feed_rows.iterrows():
            base_info[row['NFPT']] = row['Value']
            
        for i, row in future_feed_rows.iterrows():
            future_info[row['NFPT']] = row['Value']
    
        if base_info['total'] == 0 or future_info['total'] == 0:
            print('no data for {} {} {}'.format(region, animal_type, system_type))
            return None, None, None
        else:
            #print(base_feed_rows)
            #print(future_feed_rows)
            efficiency = base_info['total']/future_info['total']

            return base_info, future_info, efficiency
    else:
        print('nothing found')
        return None, None, None


# ### Livestock efficiencies




lse_recipe_entries = []
livestock_info = []

for process_name, image_info in livestock_map.items():
    #print(crop_name, image_crop)
    _filter = create_livestock_process_filter(process_name)
    found_names = w.get_many(f.database.db, *_filter)
    for item in found_names:
        if item.get('location') in ['GLO', 'RoW', 'RER']:
            continue
        image_region = get_image_region(item.get('location'))
        
        base, future, output_ratio = get_feed_info(image_region, image_info['animal_type'], image_info['system_type'], analysis_year, feed_df)

    #break
        if output_ratio:
            
            production = [x for x in item['exchanges'] if x['type']=='production']
            #print(production[0]['name'], production[0]['location'], production[0]['amount'])
            if len(production) != 1:
                print('multiple production flows')
                continue
                
            new_production = production[0]['amount'] * output_ratio
            this_process_filter = create_detailed_livestock_process_filter_desc(item.get('name'), item.get('location'), item.get('reference product'), item.get('unit'))
            
            this_recipe_entry = {
            'action': 'target_processes',
            'tasks': [{'function': 'set_process',
                       'kwargs': {'process_filter': this_process_filter}
                      },
                      {'function':'change_production_amount',
                       'kwargs': {'new_amount': new_production},
                      }
                     ]
            }
            
            lse_recipe_entries.append(this_recipe_entry)
            
            #production_check = [x for x in item['exchanges'] if x['type']=='production']
            #print(production_check[0]['name'], production_check[0]['location'], production_check[0]['amount'])
        
            livestock_info.append({'dataset': item, 'ratio': output_ratio})





executor = FuturaRecipeExecutor(f)

for recipe_entry in lse_recipe_entries:
    executor.execute_recipe_action(recipe_entry)
    f.recipe['actions'].append(recipe_entry)





def create_feed_filter():

    filter_desc = [
            {'filter': 'contains', 'args': ['name', 'Feed basket']},
    ]

    name_filter = create_filter_from_description(filter_desc)
    
    return name_filter










#livestock_info = []
lsfb_recipe_entries = []

for process_name, image_info in basket_map.items():
    #print(crop_name, image_crop)
    _filter = create_livestock_process_filter(process_name)
    found_names = w.get_many(f.database.db, *_filter)
    for item in found_names:
        if item.get('location') in ['GLO', 'RoW', 'RER']:
            continue
        image_region = get_image_region(item.get('location'))
            
        #print(item.get('name'), image_region, image_info, year)
        
        base, future, output_ratio = get_feed_info(image_region, image_info['animal_type'], image_info['system_type'], analysis_year, feed_df)
        
        if future:
            technosphere = [x for x in item['exchanges'] if x['type'] == 'technosphere']
            input_set = set([input_map[x['name']] for x in technosphere])

            mod_future = {k:v for k,v in future.items() if k in input_set}
            mod_total = sum([v for k, v in mod_future.items()])

            mod_future_percent = {k:v/mod_total for k,v in mod_future.items()}

            technosphere = [x for x in item['exchanges'] if x['type'] == 'technosphere']
            #pprint([[x['name'], input_map[x['name']]] for x in technosphere])
            #pprint(set([input_map[x['name']] for x in technosphere]))
            #pprint(set([k for k,v in future_percent.items() if v>0]))
            #print(mod_future_percent)
            
            current_total = sum(x['amount'] for x in technosphere)
            assert round(current_total,5) == 1
            
            tech_current = [{'name':x['name'], 'image_class':input_map[x['name']], 'amount':x['amount']} for x in technosphere]
            #pprint(tech_current)
            
            ratios = defaultdict(float)
            
            for j in tech_current:
                ratios[j['image_class']] += j['amount']
                
            #pprint(ratios)
            
            multipliers = {k: mod_future_percent[k]/v for k, v in ratios.items()}
            
            #pprint(multipliers)
            
            checksum = 0
            new_amounts = {}
            for tech in tech_current:
                tech['new_amount'] = tech['amount'] * multipliers[tech['image_class']]
                checksum += tech['new_amount']
                new_amounts[(tech['name'], tech.get('location'))] = tech['new_amount']

            this_process_filter = create_detailed_livestock_process_filter_desc(item.get('name'), item.get('location'), item.get('reference product'), item.get('unit'))
            
            this_recipe_entry = {
            'action': 'target_processes',
            'tasks': [{'function': 'set_process',
                       'kwargs': {'process_filter': this_process_filter}
                      },
                      {'function':'change_exchange_amounts',
                       'kwargs': {'change_dict': new_amounts},
                      }
                     ]
            }
            
            lsfb_recipe_entries.append(this_recipe_entry)
            
            #pprint(new_amounts)
                
            #pprint(tech_current)
            #print(round(checksum,5))
            
            #for exc in item['exchanges']:
            #    if exc['name'] in new_amounts.keys():
            #        exc['amount'] = new_amounts[exc['name']]
                    
            #check_technosphere =  [x for x in item['exchanges'] if x['type'] == 'technosphere']
            
            #pprint(check_technosphere)
            
            #print(base,)
            #print(future,)
            #print(output_ratio)
            #break
        else:
            print('Skipping {}'.format(process_name))
    





executor = FuturaRecipeExecutor(f)

for recipe_entry in lsfb_recipe_entries:
    executor.execute_recipe_action(recipe_entry)
    f.recipe['actions'].append(recipe_entry)





db_set = set()
for ds in f.database.db:
    for e in ds['exchanges']:
        db_set.add(e.get('input', [None])[0])
print(db_set)





f.save('{}/{}/ProspectiveLCA/{}_{}.fl'.format(os.path.dirname(os.getcwd()), outputPath,analysis_year, scen))





