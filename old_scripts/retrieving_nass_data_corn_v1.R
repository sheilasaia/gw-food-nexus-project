# retrieving nass data

# ---- 1. set up ----

# load libraries
library(tidyverse)
library(here)
library(httr)
library(jsonlite)
library(purrr)
library(maps)

# define paths
# when we put the final data on github we'll use relative paths based on the project
# project_path <- here::here()

# force direct paths for now
tabular_data_path <- "/Users/ssaia/Dropbox/GW-Food Nexus/tabular_data/nass_data/"
tabular_data_output_path <- "/Users/ssaia/Dropbox/GW-Food Nexus/tabular_data/nass_data/reformatted_data/"

# load nass key
# nass_key = "<your nass key here>"


# ---- 2. load county metadata ----

# state fips and abbreviation lookup
state_ids <- maps::state.fips %>%
  select(state_alpha = abb, state_fips = fips)

# load county ids data (reformatted 'AGDominatedCounties.xlsx' file)
county_ids_raw <- read_csv(paste0(tabular_data_path, "ag_dominated_counties_update05082019.csv"))

# define fips codes from reformatted 'AGDominatedCounties.xlsx' file
county_ids <- county_ids_raw %>%
  mutate(state_fips_pad = str_pad(state_fips, 2, pad = "0"), # pad with zeros if not 2 digits
         county_fips_pad = str_pad(county_fips, 3, pad = "0"), #pad with zeros if not 3 digits
         fips = as.character(paste0(state_fips_pad, county_fips_pad))) %>% # create fips key for later dataframe joining
  left_join(state_ids, by = "state_fips") %>%
  select(fips, state_fips, state_alpha, county_area_sqkm:county_area_under_ag_percent) # select only needed columns


# ---- 3. get nass data ----

# nass api key
# need to call your nass api key into Sys.Env memory
# request a nass api key at: https://quickstats.nass.usda.gov/api
# nass_key <- "<your number here>"

# nass url
nass_url <- "http://quickstats.nass.usda.gov"

# commodity description of interest
my_commodity_desc <- "CORN" # this is corn for grain (not sillage)
# my_commodity_desc <- "SOYBEANS"
# my_commodity_desc <- "WHEAT"
# my_commodity_desc <- "RICE"
# my_commodity_desc <- "COTTON"
# my_commodity_desc_expenses <- "EXPENSE TOTALS"
my_commodity_desc_net_income <- "INCOME, NET CASH FARM"
my_commodity_desc_income <- "INCOME, FARM-RELATED"

# query start year
# my_year <- "2017"
# don't define this if you want all years available

# state of interest
my_state <- "GA"

# aggregation level of interest
my_agg_level <- "COUNTY"

# final path string
# path_corn <- paste0("api/api_GET/?key=", nass_key, "&commodity_desc=", my_commodity_desc, "&year__GE=", my_year, "&state_alpha=", my_state) # for specific year
api_path_crop <- paste0("api/api_GET/?key=", nass_key, "&commodity_desc=", my_commodity_desc, "&state_alpha=", my_state) # for all years
# api_path_expenses <- paste0("api/api_GET/?key=", nass_key, "&commodity_desc=", my_commodity_desc_expenses, "&state_alpha=", my_state) # for all years
api_path_net_income <- paste0("api/api_GET/?key=", nass_key, "&commodity_desc=", my_commodity_desc_net_income, "&state_alpha=", my_state, "&agg_level_desc=", my_agg_level) # for all years
api_path_income <- paste0("api/api_GET/?key=", nass_key, "&commodity_desc=", my_commodity_desc_income, "&state_alpha=", my_state, "&agg_level_desc=", my_agg_level) # for all years

# get raw data
raw_data_crop <- GET(url = nass_url, path = api_path_crop)
# raw_data_expenses <- GET(url = nass_url, path = api_path_expenses)
raw_data_net_income <- GET(url = nass_url, path = api_path_net_income)
raw_data_income <- GET(url = nass_url, path = api_path_income)

