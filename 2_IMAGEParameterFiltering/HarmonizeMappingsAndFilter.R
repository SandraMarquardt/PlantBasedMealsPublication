####
rm(list = ls())
# working in R 3.6.3

# Settings ####
###

out_date<-format(Sys.Date(),'%Y_%m_%d')

# Write out results (plots, tables)
Write<- "no"  # yes or no

# Set mappings that are to be done
Electricity<-"True" # True or False
Crops<-"True"
Livestock<-"True"

meta_df<-data.frame(cbind("date",out_date))

# Packages
packages<-c("data.table","fuzzyjoin", "dplyr","janitor","openxlsx", "plyr", 
            "readxl","rgdal","gtools", "splitstackshape", "stringr","tidyverse" )

req<-substitute(require(x, character.only = TRUE))
sapply(packages, function(x) eval(req) || {install.packages(x); eval(req)})

# Paths
input_path<-paste0(dirname(getwd()),"/888_InputData/")
output_path<-paste0(dirname(getwd()),"/999_Output/IMAGEParameterFiltering/")
check_path<-paste0(dirname(getwd()),"/Checks/")

if(!dir.exists(paste0(output_path))) {dir.create(paste0(output_path))}

#### 1) Read input data #####

### Ecoinvent 3.5 cutoff model
Ecoinv_3_5_Cutoff<-data.frame(readxl::read_xlsx(paste0(input_path,"/Ecoinvent/activity_overview_3.5_allocation__cut-off_public.xlsx"), 
                                col_names = TRUE,
                                col_types = "text",
                                sheet = "activity overview",
                                range = "A1:O16023"))

Ecoinv_3_5_Cutoff_ElemExch<-data.frame(readxl::read_xlsx(paste0(input_path,"/Ecoinvent/activity_overview_3.5_allocation__cut-off_public.xlsx"), 
                                                col_names = TRUE,
                                                col_types = "text",
                                                sheet = "ElementaryExchanges",
                                                range = "A1:F4244"))

# re-name columns to avoid issues with python
colnames(Ecoinv_3_5_Cutoff)<-c("activity_uuid","activity_name","geography","time_period","ISIC_number","ISIC_class",            
                               "special_activity_type","inheritence_status","tags","group","product_name","CPC_number",            
                               "CPC_description","unit","cut_off_classification" )
## Unique data
Ecoinv_3_5_Cutoff %>% summarise_all(n_distinct)

#activity.uuid activity.name geography time.period ISIC.number ISIC.class special.activity.type inheritence.status tags group
#1         14613          6676       261          74         193        191                     4                  3  511     1
#product.name CPC.number CPC.description unit cut.off.classification
#1         2905        563             560   17                      3

# Of interest: activity.name, product.name, special.activity.type,  unit

Ecoinv_Reduced<-data.frame(unique(Ecoinv_3_5_Cutoff[,c("special_activity_type", "product_name","activity_name","unit")]))

Ecoinv_Reduced_ISIC_CPC<-data.frame(unique(Ecoinv_3_5_Cutoff[,c("special_activity_type", "product_name","activity_name","unit",
                                                                "ISIC_number", "ISIC_class", "CPC_number", "CPC_description" )]))
# check for duplicates
# unique(data.frame(get_dupes(Ecoinv_Reduced_ISIC_CPC[,c("special_activity_type", "product_name","activity_name","unit" )])))

# Join FAO codes based on CPC-to-FAO mapping
CPC_to_FAO<-data.frame(read_xlsx(paste0(input_path,"/Mappings/Mapping_FAO_CPC.xlsx"),
                                 sheet = "srirmam",
                                 col_names = TRUE,
                                 col_types = "text",
                                 range = "A1:E913"))

colnames(CPC_to_FAO)<-c("CPC_V2_code","Blank", "CPC_V2_name","FAO_code","FAO_name")

Eco_Red_ISIC_CPC_FAO<-data.frame(left_join(Ecoinv_Reduced_ISIC_CPC,
                                           CPC_to_FAO[,c("CPC_V2_code","FAO_code","FAO_name" )],
                                           by=c("CPC_number" = "CPC_V2_code")))



### Angelica's mapping
Beltran_Activities<-data.frame(read_xlsx(paste0(input_path, "/Mappings/Mapping_BeltranPaper.xlsx"),
                                         col_names = TRUE,
                                         col_types = "text",
                                         sheet = "BeltranPaper"))

## Clean up ecoinvent names
Beltran_Activities$EcoinvProcClean<-ifelse(substring(Beltran_Activities$Ecoinvent.processes..3.3.,1,1) == "'",
  substring(Beltran_Activities$Ecoinvent.processes..3.3.,2,nchar(Beltran_Activities$Ecoinvent.processes..3.3.)-1),
  Beltran_Activities$Ecoinvent.processes..3.3.)

Beltran_Activities$EcoinvProcClean<-paste0(tolower(substr(Beltran_Activities$EcoinvProcClean,1,1)),
                                           substr(Beltran_Activities$EcoinvProcClean,2,nchar(Beltran_Activities$EcoinvProcClean)))


### WFLDB 3.5 cutoff
WFLDB_3_5_Cutoff<-data.frame(read_xlsx(paste0(input_path,"/WFLDB/WFLDB-3.5_Documentation_Appendix-1_DQR&MainInputs_20191205.xlsx"),
                                       col_names = TRUE,
                                       col_types = "text",
                                       sheet = "2) Datasets and DQR"))

# Split 'category' column
WFLDB_3_5_Cutoff<-cSplit(WFLDB_3_5_Cutoff, "Category", sep = "\\", drop = FALSE, type.convert = FALSE)

names(WFLDB_3_5_Cutoff)[names(WFLDB_3_5_Cutoff) == "Category_1"]<-"WFLDB_Version" # 3.5 phase 1 or 2
names(WFLDB_3_5_Cutoff)[names(WFLDB_3_5_Cutoff) == "Category_2"]<-"ProductCategory" 
#Plant products, Food products, Food processing, Fertilizer, Animal products, Mineral water,
#_sub-dataset, Pesticides (unspecified)

## Note: _sub-datasets have Category_3 entries: Animal production, Plant production, Other, Land use change

