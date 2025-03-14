# testing the sampler.spark function

# ------------------- SPARK CONNECT --------------------------------
library(sparklyr)
library(dplyr)
library(ggplot2)

conf <- spark_config()
conf$`sparklyr.shell.driver-memory`<- "128G"
conf$spark.memory.fraction <- 0.6
conf$`sparklyr.cores.local` <- 24

sc = spark_connect(master = "local", config = conf)

path_DORS =     "/vault/hugmo418_amed/NDR-SESAR/Uttag Socialstyrelsen 2024/ut_r_par_ov_63851_2023.csv"
path_NDR =      "/vault/hugmo418_amed/NDR-SESAR/Uttag SCB+NDR+SESAR 2024/FI_Lev_NDR.csv"
path_SESAR_FU = "/vault/hugmo418_amed/NDR-SESAR/Uttag SCB+NDR+SESAR 2024/FI_Lev_SESAR_FU.csv"
path_SESAR_IV = "/vault/hugmo418_amed/NDR-SESAR/Uttag SCB+NDR+SESAR 2024/FI_Lev_SESAR_IV.csv"
path_SESAR_TS = "/vault/hugmo418_amed/NDR-SESAR/Uttag SCB+NDR+SESAR 2024/FI_Lev_SESAR_TS.csv"
path_small_SESAR_IV = "/vault/hugmo418_amed/subsets_thesis_hugo/small_IV.csv"

fromto <- c(1,3) # Number of iterations

data_small <- spark_read_csv(sc, name = "df",path = path_small_SESAR_IV,infer_schema = TRUE, null_value = 'NA')
#Filter out Date data type
features <- names(sdf_schema(data_small))
cols <- sdf_schema(data_small)
filtered_features<- features[sapply(cols[features], function(x) !x$type %in% c("StringType", "DateType", "TimestampType"))]
data <- data_small %>% select(all_of(filtered_features))
# data <- data %>% select(all_of(c("LopNr",
#                                "SenPNr",
#                                "IV_UnitCode",
#                                "IV_County",
#                                "IV_Height",
#                                "IV_Weight",
#                                "IV_BMI_Calculated",
#                                "IV_BMI_UserSubmitted",
#                                "IV_AHI",
#                                "IV_ODI")))
data %>% summarise(across(everything(), ~ sum(as.integer(is.na(.))), .names = "missing_{.col}")) %>%
  collect() %>% unlist() %>% sum(na.rm = TRUE)
code_to_be_monitored <- function(x) {
  imp_init<- impute_with_random_samples(sc, data)
  #mice_imputed <- sampler.spark(sc, data, imp_init, fromto)
  #return(mice_imputed)
}

# Monitor the function
results <- monitor_memory(
  code_to_be_monitored,    # The function to monitor
  x = NULL,    # Your function's parameters
  sampling_interval = 0.1,  # How often to sample (in seconds)
  pre_time = 1,           # How long to monitor before (in seconds)
  post_time = 1          # How long to monitor after (in seconds)
)

cat("runtime:", results$run_time)
results$result %>% sdf_nrow()
# -------------- SESAR IV ----------------------------------------

data_big <- spark_read_csv(sc, name = "sesar_iv", path = path_SESAR_IV, infer_schema = TRUE, null_value = 'NA')
features_big <- names(sdf_schema(data_big))
cols_big <- sdf_schema(data_big)
filtered_big_features <- features_big[sapply(cols_big[features_big],
          function(x) !x$type %in% c("StringType", "DateType", "TimestampType"))]
data <- data_big %>% select(all_of(filtered_big_features))
data <- data %>% select(all_of(c("LopNr",
                               "SenPNr",
                               "IV_UnitCode",
                               "IV_County",
                               "IV_Height",
                               "IV_Weight",
                               "IV_BMI_Calculated",
                               "IV_BMI_UserSubmitted",
                               "IV_AHI",
                               "IV_ODI")))
data %>% summarise(across(everything(), ~ sum(as.integer(is.na(.))), .names = "missing_{.col}")) %>%
  collect() %>% unlist() %>% sum(na.rm = TRUE)
code_to_be_monitored <- function(x) {
  imp_init_big <- impute_with_random_samples(sc, big_data)

  #mice_imputed <- sampler.spark(sc, big_data, imp_init_big, fromto)
}