# check status of api query
raw_data_crop$status_code
# raw_data_expenses$status_code
raw_data_net_income$status_code
raw_data_income$status_code
# 200 is good! no issues.
# 413 query is too big to handle

# convert to character
char_raw_data_crop <- rawToChar(raw_data_crop$content)
# char_raw_data_expenses <- rawToChar(raw_data_expenses$content)
char_raw_data_net_income <- rawToChar(raw_data_net_income$content)
char_raw_data_income <- rawToChar(raw_data_income$content)

# make into a list
list_raw_data_crop <- fromJSON(char_raw_data_crop)
# list_raw_data_expenses <- fromJSON(char_raw_data_expenses)
list_raw_data_net_income <- fromJSON(char_raw_data_net_income)
list_raw_data_income <- fromJSON(char_raw_data_income)

# map to data frame
raw_data_crop <- pmap_dfr(list_raw_data_crop, rbind)
# raw_data_expenses <- pmap_dfr(list_raw_data_expenses, rbind)
raw_data_net_income <- pmap_dfr(list_raw_data_net_income, rbind)
raw_data_income <- pmap_dfr(list_raw_data_income, rbind)

# clean up yield, area planted, and sales data
crop_data <- raw_data_crop %>%
  filter(agg_level_desc == "COUNTY") %>% # only want countly level data
  filter(prodn_practice_desc == "ALL PRODUCTION PRACTICES") %>%
  mutate(fips = paste0(state_fips_code, county_code),
         county_name_full = str_to_title(county_name),
         region = str_to_title(asd_desc),
         nass_description = str_to_lower(str_replace_all(str_replace_all(str_replace_all(str_remove_all(str_remove_all(short_desc, ","), "-"), "  ", " "), "/", "PER"), " ", "_")),
         statistic_cat_desc = str_remove_all(str_replace_all(str_to_lower(statisticcat_desc), " ", "_"), ","),
         units = str_replace_all(str_replace(str_to_lower(unit_desc), "/", "per"), " ", "_"),
         value_annual = str_trim(Value)) %>% # trim white-space
  select(fips, state_alpha, county_name_full, region, year, value_annual, statistic_cat_desc, units, nass_description) %>%
  filter(value_annual != "(D)" & value_annual != "(Z)") %>% # remove rows without data
  mutate(value_annual = as.numeric(str_remove_all(value_annual, ","))) %>%
  filter(county_name_full != "Other (Combined) Counties") # remove un-named counties
  
# county metadata (join nass county data with ag dominated county_ids dataframe)
county_data <- crop_data %>%
  select(fips:region) %>%
  distinct() %>%
  left_join(county_ids, by = "fips")

# select and reformat yield data
yield_data <- crop_data %>%
  filter(statistic_cat_desc == "yield" & nass_description == "corn_grain_yield_measured_in_bu_per_acre") %>%
  mutate(cat_units = paste0(statistic_cat_desc, "_", units),
         fips_year = paste0(fips, "_", year)) %>%
  select(fips_year, nass_description, value_annual, cat_units) # select only necessary columns

# select and reformat area planted data
area_planted_data <- crop_data %>%
  filter(statistic_cat_desc == "area_planted") %>%
  mutate(cat_units = paste0(statistic_cat_desc, "_", units),
         fips_year = paste0(fips, "_", year)) %>%
  select(fips_year, nass_description, value_annual, cat_units) # select only necessary columns

# select and reformat sales data
# sales_data <- crop_data %>%
#   filter(statistic_cat_desc == "sales") %>%
#   mutate(cat_units = paste0(statistic_cat_desc, "_", units),
#          fips_year = paste0(fips, "_", year),
#          cat_units = case_when(cat_units == "sales_$" ~ "sales_usd",
#                                cat_units == "sales_operations" ~ "sales_num_operations")) %>%
#   select(fips_year, nass_description, value_annual, cat_units) # select only necessary columns