names(WFLDB_3_5_Cutoff)[names(WFLDB_3_5_Cutoff) == "Category_3"]<-"ProductSubcategory" # Perennials, Beverages, Dairy etc.
names(WFLDB_3_5_Cutoff)[names(WFLDB_3_5_Cutoff) == "Category_4"]<-"ProductName" # Acai berry, Almond etc.
names(WFLDB_3_5_Cutoff)[names(WFLDB_3_5_Cutoff) == "Category_5"]<-"ProductSubgroup" #co-products, archetypes, feed mixtures
names(WFLDB_3_5_Cutoff)[names(WFLDB_3_5_Cutoff) == "Category_6"]<-"FeedIngredients" #grazed grass, hay, grass silage

# Split 'name' column
WFLDB_3_5_Cutoff<-cSplit(WFLDB_3_5_Cutoff, "Name", sep = "/", drop = FALSE, type.convert = FALSE)

names(WFLDB_3_5_Cutoff)[names(WFLDB_3_5_Cutoff) == "Name_1"]<-"ActivityName" # Barley grain, at farm; Barley grain, irrigated, at farm
names(WFLDB_3_5_Cutoff)[names(WFLDB_3_5_Cutoff) == "Name_2"]<-"Region_1" # also includes a 'U' for unit process;!!! for some activities it reports the unit rather than the region
names(WFLDB_3_5_Cutoff)[names(WFLDB_3_5_Cutoff) == "Name_3"]<-"Region_2" # region + U for special cases (only for GLO and CH)

# Join WFLDB and ecoinvent

WFLDB_Ecoinv<-rbind(unique(Eco_Red_ISIC_CPC_FAO),
                    unique(WFLDB_3_5_Cutoff[,c("ProductCategory", "ProductSubcategory","ProductName","ActivityName",
                                               "Unit","ProductSubgroup","FeedIngredients")]),
                    fill=TRUE)

#write.table(WFLDB_Ecoinv, paste0(output_path,"WFLDB_Ecoinv_Mapping.csv"),row.names = F, sep = ",")

### FAO to IMAGE crops

FAO_to_IMAGE<-data.frame(readxl::read_xlsx(paste0(input_path, "/Mappings/new_IMAGE_16crops_2020_05_26.xlsx"),
                                col_names = TRUE,
                                col_types = "text",
                                sheet = "new_FAO_definitions",
                                range = "F18:J193"))

FAO_to_IMAGE<-na.omit(FAO_to_IMAGE)

### 2) Map data - Angelica <> Ecoinvent ####

BeltranEcoinv1<-data.frame(left_join(Beltran_Activities[,c("IMAGE_NTC2_old","Source","Note","EcoinvProcClean")],
                                     Ecoinv_Reduced,
                                     by=c("EcoinvProcClean"="activity_name") ) )

names(BeltranEcoinv1)[names(BeltranEcoinv1) == "EcoinvProcClean"]<-"activity_name_directMatch"

## Revise mapping
BeltranEcoinv1$activity_name_revised<-BeltranEcoinv1$activity_name_directMatch

# Name mis-match for Solar CSP technologies
BeltranEcoinv1[BeltranEcoinv1$activity_name_directMatch == "electricity production for a 50MW parabolic trough power plant",c("activity_name_revised")]<-c("electricity production, solar thermal parabolic trough, 50 MW")
BeltranEcoinv1[BeltranEcoinv1$activity_name_directMatch == "electricity production at a 20MW solar tower power plant",c("activity_name_revised")]<-c("electricity production, solar tower power plant, 20 MW")