# Monitor the function
results <- monitor_memory(
  code_to_be_monitored,    # The function to monitor
  x = NULL,    # Your function's parameters
  sampling_interval = 0.1,  # How often to sample (in seconds)
  pre_time = 1,           # How long to monitor before (in seconds)
  post_time = 1          # How long to monitor after (in seconds)
)

cat("Sesar_IV runtime:", results$run_time)
imput = results$result
results$plot
# making sure it is the same size dataset
results$result %>% sdf_nrow()


# -------------- SESAR TS ----------------------------------------

data_big <- spark_read_csv(sc, name = "sesar_ts", path = path_SESAR_TS, infer_schema = TRUE, null_value = 'NA')
features_big <- names(sdf_schema(data_big))
cols_big <- sdf_schema(data_big)
filtered_big_features <- features_big[sapply(cols_big[features_big], function(x) !x$type %in% c("StringType", "DateType", "TimestampType"))]
big_data <- data_big %>% select(all_of(filtered_big_features))

big_data %>% summarise(across(everything(), ~ sum(as.integer(is.na(.))), .names = "missing_{.col}")) %>%
  collect() %>% unlist() %>% sum(na.rm = TRUE)
code_to_be_monitored <- function(x) {
  imp_init_big <- impute_with_random_samples(sc, big_data)
  #mice_imputed <- sampler.spark(sc, big_data, imp_init_big, fromto)
  #return(mice_imputed)
}

# Monitor the function
results <- monitor_memory(
  code_to_be_monitored,    # The function to monitor
  x = NULL,    # Your function's parameters
  sampling_interval = 0.1,  # How often to sample (in seconds)
  pre_time = 1,           # How long to monitor before (in seconds)
  post_time = 1          # How long to monitor after (in seconds)
)

cat("runtime:", results$run_time)
imput = results$result
# making sure it is the same size dataset
results$result %>% sdf_nrow()

# -------------- SESAR FU ----------------------------------------

data_big <- spark_read_csv(sc, name = "sesar_fu", path = path_SESAR_FU, infer_schema = TRUE, null_value = 'NA')
features_big <- names(sdf_schema(data_big))
cols_big <- sdf_schema(data_big)
filtered_big_features <- features_big[sapply(cols_big[features_big], function(x) !x$type %in% c("StringType", "DateType", "TimestampType"))]
big_data <- data_big %>% select(all_of(filtered_big_features))

big_data %>% summarise(across(everything(), ~ sum(as.integer(is.na(.))), .names = "missing_{.col}")) %>%
  collect() %>% unlist() %>% sum(na.rm = TRUE)
code_to_be_monitored <- function(x) {
  imp_init_big <- impute_with_random_samples(sc, big_data)
  #mice_imputed <- sampler.spark(sc, big_data, imp_init_big, fromto)
  #return(mice_imputed)
}

# Monitor the function
results <- monitor_memory(
  code_to_be_monitored,    # The function to monitor
  x = NULL,    # Your function's parameters
  sampling_interval = 0.1,  # How often to sample (in seconds)
  pre_time = 1,           # How long to monitor before (in seconds)
  post_time = 1          # How long to monitor after (in seconds)
)

cat("runtime:", results$run_time)
imput = results$result
# making sure it is the same size dataset
results$result %>% sdf_nrow()

#----- NDR -----------------------------------------------------

data_really_big <- spark_read_csv(sc, name = "ndr", path = path_NDR, infer_schema = TRUE)
features_really_big <- names(sdf_schema(data_really_big))
cols_really_big<- sdf_schema(data_really_big)
filtered_really_big_features <- features_really_big[sapply(cols_really_big[features_really_big],
                                            function(x) !x$type %in% c("StringType", "DateType", "TimestampType"))]
really_big_data <- data_really_big %>% select(all_of(filtered_really_big_features))
#impt_init_really_big <- impute_with_random_samples(sc, really_big_data)

code_to_be_monitored <- function(x) {
  imp_init_really_big <- impute_with_random_samples(sc, really_big_data) #This takes way too long...
  mice_imputed <- sampler.spark(sc, really_big_data, imp_init_really_big, fromto)
  return(mice_imputed)
}

# Monitor the function
results <- monitor_memory(
  code_to_be_monitored,    # The function to monitor
  x = NULL,    # Your function's parameters
  sampling_interval = 0.1,  # How often to sample (in seconds)
  pre_time = 1,           # How long to monitor before (in seconds)
  post_time = 1          # How long to monitor after (in seconds)
)

cat("runtime:", results$run_time)
imput = results$result