# select and reformat expense data
# expense_data <- raw_data_expenses %>%
#   filter(agg_level_desc == "COUNTY") %>% # only want countly level data
#   filter(domain_desc == "TOTAL" & domaincat_desc == "NOT SPECIFIED") %>% # only want non-demongraphics results
#   mutate(fips = paste0(state_fips_code, county_code),
#          statistic_cat_desc = "expenses",
#          class_desc_short = str_to_lower(str_replace_all(str_replace(class_desc, ",", ""), " ", "_")),
#          units = str_to_lower(str_replace_all(str_replace(unit_desc, "/", "per"), " ", "_")),
#          cat_units = paste0(class_desc_short, "_", statistic_cat_desc, "_", units),
#          nass_description = str_to_lower(str_replace_all(str_sub(str_replace_all(str_replace_all(str_remove_all(str_remove_all(short_desc, ","), "-"), "  ", " "), "/", "per"), 26, -1), " ", "-")),
#          value_annual = str_trim(Value)) %>%
#   select(fips, year, nass_description, value_annual, cat_units) %>%
#   filter(value_annual != "(D)" & value_annual != "(Z)") %>% # remove rows without data
#   mutate(fips_year = paste0(fips, "_", year),
#          value_annual = as.numeric(str_remove_all(value_annual, ","))) %>%
#   mutate(cat_units = case_when(cat_units == "operating_expenses_$" ~ "expenses_usd",
#                                cat_units == "operating_expenses_$_per_operation" ~ "expenses_usd_per_operation",
#                                cat_units == "operating_expenses_operations" ~ "expenses_num_operations",
#                                cat_units == "operating_paid_by_landlord_expenses_$" ~ "expenses_paid_by_landlord_usd",
#                                cat_units == "operating_paid_by_landlord_expenses_operations" ~ "expenses_paid_by_landlord_num_operations")) %>%
#   select(fips_year, nass_description, value_annual, cat_units)

# select and reformat net income data
net_income_data <- raw_data_net_income %>% 
  filter(short_desc == "INCOME, NET CASH FARM, OF OPERATIONS - NET INCOME, MEASURED IN $") %>% 
  filter(domaincat_desc == "NOT SPECIFIED") %>%
  mutate(fips = paste0(state_fips_code, county_code),
         statistic_cat_desc = str_replace(str_to_lower(statisticcat_desc), " ", "_"),
         class_desc_short = str_to_lower(str_replace_all(str_replace(class_desc, ",", ""), " ", "_")),
         cat_units = paste0(statistic_cat_desc, "_", class_desc_short, "_", unit_desc),
         nass_description = paste0(statistic_cat_desc, "_", class_desc_short),
         value_annual = str_trim(Value)) %>%
  select(fips, year, nass_description, value_annual, cat_units) %>%
  filter(value_annual != "(D)" & value_annual != "(Z)") %>% # remove rows without data
  mutate(fips_year = paste0(fips, "_", year),
         value_annual = as.numeric(str_remove_all(value_annual, ","))) %>%
  mutate(cat_units = recode(cat_units, "net_income_of_operations_$" = "net_income_of_operations_usd")) %>%
  select(fips_year, nass_description, value_annual, cat_units)

# select and reformat income receipts data
income_data <- raw_data_income %>% 
  filter(short_desc == "INCOME, FARM-RELATED - RECEIPTS, MEASURED IN $") %>% 
  filter(domaincat_desc == "NOT SPECIFIED") %>%
  mutate(fips = paste0(state_fips_code, county_code),
         statistic_cat_desc = str_to_lower(statisticcat_desc),
         cat_units = paste0(str_to_lower(group_desc), "_", statistic_cat_desc, "_", unit_desc),
         nass_description = paste0(str_to_lower(group_desc), "_", statistic_cat_desc),
         value_annual = str_trim(Value)) %>%
  select(fips, year, nass_description, value_annual, cat_units) %>%
  filter(value_annual != "(D)" & value_annual != "(Z)") %>% # remove rows without data
  mutate(fips_year = paste0(fips, "_", year),
         value_annual = as.numeric(str_remove_all(value_annual, ","))) %>%
  mutate(cat_units = recode(cat_units, "income_receipts_$" = "income_receipts_usd")) %>%
  select(fips_year, nass_description, value_annual, cat_units)
  

