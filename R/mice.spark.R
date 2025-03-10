
mice.spark <- function(data,
                       m = 5,
                       method = NULL,
                       predictorMatrix,
                       ignore = NULL,
                       where = NULL,
                       blocks,
                       visitSequence = NULL,
                       formulas,
                       modeltype = NULL,
                       blots = NULL,
                       post = NULL,
                       defaultMethod = c("pmm", "logreg", "polyreg", "polr"),
                       maxit = 5,
                       printFlag = TRUE,
                       seed = NA,
                       data.init = NULL,
                       ...) {
  call <- match.call()
  #check.deprecated(...)

  if (!is.na(seed)) set.seed(seed)

  # check form of data and m
  data <- check.spark.dataform(data)
  cols <- sparklyr::sdf_schema(data)
  m <- check.m(m)

  mp <- missing(predictorMatrix)

  predictorMatrix <- make.spark.predictorMatrix(data, blocks)

  print("**DEBUG** where:")
  print(where)
  where <- check.where.spark(where, data, blocks)
  print("**DEBUG** where after check.where:")
  print(where)

  from <- 1
  to <- from + maxit - 1
  # Since having multiple imputations loaded in memory is not feasible, we impute one by one
  # and save the results to disk after each iteration, hence sampler.spark only returns 1 imputation

  # Calculate imputation mask ...
  where <- make.where.spark(data, keyword = "missing")
  onserved <- make.where.spark(data, keyword = "observed")
  # and initialize it with random sampling from where the data is not missing
  imp_init <- data %>% sparklyr::sdf_sample(fraction = 0.1)
  imp_init <-
  # FOR EACH IMPUTATION SET i = 1, ..., m
  for (i in 1:m) {
    cat("Iteration: ", i, "\n")
    # Load data, imputation mask and imputation set
    data <- sparklyr::sdf_copy_to(sc, data)
    where <- sparklyr::sdf_copy_to(sc, where)
    imp <- sparklyr::sdf_copy_to(sc, imp_init)

    # Run the imputation algorithm
    imp <- sampler.spark(data, m, where, imp, predictorMatrix, modeltype, c(from, to))

    # Save imputation set to disk
    write.csv(imp, file = paste0("imp_", i, ".csv"))

  }

  return(NULL)
}


sampler.spark <- function(data, m, where, imp, predictorMatrix, modeltype, fromto){
  # For iteration k in fromto
  from = fromto[1]
  to = fromto[2]
  # get the variable type of each variable in the data and store that into an array
  var_names <- sparklyr::sdf_schema(data)

  var_types = get_var_types(data, var_names)

  for (k in from:to){
    # For each variable j in the data
    for (var_j in var_names){
      # Obtain the variables use to predict the missing values of variable j and create feature column
      predictors = predictorMatrix[var_j]
      # Create feature vector for MLlib models
      data <- data %>%
        sparklyr::ft_vector_assembler(input_cols = predictors, output_col = "features")
      # Get the variable type then choose the appropriate imputation method

      # Create the model
      if (var_types[[var_j]] == "Numerical"){
        model <- sparklyr::ml_linear_regression(
          x = dummy_data,
          features_col = "features",
          label_col = var,
        )
      } else if (var_types[[var_j]] == "Categorical"){
        model <- sparklyr::ml_logistic_regression(
          x = dummy_data,
          features_col = "features",
          label_col = var,
        )
      } else if (var_types[[var_j]] == "Binary"){
        model <- sparklyr::ml_logistic_regression(
          x = dummy_data,
          features_col = "features",
          label_col = var,
        )
      } else if (var_types[[var_j]] == "Unsupported"){
        # Do nothing, pass to the next for loop iteration
        next
      }

      # replace the missing values (imp) with the imputed values using ml_pr[edict]

      imp <- imp %>%
        sparklyr::mutate(var_j = ifelse(is.na(var_j), model %>% sparklyr::ml_predict(data), var_j))

    }

  }
}


# Spark version of make.where
make.where.spark <- function(data, keyword = c("missing", "all", "none", "observed")) {
  keyword <- match.arg(keyword)

  data <- check.spark.dataform(data)
  where <- switch(keyword,
                  missing = na_locations(data),
                  all = data %>% mutate(across(everything(), ~ TRUE)),
                  none = data %>% mutate(across(everything(), ~ FALSE)),
                  observed = data %>% mutate(across(everything(), ~ !is.na(.)))
  )
  where
}



# Spark version of check.where
check.where.spark <- function(where, data) {
  if (is.null(where)) {
    # print("**DEBUG** where is null")
    where <- make.where.spark(data, keyword = "missing")
  }

  if (!inherits(where, "tbl_spark")) {
    if (is.character(where)) {
      return(make.where.spark(data, keyword = where))
    } else {
      stop("Argument `where` not a Spark DataFrame", call. = FALSE)
    }
  }
  # Num rows of a spark data frame is unknown until pulled, so dim(X) returns (NA, n_cols)
  # Thus n_rows needs to be calculated separately
  n_rows_where = where %>% dplyr::count() %>% dplyr::pull()
  # print("**DEBUG** n_rows_where:")
  # print(n_rows_where)
  n_rows_data = data %>% dplyr::count() %>% dplyr::pull()
  # print("**DEBUG** n_rows_data:")
  # print(n_rows_data)
  if ((dim(data)[2] != dim(where)[2]) || (n_rows_where != n_rows_data)) {
    stop("Arguments `data` and `where` not of same size", call. = FALSE)
  }

  #where <- as.logical(as.matrix(where)) #Not needed ?
  if (is.na.spark(where)) { #from NA_utils.R
    stop("Argument `where` contains missing values", call. = FALSE)
  }

  where
}


get_var_types <- function(data, var_names) {
  # Initialize an empty vector to store variable types
  # TODO: Make this function better. right now it make bad guesses
  var_list <- names(var_names)
  types <- character(length(var_list))
  names(types) <- var_list

  # Loop through each variable in the schema
  for (var_name in var_list) {
    # Extract the type information
    var_type <- var_names[[var_name]]$type

    # Categorize based on Spark types
    if (grepl("BooleanType", var_type)) {
      types[var_name] <- "Binary"

    } else if (grepl("ByteType|ShortType|IntegerType|LongType", var_type)) {
      types[var_name] <- "Numerical"

    } else if (grepl("FloatType|DoubleType|DecimalType", var_type)) {
      types[var_name] <- "Numerical"

    } else if (grepl("StringType|CharType|VarcharType", var_type)) {
      types[var_name] <- "Categorical"

    } else  {
      types[var_name] <- "Unsupported"
    }

    if (grepl("Type", var_name)) {
      #if "Type" in the var name, set type to categorical (for sesar datasets)
      types[var_name] <- "Categorical"
    }
  }

  return(types)
}
# tests for get_var_types
# var_names <- sparklyr::sdf_schema(dummy_data)
# var_types <- get_var_types(dummy_data, var_names)
# print(var_types)