### 3.1) Electricity filters ####
if(Electricity == "True"){
### Isolate relevant sub-sets for more thorough activity-level mapping

## Electricity

# Check available units per activity for electricity related actvities
unlist(unique(Ecoinv_Reduced[Ecoinv_Reduced$special_activity_type == "ordinary transforming activity" &
                               str_detect(Ecoinv_Reduced$product_name,'electricity') ,
                             c("unit")]))

# "kWh"       "km"        "kg"        "unit"      "hour"      "person*km"

# ==> use kWh as an additional filter to generate the subset

# Electricity - transforming
Ecoinv_ElectTransf<-unique(filter(Ecoinv_Reduced[,c("special_activity_type", "product_name","unit")], 
                                  Ecoinv_Reduced$special_activity_type == "ordinary transforming activity" &
                                    Ecoinv_Reduced$unit == "kWh" &
                                    str_detect(Ecoinv_Reduced$product_name,'electricity')))

# Electricity - transforming
Ecoinv_ElectMarket<-unique(filter(Ecoinv_Reduced[,c("special_activity_type", "product_name","unit")], 
                                  (Ecoinv_Reduced$special_activity_type == "market activity" |
                                     Ecoinv_Reduced$special_activity_type == "market group")&
                                    Ecoinv_Reduced$unit == "kWh" &
                                    str_detect(Ecoinv_Reduced$product_name,'electricity')))

# Electricity - transforming
Ecoinv_ElectProdMix<-unique(filter(Ecoinv_Reduced[,c("special_activity_type", "product_name","unit")], 
                                   Ecoinv_Reduced$special_activity_type == "production mix" &
                                     Ecoinv_Reduced$unit == "kWh" &
                                     str_detect(Ecoinv_Reduced$product_name,'electricity')))

Ecoinv_ElectProductFilter<-rbind(Ecoinv_ElectTransf, Ecoinv_ElectProdMix, Ecoinv_ElectMarket)

#write.table(Ecoinv_ElectProductFilter, paste0(check_path,"Ecoinv_ElectProductFilter.csv"),row.names = F, sep = ",")

Ecoinv_ElectProductFilter2<-data.frame(read_xlsx(paste0(input_path, "/IMAGEParameterFiltering/Ecoinv_ElectProductFilter_2020_07_01.xlsx"),
                                                 col_names = TRUE,
                                                 sheet = "Ecoinv_ElectProductFilter"))

# Keep after manual check 
Electricity_ProdNames<-unlist(unique(Ecoinv_ElectProductFilter2[Ecoinv_ElectProductFilter2$InclExcl == "Include" &
                                                                  Ecoinv_ElectProductFilter2$special_activity_type == "ordinary transforming activity",
                                                                c('product_name')]))

Electricity_ProdNames_Markets<-unlist(unique(Ecoinv_ElectProductFilter2[Ecoinv_ElectProductFilter2$InclExcl == "Include" &
                                                                          (Ecoinv_ElectProductFilter2$special_activity_type == "market activity" |
                                                                             Ecoinv_ElectProductFilter2$special_activity_type == "market group"),
                                                                        c('product_name')]))
### 3.2) Electricity technologies ####

FilterEcoinv1<-data.frame(left_join(unique(filter(Ecoinv_Reduced, Ecoinv_Reduced$product_name %in% Electricity_ProdNames &
                                   Ecoinv_Reduced$special_activity_type == "ordinary transforming activity")) ,
                                  unique(BeltranEcoinv1[,c("IMAGE_NTC2_old" , "activity_name_revised","Note")]),
                                   by=c("activity_name" =  "activity_name_revised")
                                   )
                          )

# For electricity we need to exclude activities that represent bilateral trade (i.e. linked to market mix rather than technology)
FilterEcoinv2<-filter(FilterEcoinv1, !str_detect(FilterEcoinv1$activity_name,'import')) 
  # Note: Low voltage electricity is typically linked to HH-level electricity generation
  #       New TIMER technology set includes such technologies => need to be included in new mapping

# write.table(FilterEcoinv2[order(FilterEcoinv2["product_name"], FilterEcoinv2["activity_name"]),], 
 #           paste0(check_path,"FilterEcoinv2Mapping.csv"),row.names = F, sep = ",")

## Read in revised mapping
FilterEcoinv3<-data.frame(readxl::read_xlsx(paste(input_path,"/IMAGEParameterFiltering/FilterEcoinv2Mapping_Adj_2020_07_02.xlsx", sep = ""), 
                                            col_names = TRUE,
                                            na = "NA",
                                            sheet = "FilterEcoinv2Mapping"))

FilterEcoinv3$IMAGE_NTC2<-ifelse(is.na(FilterEcoinv3$IMAGE_NTC2_old),
                                          FilterEcoinv3$IMAGE_NTC2_manual,
                                          FilterEcoinv3$IMAGE_NTC2_old)

# Need to make a manual adjustment for the 'Solar PV' mapping (now two IMAGE technologies)
FilterEcoinv3[FilterEcoinv3[,"IMAGE_NTC2"] == "Solar PV" & !is.na(FilterEcoinv3$IMAGE_NTC2),
              c("IMAGE_NTC2")]<-"Solar PV (central)"

FilterEcoinv4<-unique(FilterEcoinv3[,c("special_activity_type", "product_name","activity_name","unit","IMAGE_NTC2")])

#write.table(FilterEcoinv4, 
 #                     paste0(output_path,"/Ecoinv_ElectTech_Filtered.csv"),row.names = F, sep = ",")

### 3.3) Electricity efficiencies ####
# Note: efficiencies for solar, wind, wave, hydro, geothermal, nuclear = 1 throughout

# search strings (product name and unit)
# coal: hard coal + unit = kg
# lignite: lignite + unit = kg
# oil: heavy fuel oil + unit = kg
# natural gas: natural gas + unit = m3
# biogas: biogas + unit = m3
# wood: wood + unit = kg

Kg_Strings<-c("hard coal","lignite", "heavy fuel oil", "wood chip", "wood pellet")
M3_Strings<-c("natural gas","biogas")

# Filter for the selected strings and join 
Ecoinv_ElectMarket_Eff<-rbind(unique(filter(Ecoinv_Reduced[,c("special_activity_type", "product_name","unit")], 
                                  (Ecoinv_Reduced$special_activity_type == "market activity" |
                                     Ecoinv_Reduced$special_activity_type == "market group") &
                                    Ecoinv_Reduced$unit == "kg" &
                                    str_detect(Ecoinv_Reduced$product_name,paste(Kg_Strings, collapse = "|")))),
                             
                               unique(filter(Ecoinv_Reduced[,c("special_activity_type", "product_name","unit")], 
                                            (Ecoinv_Reduced$special_activity_type == "market activity" |
                                               Ecoinv_Reduced$special_activity_type == "market group") &
                                              Ecoinv_Reduced$unit == "m3" &
                                              str_detect(Ecoinv_Reduced$product_name,paste(M3_Strings, collapse = "|"))))
                              
)

#write.table(Ecoinv_ElectMarket_Eff[order(Ecoinv_ElectMarket_Eff["product_name"]),], 
 #           paste0(output_path,"FilterEcoinv_ElectMarket_Eff.csv"),row.names = F, sep = ",")

## Read in mapped inputs
Ecoinv_ElectMarket_Eff_Mapped<-data.frame(readxl::read_xlsx(paste(input_path,"/IMAGEParameterFiltering/FilterEcoinv_ElectMarket_Eff_2020_07_01.xlsx", sep = ""), 
                                            col_names = TRUE,
                                            na = "",
                                            sheet = "FilterEcoinv_ElectMarket_Eff"))
# If NA then don't update electricity efficiency

Ecoinv_ElectMarket_Eff_Mapped2<-data.frame(left_join(Ecoinv_ElectMarket_Eff_Mapped,
                                                     unique(Ecoinv_Reduced[,c("special_activity_type","product_name","activity_name","unit")]),
                                                     by=c("special_activity_type",
                                                          "product_name",
                                                          "unit")))

#write.table(Ecoinv_ElectMarket_Eff_Mapped2[,c("special_activity_type", "product_name","activity_name", "unit","ScaleUsingLHV"  )], 
 #                      paste0(output_path,"/Ecoinv_ElectEff_Filtered.csv"),row.names = F, sep = ",")

### 3.5) Electricity markets ####

Ecoinv_ElectMarket_Filtered<-data.frame(left_join(filter(Ecoinv_ElectProductFilter2, 
                                                        (Ecoinv_ElectProductFilter2$special_activity_type == "market activity" |
                                                           Ecoinv_ElectProductFilter2$special_activity_type == "market group")
),
unique(Ecoinv_Reduced),
by=c( "special_activity_type", "product_name",   "unit")))

#write.table(Ecoinv_ElectMarket_Filtered[,c("special_activity_type","product_name","activity_name", "unit","InclExcl" )], 
#                       paste0(output_path,"/Ecoinv_ElectMarket_Filtered.csv"),row.names = F, sep = ",")

# Add character 'NA' for blanks for easier processing later on
FilterEcoinv4[is.na(FilterEcoinv4)]<-"NA"
Ecoinv_ElectMarket_Eff_Mapped2[is.na(Ecoinv_ElectMarket_Eff_Mapped2)]<-"NA"
Ecoinv_ElectMarket_Filtered[is.na(Ecoinv_ElectMarket_Filtered)]<-"NA"
### 3.6 Electricity - write out file ####
DF_toWrite_Electricity<-list(
  "Meta" = meta_df,
  "Technologies" = FilterEcoinv4,
  "Efficiencies" = Ecoinv_ElectMarket_Eff_Mapped2[,c("special_activity_type", "product_name","activity_name", "unit","ScaleUsingLHV"  )],
  "Markets" =Ecoinv_ElectMarket_Filtered[,c("special_activity_type","product_name","activity_name", "unit","InclExcl" )]
  
)

if(Write == 'yes'){write.xlsx(DF_toWrite_Electricity,
                              paste0(output_path,"/Ecoinv2IMAGE_Electricity.xlsx"), 
                              row.names=FALSE, 
                              showNA = TRUE)
}

}