# ---- 4. merge and reformat nass data ----

# combine yield, area planted, net income, and income receipts data
merge_data <- rbind(yield_data, area_planted_data, net_income_data, income_data) %>% # NOTE! all dataframes have to have the same columns & column order!
  select(-nass_description) %>% # delete this for now
  group_by(fips_year) %>%
  spread(key = cat_units, value = value_annual) %>% # spread data to format as requested
  mutate(fips = str_sub(fips_year, 1, 5),
         year = as.numeric(str_sub(fips_year, 7, 10)), # break out fips and year
         crop_type = str_to_lower(my_commodity_desc)) %>%
  ungroup(fips_year) %>% # ungroup to prevent errors later
  select(fips, year, crop_type, yield_bu_per_acre, area_planted_acres, net_income_of_operations_usd, income_receipts_usd) %>% # select only necessary columns
  left_join(county_data, by = "fips") %>% # join county metadata
  mutate(yield_bu_per_sqkm = yield_bu_per_acre * 247.105, 
         area_planted_sqkm = area_planted_acres * (1/247.105)) %>% # change from acres to sqkm) %>% 
  select(year, state_alpha, county_name_full, fips, region,
         ag_area_sqkm, county_area_sqkm, county_area_under_ag_percent, crop_type,
         yield_bu_per_sqkm, area_planted_sqkm, net_income_of_operations_usd, income_receipts_usd) %>%
  filter(year > 1996) %>%
  arrange(fips, year) %>% na.omit()

# combine yield, area planted, sales, and expense data
# merge_data <- rbind(yield_data, area_planted_data, sales_data, expense_data) %>% # NOTE! all dataframes have to have the same columns & column order!
#   select(-nass_description) %>% # delete this for now
#   group_by(fips_year) %>%
#   spread(key = cat_units, value = value_annual) %>% # spread data to format as requested
#   mutate(fips = str_sub(fips_year, 1, 5),
#          year = as.numeric(str_sub(fips_year, 7, 10))) %>% # break out fips and year
#   ungroup(fips_year) %>% # ungroup to prevent errors later
#   select(fips, year, yield_bu_per_acre, area_planted_acres, 
#          sales_usd , sales_num_operations,
#          expenses_num_operations:expenses_usd_per_operation) %>% # select only necessary columns
#   left_join(county_data, by = "fips") %>% # join county metadata
#   mutate(yield_bu_per_sqkm = yield_bu_per_acre * 247.105, 
#          area_planted_sqkm = area_planted_acres * (1/247.105)) %>% # change from acres to sqkm)
#   select(year, state_alpha, county_name_full, fips, region,
#          ag_area_sqkm, county_area_sqkm, county_area_under_ag_percent, crop_type,
#          yield_bu_per_sqkm, area_planted_sqkm,
#          sales_usd, sales_num_operations,
#          expenses_usd, expenses_usd_per_operation, expenses_num_operations) #%>% #, expenses_paid_by_landlord_usd, expenses_paid_by_landlord_num_operations)
#   #na.omit()

# for now left out operations that were owned by landlords and also kept all data (not just ag dominated counties)
# non-ag dominated counties have NA values for ag_area_sqkm and county_area_sqkm


# ---- 5. export nass data ----

# export merged data
write_csv(merge_data, paste0(tabular_data_output_path, "la_nass_corn_data.csv"))


# ---- 6. corn data download funciton ----

