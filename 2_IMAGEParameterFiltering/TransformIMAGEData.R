####
rm(list = ls())

# Settings ####
###

out_date<-format(Sys.Date(),'%Y_%m_%d')

# Write out results 
Write<- "yes"  # yes or no

Scenarios<-c("SSP1","SSP2","SSP3")

MappingsFileDate<-"2020_08_11"


meta_df<-data.frame(cbind("date",out_date))

# Set mappings that are to be done
Energy<-"True" # True or False
Agriculture<-"True"

# Packages
packages<-c("data.table","fuzzyjoin", "dplyr","openxlsx", "plyr", 
            "readxl","rgdal","splitstackshape", "stringr","tidyverse" )

req<-substitute(require(x, character.only = TRUE))
sapply(packages, function(x) eval(req) || {install.packages(x); eval(req)})

# Paths
input_path<-paste0(dirname(getwd()),"/888_InputData/")

check_path<-paste0(dirname(getwd()),"/Checks/")

for(Scen in Scenarios){
  print(paste0("Processing data for scenario ",Scen))
  
  output_path<-paste0(dirname(getwd()),"/999_Output/IMAGEParameterFiltering/",Scen,"/" )
  if(!dir.exists(output_path)) {dir.create(output_path)}
  
  #### 1) Read input data #####
  
  ## Mappings
  IMAGE_Reg0<-data.frame(readxl::read_xlsx(paste0(input_path,"/Mappings/Mappings_IMAGE_", MappingsFileDate,".xlsx"), 
                                           col_names = TRUE,
                                           col_types = "text",
                                           na = "",
                                           sheet = "IMAGE_Regions"))
  # Energy
  IMAGE_Tech_Elect0<-data.frame(readxl::read_xlsx(paste0(input_path,"/Mappings/Mappings_IMAGE_", MappingsFileDate,".xlsx"), 
                                                  col_names = TRUE,
                                                  col_types = "text",
                                                  sheet = "TIMER_TechElectricity"))
  
  # Agriculture
  IMAGE_ID_Crops0<-data.frame(readxl::read_xlsx(paste0(input_path,"/Mappings/Mappings_IMAGE_", MappingsFileDate,".xlsx"), 
                                                col_names = TRUE,
                                                col_types = "text",
                                                sheet = "IMAGE_Area",
                                                range = "A1:D38",
                                                na = ""))
  
  ## Data
  if(Energy == "True"){
    TIMER_ElecProdSpec3_0<-data.frame(readxl::read_xlsx(paste0(input_path,"/IMAGE/",Scen,"_TIMER_3_11_Results_2020_10_30.xlsx"), 
                                                        col_names = TRUE,
                                                        sheet = "ElecProdSpec3",
                                                        range = "A4:AF3644"))
    
    TIMER_ElecEffAvg_0<-data.frame(readxl::read_xlsx(paste0(input_path,"/IMAGE/",Scen,"_TIMER_3_11_Results_2020_10_30.xlsx"), 
                                                     col_names = TRUE,
                                                     sheet = "ElecEffAvg",
                                                     range = "A4:AF3384"))
    
    
    
    TIMER_NuclFuelEff_0<-data.frame(readxl::read_xlsx(paste0(input_path,"/IMAGE/",Scen,"_TIMER_3_11_Results_2020_10_30.xlsx"), 
                                                      col_names = TRUE,
                                                      sheet = "NuclFuelEff",
                                                      range = "A4:AB134"))
  }
  
  if(Agriculture == "True"){
    
    
    IMAGE_CropYield0<-data.frame(readxl::read_xlsx(paste0(input_path,"/IMAGE/",Scen,"_IM32.xlsx"), 
                                                   col_names = TRUE,
                                                   sheet = "YIELD_DM",
                                                   range = "A5:AD6686"))
    
    
    IMAGE_FeedEff0<-data.frame(readxl::read_xlsx(paste0(input_path,"/IMAGE/",Scen,"_IM32.xlsx"), 
                                                 col_names = TRUE,
                                                 sheet = "FEEDEFF",
                                                 range = "A5:AE14153"))
    
    
    
  }
  
  
  ### 2) Transpose data to pivot format ####
  
  ### 2.1.1) Electricity ####
  if(Energy == "True"){
    ## Electricity production - t, NRCT, NTC2 [GJ electric]
    
    TIMER_ElecProd_1<-data.frame(TIMER_ElecProdSpec3_0%>%pivot_longer(cols=starts_with("class"),
                                                                      names_to = "DIM_2",
                                                                      values_to = "Value"))
    
    TIMER_ElecProd_1$NRCT_Code<-as.character(TIMER_ElecProd_1$DIM_.1)
    
    # Keep only the code
    TIMER_ElecProd_1$NTC2_Code<-str_extract(TIMER_ElecProd_1$DIM_2,"(\\d)+")
    
    # Join with appropriate identifiers
    TIMER_ElecProd_2<-data.frame(left_join(TIMER_ElecProd_1,
                                           IMAGE_Reg0[,c("Code","NRCT")],
                                           by=c("NRCT_Code" = "Code")))
    
    TIMER_ElecProd_2<-data.frame(left_join(TIMER_ElecProd_2,
                                           IMAGE_Tech_Elect0[,c("Code","NTC2")],
                                           by=c("NTC2_Code" = "Code")))
    
    # Note: NA for NTC2 => NTC2_Code = 10; NA for NRCT => NRCT_Code = 27 ==> ok
    
    TIMER_ElecProd_3<-filter(TIMER_ElecProd_2, !TIMER_ElecProd_2$NRCT_Code == "27" &
                               !TIMER_ElecProd_2$NRCT_Code == "28",
                             !TIMER_ElecProd_2$NTC2_Code == "10")
    
    TIMER_ElecProd_3$Unit<-"GJ_electric"
    
    # Since we've omitted the empty regional code and the world sum, we can re-label the region code/name
    names(TIMER_ElecProd_3)[names(TIMER_ElecProd_3) == "NRCT_Code"]<-"NRC2_Code"
    names(TIMER_ElecProd_3)[names(TIMER_ElecProd_3) == "NRCT"]<-"NRC2"
    
    
    ## Electricity efficiency - t, NRC2, NTC2 [GJ electric/ GJ fuel]
    
    TIMER_ElecEff_1<-data.frame(TIMER_ElecEffAvg_0%>%pivot_longer(cols=starts_with("class"),
                                                                  names_to = "DIM_2",
                                                                  values_to = "Value"))
    
    TIMER_ElecEff_1$NRC2_Code<-as.character(TIMER_ElecEff_1$DIM_.1)
    
    # Keep only the code
    TIMER_ElecEff_1$NTC2_Code<-str_extract(TIMER_ElecEff_1$DIM_2,"(\\d)+")
    
    # Join with appropriate identifiers
    TIMER_ElecEff_2<-data.frame(left_join(TIMER_ElecEff_1,
                                          IMAGE_Reg0[,c("Code","NRC2")],
                                          by=c("NRC2_Code" = "Code")))
    
    TIMER_ElecEff_2<-data.frame(left_join(TIMER_ElecEff_2,
                                          IMAGE_Tech_Elect0[,c("Code","NTC2")],
                                          by=c("NTC2_Code" = "Code")))
    
    # Note: NA for NTC2 => NTC2_Code = 10 ==> ok
    
    TIMER_ElecEff_3<-filter(TIMER_ElecEff_2, 
                            !TIMER_ElecEff_2$NTC2_Code == "10")
    
    TIMER_ElecEff_3$Unit<-"GJ_electric_GJ_fuel"
    
    
    
    ### 2.1.2) Nuclear ####
    
    ## Nuclear efficiency - t, NRC [GJ electric/GJ fuel]
    
    TIMER_NuclEff_1<-data.frame(TIMER_NuclFuelEff_0%>%pivot_longer(cols=starts_with("class"),
                                                                   names_to = "DIM_2",
                                                                   values_to = "Value"))
    
    TIMER_NuclEff_1$NRC_Code<-str_extract(TIMER_NuclEff_1$DIM_2,"(\\d)+")
    
    # Join with appropriate identifiers
    TIMER_NuclEff_2<-data.frame(left_join(TIMER_NuclEff_1,
                                          IMAGE_Reg0[,c("Code","NRC")],
                                          by=c("NRC_Code" = "Code")))
    
    
    TIMER_NuclEff_3<-filter(TIMER_NuclEff_2, !TIMER_NuclEff_2$NRC_Code == "27")
    
    # Note: no NAs
    
    TIMER_NuclEff_3$Unit<-"GJ_electric_GJ_fuel"
    
    # Since we've omitted the empty regional code and the world sum, we can re-label the region code/name
    names(TIMER_NuclEff_3)[names(TIMER_NuclEff_3) == "NRC_Code"]<-"NRC2_Code"
    names(TIMER_NuclEff_3)[names(TIMER_NuclEff_3) == "NRC"]<-"NRC2"
    
    ### 2.1.3) Output files - Energy ####
    
    # Electricity
    DF_toWrite_Electricity<-list(

      "ElecProdSpec3" = TIMER_ElecProd_3[,c("t","NRC2_Code","NRC2","NTC2_Code","NTC2","Unit","Value")],
      "ElecEffAvg" = TIMER_ElecEff_3[,c("t","NRC2_Code","NRC2","NTC2_Code","NTC2","Unit","Value")],
      
      "NuclFuelEff" = TIMER_NuclEff_3[,c("t","NRC2_Code","NRC2","Unit","Value")],
      "Meta" = meta_df
      
    )
    
    if(Write == 'yes'){write.xlsx(DF_toWrite_Electricity, 
                                  paste0(output_path,"/IMAGE_Electricity_",Scen,".xlsx"), 
                                  row.names=FALSE)
    }
    
    
    
  } # closes Energy == True
  
  
  if(Agriculture == "True"){
    
    ### 2.2) Crop data ####
    ## YIELD_DM - t, NFCAREAT,NFCT, NRT [Gg dm/km2]
    
    IMAGE_Yield_1<-data.frame(IMAGE_CropYield0%>%pivot_longer(cols= Canada:World,
                                                              names_to = "NRT_intermed",
                                                              values_to = "Value")) 
    # Need to re-label the regions for NRT
    Labels_NRT_intermed<-data.frame(unique(IMAGE_Yield_1$NRT_intermed))
    
    colnames(Labels_NRT_intermed)[1]<-"NRT_intermed"
    
    Labels_NRT_intermed$NRT_Code<-as.character(seq.int(nrow(Labels_NRT_intermed)))
    Labels_NRT_intermed$NRT_intermed<-as.character(Labels_NRT_intermed$NRT_intermed)
    
    Labels_NRT_intermed<-left_join(Labels_NRT_intermed,
                                   IMAGE_Reg0[,c("Code","NRC2", "NRT")],
                                   by=c("NRT_Code" = "Code"))
    
    # Need to re-label the regions for NRT
    
    IMAGE_Yield_2<-data.frame(left_join(IMAGE_Yield_1,
                                        Labels_NRT_intermed,
                                        by=c("NRT_intermed")))
    
    # Harmonize crop mapping (from NFCT to NFCT_mod
    IMAGE_Yield_3<-data.frame(left_join(IMAGE_Yield_2,
                                        IMAGE_ID_Crops0[,c("Code","NGFBFC","NFCT_mod")],
                                        by=c("NFCT"="NGFBFC")))
    
    IMAGE_Yield_3$Unit <- "Gg_dm_per_km2"
    
    # Subset data to desired identifiers
    IMAGE_Yield_4<-IMAGE_Yield_3[!IMAGE_Yield_3$NRT_Code == "27" & # exclude 'World'
                                   !IMAGE_Yield_3$NFCAREAT == "total" &
                                   !IMAGE_Yield_3$NFCT == "Total",
                                 c("t", "NRT_Code","NRC2","Code","NFCT_mod","NFCAREAT","Unit", "Value")]
    
    
    
    colnames(IMAGE_Yield_4)<-c("t", "NRC2_Code","NRC2","NFCT_NFCAREAT_Code", "NFCT_mod","NFCAREAT","Unit", "Value")
    
    # Areas and crops
    DF_toWrite_Area_Yield<-list(

      "YIELD_DM" = IMAGE_Yield_4,
      "Meta" = meta_df
      
    )
    
    if(Write == 'yes'){write.xlsx(DF_toWrite_Area_Yield, 
                                  paste0(output_path,"/IMAGE_Area_CropYield_",Scen,".xlsx"), 
                                  row.names=FALSE)
    }
    
    ### 2.3) Feed efficiency ####
    ## FEEDEFF - t, NGST, NFPT, NAT, NRT [kg dm/kg product]
    
    IMAGE_FeedEff_1<-data.frame(IMAGE_FeedEff0%>%pivot_longer(cols = Canada:World,
                                                              names_to = "NRT_intermed",
                                                              values_to = "Value"))
    
    # Re-label regions for NRT
    IMAGE_FeedEff_2<-data.frame(left_join(IMAGE_FeedEff_1,
                                          Labels_NRT_intermed,
                                          by=c("NRT_intermed")))
    
    # Add unit
    IMAGE_FeedEff_2$Unit<-"Kg_dm_feed_per_kg_prod"
    
    # Subset data to desired identifiers
    IMAGE_FeedEff_3<-IMAGE_FeedEff_2[!IMAGE_FeedEff_2$NRT_Code == "27" & # exclude World
                                       !IMAGE_FeedEff_2$NAT == "total",
                                     c("t","NRT_Code","NRC2","NAT","NGST","NFPT","Unit","Value")]
    
    colnames(IMAGE_FeedEff_3)<-c("t", "NRC2_Code","NRC2","NA", "NGST","NFPT","Unit", "Value")
    
    # Write out feed intake and efficiency
    DF_toWrite_FeedIntk_FeedEff<-list(

      "FEEDEFF" = IMAGE_FeedEff_3,
      "Meta" = meta_df
      
    )
    
    if(Write == 'yes'){write.xlsx(DF_toWrite_FeedIntk_FeedEff, 
                                  paste0(output_path,"/IMAGE_FeedIntake_Eff_",Scen,".xlsx"), 
                                  row.names=FALSE)
    }
    
  } # Agriculture
  
}