## 4.1.1) Crop technologies - WFLDB ####
if(Crops == "True"){
  
  # Look at top-level unique cases to map IMAGE crops to WFLDB crops
  Crops_Level1<-data.frame(unique(WFLDB_Ecoinv[WFLDB_Ecoinv$ProductCategory == 'Plant products' & 
                                                 !WFLDB_Ecoinv$ProductSubcategory == 'Grass for fodder and pasture',
                                                   c("ProductSubcategory","ProductName","ProductSubgroup",'Unit' )]
    
    ))
  
  Crops_Level2<-data.frame(unique(WFLDB_3_5_Cutoff[WFLDB_3_5_Cutoff$ProductCategory == 'Plant products' & 
                                                 !WFLDB_3_5_Cutoff$ProductSubcategory == 'Grass for fodder and pasture',
                                               c("ProductSubcategory","ProductName","ProductSubgroup",'Unit', 'Region_1', 'Region_2' )]
                                  
  ))
  
  # The min should be greater than 1 to be sure that no activity is only defined for 'GLO'
  min(unique(get_dupes(Crops_Level2[,c("ProductSubcategory","ProductName","ProductSubgroup",'Unit')]))[5])
  
  # First try to map to FAO names 
  FilterCrops1<-left_join(Crops_Level1,
                          FAO_to_IMAGE[,c("FAO_name","IMAGE_crop_name")],
                          by=c("ProductName" = "FAO_name"))
  
  names(FilterCrops1)[names(FilterCrops1) == "IMAGE_crop_name"]<-"IMAGE_crop_V1"
  
 # write.table(FilterCrops1[order(FilterCrops1["ProductSubcategory"], FilterCrops1["ProductName"]),], 
  #                       paste0(check_path,"FilterCrops1.csv"),row.names = F, sep = ",")
  
  # Read in the manually adapted mapping (manual map to FAO crops)
  FilterCrops2<-data.frame(read_xlsx(paste0(input_path,"/IMAGEParameterFiltering/FilterCrops1_2020_08_04.xlsx"),
                                     col_names = TRUE,
                                     sheet = "FilterCrops1",
                                     na = "NA"))
  
  FilterCrops2<-left_join(FilterCrops2,
                          FAO_to_IMAGE[,c("FAO_name","IMAGE_crop_name")],
                          by=c("FAO_manual"="FAO_name"))
  
  FilterCrops2$IMAGE_manual<-ifelse(is.na(FilterCrops2$IMAGE_crop_V1),
                                    FilterCrops2$IMAGE_crop_name,
                                    FilterCrops2$IMAGE_crop_V1)
  # still need to add some further manual mappings
  
  filter(FilterCrops2[,c("ProductSubcategory","ProductName","IMAGE_manual")], !complete.cases(FilterCrops2$IMAGE_manual))
 #   ProductSubcategory ProductName IMAGE_manual
 # 1             Arable  Sweet corn         <NA>
  #  2       Horticulture     Parsley         <NA>
   # 3         Perennials  Acai berry         <NA>
  #  4         Perennials  Blackberry         <NA>
   # 5         Perennials  Elderberry         <NA>
  #  6         Perennials      Stevia         <NA>
  # 7         Arable          Guar  
 
  FilterCrops2[FilterCrops2$ProductSubcategory == "Arable" & FilterCrops2$ProductName == "Guar",c("IMAGE_manual")]<-'Pulses'
  # Without the additional 'ProductSubcategory' filter the code returns two rows. Second row is all NA
  FilterCrops2[FilterCrops2$ProductSubcategory == "Arable" & FilterCrops2$ProductName == "Sweet corn",c("IMAGE_manual")]<-'Maize'
  
  FilterCrops2[FilterCrops2$ProductSubcategory == "Horticulture" & FilterCrops2$ProductName == "Parsley",c("IMAGE_manual")]<-'Other non-food, luxury, spices'
  
  FilterCrops2[FilterCrops2$ProductSubcategory == "Perennials" & FilterCrops2$ProductName == "Acai berry",c("IMAGE_manual")]<-'Vegetables & fruits'
   
  FilterCrops2[FilterCrops2$ProductSubcategory == "Perennials" & FilterCrops2$ProductName == "Blackberry",c("IMAGE_manual")]<-'Vegetables & fruits'
  
  FilterCrops2[FilterCrops2$ProductSubcategory == "Perennials" & FilterCrops2$ProductName == "Elderberry",c("IMAGE_manual")]<-'Vegetables & fruits'
  
  FilterCrops2[FilterCrops2$ProductSubcategory == "Perennials" & FilterCrops2$ProductName == "Stevia",c("IMAGE_manual")]<-'Other non-food, luxury, spices'

  # Link mapped data to WFLDB activity names
  
  FilterCrops3<-data.frame(left_join(FilterCrops2[,c("ProductSubcategory","ProductName","ProductSubgroup","Unit", "IMAGE_manual" )],
                                     unique(WFLDB_3_5_Cutoff[,c("ProductSubcategory","ProductName","ProductSubgroup","Unit","ActivityName")])
                                     ))
  
  FilterCrops3$ProductCategory<-'Plant products'
  
  FilterCrops3$Source<-"WFLDB"
  
### 4.1.2) Crop technologies - Ecoinvent ####
  # Filter Ecoinvent data to isolate plant production processes
  Crops_Eco1<-data.frame(unique(WFLDB_Ecoinv[str_detect(WFLDB_Ecoinv$ISIC_class,"Growing"),
                                                 c("special_activity_type","product_name","activity_name","unit","ISIC_number", "ISIC_class",
                                                   "CPC_number","CPC_description","FAO_code","FAO_name"   )]
                                  
  ))
  
  # Join with IMAGE (making use of CPC_to_FAO crop mapping)
  FilterCropsEco1<-data.frame(left_join(Crops_Eco1, # includes all relevant ecoinvent activities
                                        FAO_to_IMAGE[,c("IMAGE_crop_name","FAO_name","FAO_codeLong"  )],
                                        by=c("FAO_code" = "FAO_codeLong")))
  
  
  # Check cases (ISIC and CPC aggregation) with NA for IMAGE_crop_name
  dim(unique(FilterCropsEco1[is.na(FilterCropsEco1$IMAGE_crop_name), c("ISIC_class","CPC_description","IMAGE_crop_name")])) # 24
  
 # write.table(unique(FilterCropsEco1[is.na(FilterCropsEco1$IMAGE_crop_name), c("ISIC_class","CPC_description","IMAGE_crop_name")]),
  #          paste0(check_path,"/FilterCropsEco1_manualCheck.csv"),col.names = TRUE, row.names = FALSE,sep = ",")
  
  # Read in manual decision to include/exclude certain ISIC/CPC identifiers
  FilterCropsEco1_manualCheck<-data.frame(read_xlsx(paste0(input_path,"/IMAGEParameterFiltering/FilterCropsEco1_manualCheck_2020_08_05.xlsx"),
                                                    col_names = TRUE,
                                                    sheet = "FilterCropsEco1_manualCheck"))
  
  # Re-join with full ecoinvent activity information
  FilterCropsEco2<-data.frame(left_join(
    FilterCropsEco1, 
    subset(FilterCropsEco1_manualCheck, select = -c(IMAGE_crop_name)),
    by=c("ISIC_class","CPC_description")
  ))
  
  # Check which IMAGE crops have been assigned based on CPC_to_FAO mapping and add additional mapping for missing cases
  FilterCropsEco3<-unique(FilterCropsEco2[FilterCropsEco2$InclExcl == "Incl",c( "ISIC_class","CPC_description","IMAGE_crop_name")])
  
 # write.table(unique(FilterCropsEco3),
  #                      paste0(check_path,"/FilterCropsEco3.csv"),col.names = TRUE, row.names = FALSE,sep = ",")
  
  FilterCropsEco3_manual<-data.frame(read_xlsx(paste0(input_path,'/IMAGEParameterFiltering/FilterCropsEco3_2020_08_05.xlsx'),
                                               col_names = TRUE,
                                               sheet = "FilterCropsEco3",
                                               na = "NA"))
  
  # Re-join with full ecoinvent activity information
  FilterCropsEco4<-data.frame(left_join(FilterCropsEco2,
                                        subset(FilterCropsEco3_manual,select = -c(IMAGE_crop_name)),
                                        by=c("ISIC_class","CPC_description")))
  
  FilterCropsEco4$IMAGE_manual<-ifelse(is.na(FilterCropsEco4$IMAGE_crop_name),
                                       FilterCropsEco4$IMAGE_crop_V1,
                                       FilterCropsEco4$IMAGE_crop_name)
  
  # Reduce dataframe to unique cases without FAO names and codes and keep entries with mapping to IMAGE
  
  FilterCropsEco5<-unique(FilterCropsEco4[complete.cases(FilterCropsEco4$IMAGE_manual),
                             c("special_activity_type","product_name","activity_name","unit","ISIC_number","ISIC_class", 
                               "CPC_number","CPC_description", "IMAGE_manual" )])
  
  # Check for duplicate mappings between just ecoinvent and IMAGE
 # get_dupes(FilterCropsEco5[,c("special_activity_type","product_name","activity_name","unit")])
  
#  special_activity_type          product_name activity_name         unit  dupe_count
 # <chr>                          <chr>        <chr>                 <chr>      <int>
#    1 ordinary transforming activity sugar beet   sugar beet production kg             2
#  2 ordinary transforming activity sugar beet   sugar beet production kg             2
  
  # ==> OK, assigned to the same IMAGE crop; duplication due to two possible ISIC classes
  FilterCropsEco5$Source<-"Ecoinvent"
  
### 4.1.3) Crop technologies - joint filter #### 
  
  FilterCropsEco_WFLDB1<-smartbind(FilterCropsEco5, FilterCrops3)
  
  # match IMAGE identified key to key used in IMAGE data
  names(FilterCropsEco_WFLDB1)[names(FilterCropsEco_WFLDB1) =="IMAGE_manual"]<-"NFCT_mod"
  
  # re-link with original WFLDB identifiers
  FilterCropsEco_WFLDB2<-data.frame(left_join(FilterCropsEco_WFLDB1,
                                              unique(WFLDB_3_5_Cutoff[,c("Category","ProductCategory","ProductSubcategory",
                                                                         "ProductName","ProductSubgroup", "ActivityName" )]),
                                                     by=c("ProductCategory","ProductSubcategory",
                                                          "ProductName","ProductSubgroup", "ActivityName")))
  # Note: 7 crops are now duplicated because they are included in WFLDB Phase 1 and Phase 2, respectively
  
  # Technologies
  CropsEco_WFLDB_Tech<-filter(FilterCropsEco_WFLDB2, FilterCropsEco_WFLDB2$special_activity_type == "ordinary transforming activity" |
                                is.na(FilterCropsEco_WFLDB2$special_activity_type))
  
  # Identify as irrigated or rainfed 

  CropsEco_WFLDB_Tech$NFCAREAT<-ifelse((str_detect(CropsEco_WFLDB_Tech$ActivityName, 'irrigated') &
                                          !str_detect(CropsEco_WFLDB_Tech$ActivityName, 'non-irrigated')),
                                       'irrigated',
                                       'rainfed')

#  write.table(unique(CropsEco_WFLDB_Tech[,c( "special_activity_type","product_name","activity_name", "unit",
 #                                         #  "ProductCategory",  "ProductSubcategory", "ProductName", "ProductSubgroup", 
  #                                          "Category", "ActivityName", "Unit",
   #                                          "Source", "NFCT_mod","NFCAREAT")]),
    #          paste0(output_path,"/EcoWFLDB_CropTech_Filtered.csv"),
     #         row.names = F, sep = ",")
  
# Add character 'NA' for blanks for easier processing later on
  CropsEco_WFLDB_Tech[is.na(CropsEco_WFLDB_Tech)]<-"NA"
 ### 4.3.4 Crops - write out file ####
 DF_toWrite_Crops<-list(
   "Meta" = meta_df,
   "Technologies" = unique(CropsEco_WFLDB_Tech[,c( "special_activity_type","product_name","activity_name", "unit",
                                                   #  "ProductCategory",  "ProductSubcategory", "ProductName", "ProductSubgroup", 
                                                   "Category", "ActivityName", "Unit",
                                                   "Source", "NFCT_mod","NFCAREAT")])
   
 )

 
 if(Write == 'yes'){write.xlsx(DF_toWrite_Crops,
                               paste0(output_path,"/EcoinvWFLDB2IMAGE_Crops.xlsx"), 
                               row.names=FALSE, 
                               showNA = TRUE)
 }
 
}