get_nass_corn <- function(state) {
  # nass url
  nass_url <- "http://quickstats.nass.usda.gov"
  
  # commodity description of interest
  my_commodity_desc <- "CORN" # this is corn for grain (not sillage)
  my_commodity_desc_net_income <- "INCOME, NET CASH FARM"
  my_commodity_desc_income <- "INCOME, FARM-RELATED"
  
  # state of interest
  my_state <- state
  
  # aggregation level of interest
  my_agg_level <- "COUNTY"
  
  # final path string
  api_path_crop <- paste0("api/api_GET/?key=", nass_key, "&commodity_desc=", my_commodity_desc, "&state_alpha=", my_state) # for all years
  api_path_net_income <- paste0("api/api_GET/?key=", nass_key, "&commodity_desc=", my_commodity_desc_net_income, "&state_alpha=", my_state, "&agg_level_desc=", my_agg_level) # for all years
  api_path_income <- paste0("api/api_GET/?key=", nass_key, "&commodity_desc=", my_commodity_desc_income, "&state_alpha=", my_state, "&agg_level_desc=", my_agg_level) # for all years
  
  # get raw data
  raw_data_crop <- GET(url = nass_url, path = api_path_crop)
  raw_data_net_income <- GET(url = nass_url, path = api_path_net_income)
  raw_data_income <- GET(url = nass_url, path = api_path_income)
  
  # save status codes
  temp_status_codes <- c(raw_data_crop$status_code, raw_data_net_income$status_code, raw_data_income$status_code)
  
  # convert to character
  char_raw_data_crop <- rawToChar(raw_data_crop$content)
  char_raw_data_net_income <- rawToChar(raw_data_net_income$content)
  char_raw_data_income <- rawToChar(raw_data_income$content)
  
  # check query status code. if all are equal to 200, then ok
  if (length(grep(200, temp_status_codes)) == length(temp_status_codes)) {
    
    # make into a list
    list_raw_data_crop <- fromJSON(char_raw_data_crop)
    list_raw_data_net_income <- fromJSON(char_raw_data_net_income)
    list_raw_data_income <- fromJSON(char_raw_data_income)
    
    # map to data frame
    raw_data_crop <- pmap_dfr(list_raw_data_crop, rbind)
    raw_data_net_income <- pmap_dfr(list_raw_data_net_income, rbind)
    raw_data_income <- pmap_dfr(list_raw_data_income, rbind)
    
    # clean up yield, area planted, and sales data
    crop_data <- raw_data_crop %>%
      filter(agg_level_desc == "COUNTY") %>% # only want countly level data
      filter(prodn_practice_desc == "ALL PRODUCTION PRACTICES") %>%
      mutate(fips = paste0(state_fips_code, county_code),
             county_name_full = str_to_title(county_name),
             region = str_to_title(asd_desc),
             nass_description = str_to_lower(str_replace_all(str_replace_all(str_replace_all(str_remove_all(str_remove_all(short_desc, ","), "-"), "  ", " "), "/", "PER"), " ", "_")),
             statistic_cat_desc = str_remove_all(str_replace_all(str_to_lower(statisticcat_desc), " ", "_"), ","),
             units = str_replace_all(str_replace(str_to_lower(unit_desc), "/", "per"), " ", "_"),
             value_annual = str_trim(Value)) %>% # trim white-space
      select(fips, county_name_full, region, year, value_annual, statistic_cat_desc, units, nass_description) %>%
      filter(value_annual != "(D)" & value_annual != "(Z)") %>% # remove rows without data
      mutate(value_annual = as.numeric(str_remove_all(value_annual, ","))) %>%
      filter(county_name_full != "Other (Combined) Counties") # remove un-named counties
    # in the case that there's no corn data there are 3 unique values for statistic_cat_desc (i.e., sales, area_harvested, production)
    # in the case that there's corn data there are 6 unique values for statistic_cat_desc (i.e., sales, area_harvested, production, area_planted, area_planted_net, "yield")
    
    # if yield data exisists, then reformat
    if (length(grep("yield", unique(crop_data$statistic_cat_desc))) > 0) {
      # county metadata (join nass county data with ag dominated county_ids dataframe)
      county_data <- crop_data %>%
        select(fips:region) %>%
        distinct() %>%
        left_join(county_ids, by = "fips")
      
      # select and reformat yield data
      yield_data <- crop_data %>%
        filter(statistic_cat_desc == "yield" & nass_description == "corn_grain_yield_measured_in_bu_per_acre") %>%
        mutate(cat_units = paste0(statistic_cat_desc, "_", units),
               fips_year = paste0(fips, "_", year)) %>%
        select(fips_year, nass_description, value_annual, cat_units) # select only necessary columns
      
      # select and reformat area planted data
      area_planted_data <- crop_data %>%
        filter(statistic_cat_desc == "area_planted") %>%
        mutate(cat_units = paste0(statistic_cat_desc, "_", units),
               fips_year = paste0(fips, "_", year)) %>%
        select(fips_year, nass_description, value_annual, cat_units) # select only necessary columns
      
      # select and reformat net income data
      net_income_data <- raw_data_net_income %>% 
        filter(short_desc == "INCOME, NET CASH FARM, OF OPERATIONS - NET INCOME, MEASURED IN $") %>% 
        filter(domaincat_desc == "NOT SPECIFIED") %>%
        mutate(fips = paste0(state_fips_code, county_code),
               statistic_cat_desc = str_replace(str_to_lower(statisticcat_desc), " ", "_"),
               class_desc_short = str_to_lower(str_replace_all(str_replace(class_desc, ",", ""), " ", "_")),
               cat_units = paste0(statistic_cat_desc, "_", class_desc_short, "_", unit_desc),
               nass_description = paste0(statistic_cat_desc, "_", class_desc_short),
               value_annual = str_trim(Value)) %>%
        select(fips, year, nass_description, value_annual, cat_units) %>%
        filter(value_annual != "(D)" & value_annual != "(Z)") %>% # remove rows without data
        mutate(fips_year = paste0(fips, "_", year),
               value_annual = as.numeric(str_remove_all(value_annual, ","))) %>%
        mutate(cat_units = recode(cat_units, "net_income_of_operations_$" = "net_income_of_operations_usd")) %>%
        select(fips_year, nass_description, value_annual, cat_units)
      
      # select and reformat income data
      income_data <- raw_data_income %>% 
        filter(short_desc == "INCOME, FARM-RELATED - RECEIPTS, MEASURED IN $") %>% 
        filter(domaincat_desc == "NOT SPECIFIED") %>%
        mutate(fips = paste0(state_fips_code, county_code),
               statistic_cat_desc = str_to_lower(statisticcat_desc),
               cat_units = paste0(str_to_lower(group_desc), "_", statistic_cat_desc, "_", unit_desc),
               nass_description = paste0(str_to_lower(group_desc), "_", statistic_cat_desc),
               value_annual = str_trim(Value)) %>%
        select(fips, year, nass_description, value_annual, cat_units) %>%
        filter(value_annual != "(D)" & value_annual != "(Z)") %>% # remove rows without data
        mutate(fips_year = paste0(fips, "_", year),
               value_annual = as.numeric(str_remove_all(value_annual, ","))) %>%
        mutate(cat_units = recode(cat_units, "income_receipts_$" = "income_receipts_usd")) %>%
        select(fips_year, nass_description, value_annual, cat_units)
      
      # combine yield, area planted, net income, and income receipts data
      merge_data <- rbind(yield_data, area_planted_data, net_income_data, income_data) %>% # NOTE! all dataframes have to have the same columns & column order!
        select(-nass_description) %>% # delete this for now
        group_by(fips_year) %>%
        spread(key = cat_units, value = value_annual) %>% # spread data to format as requested
        mutate(fips = str_sub(fips_year, 1, 5),
               year = as.numeric(str_sub(fips_year, 7, 10)), # break out fips and year
               crop_type = str_to_lower(my_commodity_desc)) %>%
        ungroup(fips_year) %>% # ungroup to prevent errors later
        select(fips, year, crop_type, yield_bu_per_acre, area_planted_acres, net_income_of_operations_usd, income_receipts_usd) %>% # select only necessary columns
        left_join(county_data, by = "fips") %>% # join county metadata
        mutate(yield_bu_per_sqkm = yield_bu_per_acre * 247.105, 
               area_planted_sqkm = area_planted_acres * (1/247.105)) %>% # change from acres to sqkm) %>% 
        select(year, state_alpha, county_name_full, fips, region,
               ag_area_sqkm, county_area_sqkm, county_area_under_ag_percent, crop_type,
               yield_bu_per_sqkm, area_planted_sqkm, net_income_of_operations_usd, income_receipts_usd) %>%
        filter(year > 1996) %>%
        arrange(fips, year) %>% na.omit()
      
      # return merged data
      return(merge_data)
    }
    
    # if yield data doesn't exist, then return empty data frame
    else {
      merge_data <- data.frame()
      
      # return empty merged data
      return(merge_data)
    }
  }
  
  # if all are not equal to 200, then there's an issue! (413 = query too big)
  else {
    
    # save status codes as merged data frame
    merge_data <- data.frame(state_alpha = my_state, 
                             crop_status_code = temp_status_codes[1],
                             net_income_status_code = temp_status_codes[2],
                             income_status_code = temp_status_codes[3])
    
    # return merged data frame with one row
    return(merge_data)
  }
}


