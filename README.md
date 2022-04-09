# PlantBasedMealsPublication

> NOTE:
> This repository contains two branches
> * main: a generic implementation of the approach (i.e. usable with licensed ecoinvent data but without the meal case study specific implementations)
> * case_study_impl: implementation used for the publication (requires additional commercially senstive information that cannot be shared)

## Workspace structure and content

1_LCI
* Extracting and linking Ecoinvent and WFLDB
* Extracting and linking meal LCI

2_IMAGEParameterFiltering
* R files to identify link between IMAGE information and approapriate ecoinvent/WFLDB data

3_ProspectiveLCA
* Python files to run prospective LCA
    * generating scenario rusn
    * adding new methods (Recipe 2016, BII)
    * extracting results to csv for further exploitation

888_InputData
* Input data for all relevant steps

999_Output
* Output data and visualizations

## Step-by-step run through
> NOTE: The following files and folders are NOT included in the git repo
>
> Databases can be downloaded under license, AdditionalProcesses files contain comercially sensitive data and cannot be shared

* 888_InputData\Ecoinvent\datasets [download ecoinvent 3.5_cutoff_ecoSpold02.7z from [ecoinvent](http://www.ecoinvent.org) and extract]
* 888_InputData\Ecoinvent\35_migration_2.pickle
* 888_InputData\WLFDB/WFLDB35_20200109_edited.CSV [Export WFLDB from SimaPro as .csv and make the edits listed below]
* 888_InputData\CaseStudyCustomDatasets\DE_AdditionalProcesses_2020_11_05.TXT [SimaPro extract of custom additional datasets]
* 888_InputData\CaseStudyCustomDatasets\ID_AdditionalProcesses_2020_11_06.TXT [SimaPro extract of custom additional datasets]

> Edits required to WFLDB SimaPro export:
> - Replace `;min;` with `;minute;`
> - Replace `yield` with `crop_yield`
> - Replace `^` with `**`
> - Change `Methane;` to `Methane, fossil;` (in chick hatching and petrol use in mower/machine)
> - Add cutoff processes (see `888_InputData/additional_waste_cutoffs.csv` for :
>    - Core board (waste treatment) {GLO}| recycling of core board | Cut-off, U
>    - Mixed plastics (waste treatment) {GLO}| recycling of mixed plastics | Cut-off, U
>    - Steel and iron (waste treatment) {GLO}| recycling of steel and iron | Cut-off, U


### 0) Set up the conda environment and dependencies

```
conda create -n mealsEnv python=3
conda activate mealsEnv

pip install brightway2 pyside2 pyaml futura futura-image wurst bw-recipe-2016
```
> See env_setup.txt for detailed overview of package versions used for this project

### 1) Process LCI information


#### 1.1) Create brightway project containing Ecoinvent and WFLDB

> Importing WFLDB into Brightway is a complex process which we have compiled into a script, this script creates a project called `EcoWFLDB_DE_ID`, to change this edit the `project_name` variable in the script.

`cd` to `1_LCI`

Run the script

```
python LinkEcoinventWFLDB.py 
```

* Input
    * 888_InputData\Ecoinvent\ecoinvent 3.5_cutoff_ecoSpold02.7 [not on git]
    * 888_InputData\Ecoinvent\35_migration_2.pickle [not on git]
    * 888_InputData\WFLDB\WFLDB35_20200109_edited.CSV [not on git]
* Output
    * BW project with ecoinvent and WFLDB databases

#### 1.2) Extract and link case study LCI information
```
python ImportAdditionalDatasets_DEcaseStudy.py
```
* Input
    * 888_InputData\CaseStudyCustomDatasets\DE_Meals.xlsx
    * 888_InputData\CaseStudyCustomDatasets\DE_AdditionalProcesses_2020_11_05.TXT [not on git]
* Output
    * Added DE case study meals to brightway project

```
python ImportAdditionalDatasets_IDcaseStudy.py
```
* Input
    * 888_InputData\CaseStudyCustomDatasets\ID_Meals.xlsx
    * 888_InputData\CaseStudyCustomDatasets\ID_Meals_Subassembly.xlsx
    * 888_InputData\CaseStudyCustomDatasets\ID_AdditionalProcesses_2020_11_06.TXT [not on git]
* Output
    * Added ID case study meals to brightway project

#### 1.3) Generate .fl file for use in Futura runs

```
python GenerateFL.py
```

* Input
  * [Brightway database generated in previous steps]

* Output
  * /999_Output/LCI/Ecoinvent_WFLDB_PBM_DE_ID_save.fl

### 2)  Getting IMAGE data ready 
#### 2.1) Harmonizing mapping with ecoinvent/WFLDB
Using R Studio (in directory 2_IMAGEParameterFiltering)
Run HarmonizeMappingsAndFilter.R
* Input
    * 888_InputData\Ecoinvent/activity_overview_3.5_allocation__cut-off_public.xlsx
	* 888_InputData\Mappings/Mapping_FAO_CPC.xlsx
	* 888_InputData\Mappings/Mapping_BeltranPaper.xlsx
	* 888_InputData\WFLDB/WFLDB-3.5_Documentation_Appendix-1_DQR&MainInputs_20191205.xlsx
	* 888_InputData\Mappings/new_IMAGE_16crops_2020_05_26.xlsx
	* 888_InputData\IMAGEParameterFiltering/Ecoinv_ElectProductFilter_2020_07_01.xlsx
	* 888_InputData\IMAGEParameterFiltering/FilterEcoinv2Mapping_Adj_2020_07_02.xlsx
	* 888_InputData\IMAGEParamterFiltering/FilterEcoinv_ElectMarket_Eff_2020_07_01.xlsx
	* 888_InputData\IMAGEParameterFiltering/FitlerCrops1_2020_08_04.xlsx
	* 888_InputData\IMAGEParameterFiltering/FilterCropsEco1_manualCheck_2020_08_05.xlsx
	* 888_InputData\IMAGEParameterFiltering/FilterCropsEco3_2020_08_05.xlsx
    * 888_InputData\IMAGEParameterFiltering/FilterLivest_Feed1_2020_08_19.xlsx
* Output [merge output files for electricity and crops similar to livestock]
	* 999_Output\IMAGEParameterFiltering\Ecoinv2IMAGE_Electricity.xlsx
	* 999_Output\IMAGEParameterFiltering\EcoinvWFLDB2IMAGE_Crops.xlsx
    * 999_Output\IMAGEParameterFiltering\WFLDB2IMAGE_Livestock.xslx

#### 2.2) Transforming IMAGE data for use in prospective LCA
Using R Studio (in directory 2_IMAGEParameterFiltering)
Run TransformIMAGEData.R
* Input
	* 888_InputData\Mappings/Mappings_IMAGE_{MappingsFileDate}.xlsx
	* 888_InputData\IMAGE/{Scen}_TIMER_3_11_Results_2020_10_30.xlsx
	* 888_InputData\IMAGE/{Scen}_IM32.xlsx
* Output
	* 999_Output\IMAGEParameterFiltering\/{Scen}/IMAGE_Electricity_{Scen}.xlsx
	* 999_Output\IMAGEParameterFiltering\/{Scen}/IMAGE_Area_CropYield_{Scen}.xlsx
	* 999_Output\IMAGEParameterFiltering\/{Scen}/IMAGE_FeedIntake_Eff_{Scen}.xlsx

### 3) Prospective LCA and extracting results
#### 3.1) Run prospective LCA per scenario
Navigate to 3_ProspectiveLCA (using anaconda cmd) [see commands.txt for concrete examples]
python PBM_create_run.py {scen} {year}
* Input
    * 999_Output\LCI\BaseLoader\Ecoinvent_WFLDB_PBM_DE_ID_save.fl
	* 999_Output\IMAGEParameterFiltering\/{Scen}/IMAGE_Electricity_{Scen}.xlsx
	* 999_Output\IMAGEParameterFiltering\Ecoinv2IMAGE_Electricity.xlsx
	* 999_Output\IMAGEParameterFiltering\/{Scen}/IMAGE_Area_CropYield_{Scen}.xlsx
	* 999_Output\IMAGEParameterFiltering\EcoinvWFLDB2IMAGE_Crops.xlsx
	* 999_Output\IMAGEParameterFiltering\/{Scen}/IMAGE_FeedIntake_Eff_{Scen}.xlsx
	* 999_Output\IMAGEParameterFiltering\WFLDB2IMAGE_Livestock.xslx
* Output
    * 999_Output\ProspectiveLCA\{year}_{scen}.fl

#### 3.2) Extract scenario results as brightway2 databases
python DB_extract.py {file_name} {database_name} {project_name}
* Input
    * 999_Output\ProspectiveLCA\{year}_{scen}.fl
* Output
    * scenario database stored in brightway2 project

#### 3.3) Add custom LCA methods to brightway2 project
python NewMethods_Recipe2016_BII.py {project_name}
* Input
    * 888_InputData/Mappings/Ecoinvent2BII_2021_01_12.xlsx
* Output
    * additional methods stored in brightway2 project

#### 3.4) Extract LCA results of scenarios as csv files
python ResultExploitation.py {project_name} {database_name} {scen} {year}
* Input
    * databases of the selected project
* Output
    * 999_Output\ProspectiveLCA\ForExploitation\{LCA_method}_{scen}_{year}_{meal}.csv
    * 999_Output\ProspectiveLCA\ForExploitation\{LCA_method}_{scen}_{year}_{meal}_meal_comp.csv