if(Livestock == "True"){
  ### 5.1 Livestock filters - WFLDB ####

  # Check animal activities
  ## ProductCategory == Animal products
  ### ProductSubcategory == At farm  [At slaughterhouse excluded)]
  ### ProductName == Different livestock
  ### ProductSubgroup == NA ('market mix'); Archetypes (production activity)
  ### Unit == kg (Poultry husbandry would have unit day)
  unique(filter(WFLDB_3_5_Cutoff[,c("ProductCategory","ProductSubcategory",
                                    "ProductName","ProductSubgroup","Unit" )],
                WFLDB_3_5_Cutoff$ProductCategory == "Animal products" &
                  WFLDB_3_5_Cutoff$ProductSubcategory == "At farm" &
                  WFLDB_3_5_Cutoff$Unit == "kg"))
  
  # Check for GLO datasets that need to be excluded
 ToExcludeLivestockGLO<-unlist(unique(filter(WFLDB_3_5_Cutoff[,c("ProductCategory","ProductSubcategory",
                                    "ProductName","ProductSubgroup","ActivityName", "Unit" ,"Region_1")],
                WFLDB_3_5_Cutoff$ProductCategory == "Animal products" &
                  WFLDB_3_5_Cutoff$ProductSubcategory == "At farm" &
                  # WFLDB_3_5_Cutoff$ProductName == "Poultry" &
                  WFLDB_3_5_Cutoff$Unit == "kg"& WFLDB_3_5_Cutoff$Region_1 == "GLO U")
         
  )[5])
  
  # Check animal inputs
  ### ProductSubcategory == Animal production 
  ### ProductName == Feed; Cattle (linked to infrastructure); Poultry (linked to infrastructure)
  ###               ; Swine (linked to infrastructure); Slautherhouse (exclude); Specific emissions; Manure management
  ### ProductSubgroup == Feed mixtures; Feed processes; Feed baskets; Feed Ingredients (Housing, Diary farm management excluded)

  unique(filter(WFLDB_3_5_Cutoff[,c("ProductCategory","ProductSubcategory",
                                    "ProductName","ProductSubgroup","Unit" )],
                WFLDB_3_5_Cutoff$ProductSubcategory == "Animal production" &
               (WFLDB_3_5_Cutoff$ProductName == "Feed" |
                  WFLDB_3_5_Cutoff$ProductName == "Specific emissions" |
                  WFLDB_3_5_Cutoff$ProductName == "Manure management"
                )))
  
  
### 5.2 Livestock technologies  ####
  FilterLivest1<-data.frame(rbind(
    unique(filter(WFLDB_3_5_Cutoff[,c("ProductCategory","ProductSubcategory",
                                                                "ProductName","ProductSubgroup","ActivityName", "Unit" )],
                    WFLDB_3_5_Cutoff$ProductCategory == "Animal products" &
                    WFLDB_3_5_Cutoff$ProductSubcategory == "At farm" &
                    !WFLDB_3_5_Cutoff$ProductName == "Poultry" & # Poultry doesn't have an archetype, incl separately
                    WFLDB_3_5_Cutoff$ProductSubgroup == "Archetypes" &
                    WFLDB_3_5_Cutoff$Unit == "kg" )),
    unique(filter(WFLDB_3_5_Cutoff[,c("ProductCategory","ProductSubcategory",
                                      "ProductName","ProductSubgroup","ActivityName", "Unit" )],
                    WFLDB_3_5_Cutoff$ProductCategory == "Animal products" &
                    WFLDB_3_5_Cutoff$ProductSubcategory == "At farm" &
                    WFLDB_3_5_Cutoff$ProductName == "Poultry" &
                    WFLDB_3_5_Cutoff$Unit == "kg" )
      
    )))
  
  # map to IMAGE livestock (NA: non-dairy cattle, dairy cattle, pigs, sheep & goats, poultry)
  Dairy<-c("Dairy cattle","Raw milk")
  
  FilterLivest1$'NA'<-ifelse(FilterLivest1$ProductName == "Beef cattle", "non-dairy cattle",
                             ifelse(FilterLivest1$ProductName %in% Dairy , "dairy cattle",
                                    ifelse(FilterLivest1$ProductName == "Swine","pigs",
                                           ifelse(FilterLivest1$ProductName == "Lamb","sheep & goats",
                                                  ifelse(FilterLivest1$ProductName == "Poultry", "poultry",
                                                         "NA")))))
  
  # map to livestock system (NGST: intensive grazing system, extensive grazing system, total)
  
  String_intensive<-c('feedlot or intensive system', 'industrial')
  String_extensive<-c('grassland system', 'backyard')
  
  FilterLivest1$NGST<-ifelse(str_detect(FilterLivest1$ActivityName, paste(String_intensive, collapse = "|")),
                             "intensive grazing system",
                             ifelse(str_detect(FilterLivest1$ActivityName, paste(String_extensive, collapse = "|")),
                                               "extensive grazing system", "total"
                                                ))
  ## Note: all dairy systems are assigend to 'total' because the specification of the WFLDB datasets doens't
  ##      allow for a systematic destiction between extensive and intensive
  
  # Re-join with original WFLDB identifiers
  FilterLivest2<-data.frame(left_join(FilterLivest1,
                                      unique(WFLDB_3_5_Cutoff[,c("Category","ProductCategory","ProductSubcategory",
                                                          "ProductName","ProductSubgroup","ActivityName", "Unit")])
                                      ))
  
  names(FilterLivest2)[names(FilterLivest2) == "NA."]<-"NA"

  # Write out Category, ActivityName, Unit, NA, NGST
 # write.table(unique(FilterLivest2[,c( # "ProductCategory", "ProductSubcategory", "ProductName", "ProductSubgroup", 
  #                                            "Category", "ActivityName", "Unit",
   #                                           "NA","NGST")]),
    #          paste0(output_path,"WFLDB_LivestTech_Filtered.csv"),
     #         row.names = F, sep = ",")
  
  ### 5.3 Livestock effiencies ####
  Livestock_Inputs_Incl<-c('Feed',"Manure management","Specific emissions")
  Livestock_Inputs_Excl<-c("Feed mixtures","Feed Ingredients","Feed processes")
  Livestock_SpeficEmissions<-c("Enteric") # The other emissions enter the livestock activites via the feed components (e.g. grazed grass)
  
  FilterLivest_Eff1<-data.frame(rbind(unique(filter(WFLDB_3_5_Cutoff[,c("ProductCategory","ProductSubcategory",
                                                         "ProductName","ProductSubgroup","ActivityName", "Unit" )],
                                     WFLDB_3_5_Cutoff$ProductSubcategory == "Animal production" &
                                     WFLDB_3_5_Cutoff$ProductName %in% Livestock_Inputs_Incl[1:2] &
                                       !WFLDB_3_5_Cutoff$ProductSubgroup %in% Livestock_Inputs_Excl
                                       
                                     )),
                             # separate treatment for specific emissions (only include activites with 'enteric' in name)
                                     unique(filter(WFLDB_3_5_Cutoff[,c("ProductCategory","ProductSubcategory",
                                                                       "ProductName","ProductSubgroup","ActivityName", "Unit" )],
                                            WFLDB_3_5_Cutoff$ProductSubcategory == "Animal production" &
                                            WFLDB_3_5_Cutoff$ProductName %in% Livestock_Inputs_Incl[3] &
                                            str_detect(WFLDB_3_5_Cutoff$ActivityName,paste(Livestock_SpeficEmissions))
                                     
                                     )) 
                                     ))
  
  # Feed storage and transported is calculated using DM intake as a key component, so we'll also need to 
  # filter storage and transport options as inputs that should be scaled using feed efficiency
  FilterLivest_Eff2<-data.frame(rbind(
    unique(filter(WFLDB_3_5_Cutoff[,c("ProductCategory","ProductSubcategory",
                                      "ProductName","ProductSubgroup","ActivityName", "Unit" ) ],
                  WFLDB_3_5_Cutoff$ProductSubcategory == "Animal production" &
                 str_detect(WFLDB_3_5_Cutoff$ActivityName,'Feed storage and transport')
                  )),
    unique(filter(WFLDB_3_5_Cutoff[,c("ProductCategory","ProductSubcategory",
                                      "ProductName","ProductSubgroup","ActivityName", "Unit" ) ],
                    WFLDB_3_5_Cutoff$ProductSubcategory == "Plant production" &
                    WFLDB_3_5_Cutoff$ProductName == "Installations" &
                    str_detect(WFLDB_3_5_Cutoff$ActivityName, paste(list('storage', 'silo'), collapse = "|")) &
                    WFLDB_3_5_Cutoff$Unit == "m3" 
                   
                  ))
        ))
  
  # Bring together
  FilterLivest_Eff3<-rbind(FilterLivest_Eff1, FilterLivest_Eff2)
  
  # Re-join with original WFLDB identifiers
  FilterLivest_Eff4<-data.frame(left_join(FilterLivest_Eff3,
                                      unique(WFLDB_3_5_Cutoff[,c("Category","ProductCategory","ProductSubcategory",
                                                                 "ProductName","ProductSubgroup","ActivityName", "Unit")])
  ))
  # Write out Category, ActivityName, Unit, NA, NGST
 # write.table(unique(FilterLivest_Eff4[,c( # "ProductCategory", "ProductSubcategory", "ProductName", "ProductSubgroup", 
  #  "Category", "ActivityName", "Unit")]),
   # paste0(output_path,"WFLDB_LivestEff_Filtered.csv"),
    #row.names = F, sep = ",")
  
  ### 5.4 Livestock feed basket compositions ####
  
  # Link the feed baskets to the relavant IMAGE livestock and systems
  FilterLivest_FeedBaskets1<-data.frame(unique(filter(
    WFLDB_3_5_Cutoff[,c("ProductCategory","ProductSubcategory",
                        "ProductName","ProductSubgroup","ActivityName", "Unit" ) ],
    WFLDB_3_5_Cutoff$ProductSubcategory == "Animal production" &
      WFLDB_3_5_Cutoff$ProductName == "Feed" &
      WFLDB_3_5_Cutoff$ProductSubgroup == "Feed baskets"
  )))
  
  FilterLivest_FeedBaskets1$'NA'<-ifelse(str_detect(FilterLivest_FeedBaskets1$ActivityName, "beef"), "non-dairy cattle",
                                         ifelse(str_detect(FilterLivest_FeedBaskets1$ActivityName, "swine"), "pigs",
                                                ifelse(str_detect(FilterLivest_FeedBaskets1$ActivityName, "lamb"), "sheep & goats",
                                                       ifelse(str_detect(FilterLivest_FeedBaskets1$ActivityName, "poultry"), "poultry",
                                                                     "NA"))))  
  FilterLivest_FeedBaskets1$NGST<- ifelse(str_detect(FilterLivest_FeedBaskets1$ActivityName, paste(String_intensive, collapse = "|")),
                                          "intensive grazing system",
                                          ifelse(str_detect(FilterLivest_FeedBaskets1$ActivityName, paste(String_extensive, collapse = "|")),
                                                 "extensive grazing system", "total"
                                          )) 
  # Re-join with original WFLDB identifiers
  FilterLivest_FeedBaskets2<-data.frame(left_join(FilterLivest_FeedBaskets1,
                                          unique(WFLDB_3_5_Cutoff[,c("Category","ProductCategory","ProductSubcategory",
                                                                     "ProductName","ProductSubgroup","ActivityName", "Unit")])
  ))
  
  names(FilterLivest_FeedBaskets2)[names(FilterLivest_FeedBaskets2) == "NA."]<-"NA"
  
  # Write out baskets
#  write.table(unique(FilterLivest_FeedBaskets2[,c( # "ProductCategory", "ProductSubcategory", "ProductName", "ProductSubgroup", 
 #   "Category", "ActivityName", "Unit",
  #  "NA","NGST")]),
   # paste0(output_path,"WFLDB_LivestBaskets_Filtered.csv"),
    #row.names = F, sep = ",")
  
  ###
  
  # Isolate the ingredients of the feed baskets and feed rations (dairy cattle)  
  FilterLivest_Feed1<-data.frame(rbind(
    # General ingredients of feed baskets
    unique(filter(WFLDB_3_5_Cutoff[,c("ProductCategory","ProductSubcategory",
                                      "ProductName","ProductSubgroup","ActivityName", "Unit" ) ],
                  WFLDB_3_5_Cutoff$ProductSubcategory == "Animal production" &
                    WFLDB_3_5_Cutoff$ProductName == "Feed" &
                    WFLDB_3_5_Cutoff$ProductSubgroup == "Feed mixtures"
    )),
    # Grass inputs (used directly by dairy cattle)
    unique(filter(WFLDB_3_5_Cutoff[,c("ProductCategory","ProductSubcategory",
                                      "ProductName","ProductSubgroup","ActivityName", "Unit" ) ],
                  WFLDB_3_5_Cutoff$ProductSubcategory == "Animal production" &
                    WFLDB_3_5_Cutoff$ProductName == "Feed" &
                    WFLDB_3_5_Cutoff$ProductSubgroup == "Feed Ingredients" &
                    WFLDB_3_5_Cutoff$FeedIngredients == "Grazed grass" &
                    str_detect(WFLDB_3_5_Cutoff$ActivityName, paste(list('country mix', 'regional mix','global mix'), 
                                                                    collapse = "|"))
    )),
    # Hay used by dairy cattle
    unique(filter(WFLDB_3_5_Cutoff[,c("ProductCategory","ProductSubcategory",
                                      "ProductName","ProductSubgroup","ActivityName", "Unit" ) ],
                  WFLDB_3_5_Cutoff$ProductSubcategory == "Animal production" &
                    WFLDB_3_5_Cutoff$ProductName == "Feed" &
                    WFLDB_3_5_Cutoff$ProductSubgroup == "Feed Ingredients" &
                    WFLDB_3_5_Cutoff$FeedIngredients == "Hay" &
                    str_detect(WFLDB_3_5_Cutoff$ActivityName, paste(list('production mix'), 
                                                                    collapse = "|"))
    ))
  )  )
  
  # Write out feed inputs for manual mapping to IMAGE
 # write.table(FilterLivest_Feed1, paste0(check_path,"FilterLivest_Feed1.csv"),row.names = F, sep = ",")
  
  FilterLivest_Feed2<-data.frame(readxl::read_xlsx(paste0(input_path,"/IMAGEParameterFiltering/FilterLivest_Feed1_2020_08_19.xlsx"), 
                                                   col_names = TRUE,
                                                   col_types = "text",
                                                   sheet = "FilterLivest_Feed1"))
  # Re-join with original WFLDB identifiers
  FilterLivest_Feed3<-data.frame(left_join(FilterLivest_Feed2,
                                                  unique(WFLDB_3_5_Cutoff[,c("Category","ProductCategory","ProductSubcategory",
                                                                             "ProductName","ProductSubgroup","ActivityName", "Unit")])
  ))
  

  # Write out feed ingredients
  
#  write.table(unique(FilterLivest_Feed3[,c( # "ProductCategory", "ProductSubcategory", "ProductName", "ProductSubgroup", 
 #   "Category", "ActivityName", "Unit",
  #  "NFP")]),
   # paste0(output_path,"WFLDB_LivestFeedInpt_Filtered.csv"),
    #row.names = F, sep = ",")
  
  ### 5.5 Livestock (dairy cattle) parameter ####
  Livest_Parameters1<-data.frame(cbind( c("Pas", "HPas",
                                   "Hay", "HHay",
                                   "Grain", "HGrain",
                                   "Prot", "HProt"),
                                 c("grass & fodder","grass & fodder",
                                   "grass & fodder","grass & fodder",
                                   "food crops", "food crops",
                                   "grass & fodder","grass & fodder"
                                   
                                   )))
  
  colnames(Livest_Parameters1)<-c("WFLDB","NFPT")
  
  # Write out parameters
#  write.table(unique(Livest_Parameters1[,c( "WFLDB","NFP")]),
 #   paste0(output_path,"WFLDB_LivestFeedInpt_Parameters_Filtered.csv"),
  #  row.names = F, sep = ",")
  # Add character 'NA' for blanks for easier processing later on
  FilterLivest2[is.na(FilterLivest2)]<-"NA"
  FilterLivest_Eff4[is.na(FilterLivest_Eff4)]<-"NA"
  FilterLivest_FeedBaskets2[is.na(FilterLivest_FeedBaskets2)]<-"NA"
  FilterLivest_Feed3[is.na(FilterLivest_Feed3)]<-"NA"
  Livest_Parameters1[is.na(Livest_Parameters1)]<-"NA"
  
### 5.6 Livestock - write out file ####
  DF_toWrite_Livestock<-list(
    "Meta" = meta_df,
    "Technologies" = unique(FilterLivest2[,c( "Category", "ActivityName", "Unit","NA","NGST")]),
    "LivestEff" = unique(FilterLivest_Eff4[,c("Category", "ActivityName", "Unit")]),
    "LivestBaskets" = unique(FilterLivest_FeedBaskets2[,c( "Category", "ActivityName", "Unit","NA","NGST")]),
    "LivestFeedInpt" = unique(FilterLivest_Feed3[,c( "Category", "ActivityName", "Unit","NFPT")]),
    "LivestFeedInpt_Parameters" = unique(Livest_Parameters1[,c( "WFLDB","NFPT")])
  )
  
  if(Write == 'yes'){write.xlsx(DF_toWrite_Livestock, 
                                paste0(output_path,"/WFLDB2IMAGE_Livestock.xlsx"), 
                                row.names=FALSE)
  }

}