# ---- 7. corn function in action ----

# all 50 states (list)
# my_conus_state_list <- data.frame(state_alpha = state.abb) %>%
#   filter(state_alpha != "AK" & state_alpha != "HI")

# states of interest for gw-food-nexus project
my_sel_conus_state_list <- county_ids %>% # see code section 2. for county_ids
  select(state_alpha) %>%
  distinct() %>%
  arrange(state_alpha)
# 33 unique states identified (out of 48 conus states)

# loop
for (i in 1:length(my_sel_conus_state_list$state_alpha)) {
  
  # call a state
  temp_state <- my_sel_conus_state_list$state_alpha[i]
  
  # get data
  temp_data <- get_nass_corn(temp_state)
  
  # only export if there's data
  if (dim(temp_data)[1] > 1) {
    
    # export data
    write_csv(temp_data, paste0(tabular_data_output_path, "nass_data_", str_to_lower(temp_state), "_corn.csv"))
  }
  
  # if there's an error, also save status codes
  else if (dim(temp_data)[1] == 1) {
    
    # export data
    write_csv(temp_data, paste0(tabular_data_output_path, "nass_data_", str_to_lower(temp_state), "_corn.csv"))
  }
  
  # if dim(temp_data)[1] == 0 then don't save anything
}


# ---- 8. merge all datasets together ----

# read files in folder
nass_files <- list.files(path = tabular_data_output_path)
nass_file_paths <- paste0(tabular_data_output_path, nass_files)
nass_file_sizes <- purrr::map_dbl(nass_file_paths, file.size)

nass_file_data <- data.frame(file_name = as.character(nass_files),
                             file_path = as.character(paste0(tabular_data_output_path, nass_files)),
                             file_size_bytes = as.numeric(nass_file_sizes))

# select files bigger than 86 bytes to merge
nass_sel_file_data <- nass_file_data %>%
  filter(file_size_bytes > 86)
# for data files that are 86 bytes - these ones the query was too big (status code = 413)
nass_sel_file_paths <- as.vector(nass_sel_file_data$file_path)

# 
blah <- purrr::map(nass_sel_file_paths, blah_function) %>%
  unlist() %>%
  bind_rows()
  
blah_function <- function(file_path) {
  
  my_df <- read_csv(file_path)
  
  return(my_df)
}

# ---- x. extra code ----
# select and reformat area harvested data
corn_area_harvested_data <- corn_data %>%
  filter(statisticcat_desc_full == "area_harvested") %>%
  filter(unit_desc_full == "acres") %>% # don't want # operations
  mutate(area_harvested_acres = value_annual) %>% # consolidate
  select(fips:year, area_harvested_acres)

# other potential datasets (corn sales and production)
corn_sales_data <- corn_data %>%
  filter(statisticcat_desc_full == "sales") %>%
  filter(unit_desc_full == "$")

corn_production_data <- corn_data %>%
  filter(statisticcat_desc_full == "production")


# ---- x. to do: ----
# make function and for loop for multiple states