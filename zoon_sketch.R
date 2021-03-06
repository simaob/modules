# _____________     ____________       ____________         ___________________
#  \  ______   \__ _\   ______  \     _\   ______  \       _\      ___  \______
#   \       /   \  \ \  \     \  \__ _\ \  \     \  \     _\ \  \/    \  \_____
#    \     /     \  \ \  \     \  \  \ \ \  \     \  \__ _\ \ \  \     \  \____
#     \   /______ \  \ \  \_____\  \  \ \ \  \_____\  \  \ \ \ \  \     \  \___
#      \___________\__\_\___________\__\_\_\___________\__\_\_\_\___________\__
#                      \____________\___\_\____________\___\_\_\____________\__
#                                        \____________\_____\_\____________\___
# SPECIES DISTRIBUTION MODELLING                             \____________\____
#
# A PROTOTYPE FOR REPRODUCIBLE, ACCESSIBLE & SHAREABLE SCIENTIFIC OUTPUTS IN R

# (Greg, I edited your lovely ASCII art to bring it under the 80 character
# line limit for the Google R style guide)

# This is a *really* rough sketch of a modular structure for the ZOON workflow.
# In this version, a workflow consists of 5 types of modules, representing the
# key steps in an SDM workflow:
#
#   occurrence module
#   covariate module
#   process module
#   model module
#   map module
#
# The user must select one module for each of these module types. These are
# then passed to the workflow wrapper function which runs through each step.
# Every module type should have a protocol determining what it takes as input
# and what it gives as output. Different modules for each module type could
# be stored in a community repositories, enabling users to quickly drop in a
# newly developed model or processing step and run it with their data. The
# structure also makes it very easy to compare different models against a
# standard dataset.
# These modules are just functions and wherever possible they should be self-
# contained, taking no arguments other than those used in the workflow.
#
# Clearly this is very simplistic, obvious next steps include modules for
# validation statistics and plots, the ability to predict to different
# covariate rasters than are used to train the model, etc. 
#
# OK, let's go....

# ~~~~~~~~~~~~
# clear the workspace
rm(list = ls())

# ~~~~~~~~~~~~
# define the modules fir each module type

# ~~~~~~~~~~~~
# occurrence modules

# input: a numeric vetor of length 4 giving the coordinates of the rectangular
# region within which to carry out the analysis, in the order: xmin, xmax,
# ymin, ymax.

# output: a dataframe with four columns:
#   value - a numeric value which may give 1 for presences, 0 for absences or a
#     positive integer for count data
#   type - a character value saying what is in the value column
#   lon - the longitude of the record
#   lat - the latitutude of the record

# ~~~

# occurrenceCp:
# occurrence module to grab *Anopheles plumbeus* (a mosquito) occurrence (i.e.
# presence-only) data from GBIF, in the area bounded by extent.
# Perhaps this should have temp                                                                         oral interval too for future-proofing?

occurrenceCp <- function (extent) {
  require (dismo)
  
  raw <- gbif(genus = 'Anopheles',
              species = 'plumbeus',
              ext = extent)
  
  occurrence <- raw[, c('lon', 'lat')]
  
  occurrence$value <- 1
  
  occurrence$type <- 'presence'
  
  return(occurrence)
}

# ~~~~~~~~~~~~
# covariate modules

# input: a numeric vetor of length 4 giving the coordinates of the rectangular
# region within which to carry out the analysis, in the order: xmin, xmax,
# ymin, ymax.

# output: a Raster* object (class from the raster package) with the gridded
# covariates used to train and predict from the SDM.

# ~~~

# covariateAir:
# covariate module to grab a coarse resolution mean air temperature raster from
# January-February 2001-2002 for the given extent.

covariateAir <- function (extent) {
  require(RNCEP)
  
  c1 <- NCEP.gather(variable = 'air',
                    level = 850,
                    months.minmax = c(1:2),
                    years.minmax = c(2000,2001),
                    lat.southnorth = extent[3:4],
                    lon.westeast = extent[1:2],
                    reanalysis2 = FALSE,
                    return.units = TRUE)
  
  avg <- apply(c1, c(1, 2), mean)
  
  ras <- raster(avg)
  
  extent(ras) <- c(extent)
  
  return (ras)  
  
}

# ~~~~~~~~~~~~
# process modules

# input:
#   occ - occurrence data, the output from an occurrence module
#   ras - covariate data, the output from a covariate module

# output: dataframe with at least 5 columns
#   value - a numeric value which may give 1 for presences, 0 for absences or a
#     positive integer for count data
#   type - a character value saying what is in the value column
#   lon - the longitude of the record
#   lat - the latitutude of the record
#   columns 5-n - the values of the covariates for each records (the names of
#       these columns should correspond exactly to the names of the layers in
#       ras)

# ~~~

# processA:
# process module to generate up to 100 background records at random in
# cells of ras and return these along with the ppresence only data.

processA <- function (occ, ras) {
  
  require (dismo)
  
  if (!all(occ$type == 'presence')) {
    stop ('this function only works for presence-only data')
  }
  
  # generate pseudo-absence data
  pa <- randomPoints(ras,
                     100)
  
  
  npres <- nrow(occ)
  
  npabs <- nrow(pa)
  
  # extract covariates
  occ_covs <- as.matrix(extract(ras, occ[, c('lon', 'lat')]))
  
  pa_covs <- as.matrix(extract(ras, pa))
  
  covs <- rbind(occ_covs,
                pa_covs)
  
  # combine with the occurrence data
  df <- data.frame(value = rep(c(1, 0),
                               c(npres, npabs)),
                   type = rep(c('presence', 'background'),
                              c(npres, npabs)),
                   lon = c(occ$lon, pa[, 1]),
                   lat = c(occ$lat, pa[, 2]),
                   covs)
  
  names(df)[5:ncol(df)] <- names(ras)
  
  return(df)
  
}

# ~~~~~~~~~~~~
# model modules

# input:
#   df - a dataframe, the output from a process module

# output: a model object with a valid predict method

# note that the current set up only works for models with a predict method
# which takes the argument: type = 'response'
# obviously we'll have to work around that.

# ~~~

# modelLR:
# model module to fit a simple logistic regression model

modelLR <- function (df) {
  if (!all(df$type %in% c('presence', 'absence', 'background'))) {
    stop ('only for presence/absence or presence/background data')
  }
  
  covs <- as.data.frame(df[, 5:ncol(df)])
  names(covs) <- names(df)[5:ncol(df)]
  m <- glm(df$value ~ .,
           data = covs,
           family = binomial)
  
  return (m)
}

# modelRF:
# model module to fit a simple RandomForest classification model

modelRF <- function (df) {
  
  require ('randomForest')
  
  if (!all(df$type %in% c('presence', 'absence', 'background'))) {
    stop ('only for presence/absence or presence/background data')
  }
  
  covs <- as.data.frame(df[, 5:ncol(df)])
  names(covs) <- names(df)[5:ncol(df)]
  m <- randomForest(df$value ~ .,
                    data = covs,
                    weights = rep(1, nrow(covs)),
                    size = 1)
  
  return (m)
}

# ~~~~~~~~~~~~
# map modules

# input:
#   model - a model object, the output from a model module
#   ras - a Raster* object, the output from a covariate module

# output: a Raster object giving the probabilistic model predictions for each
# cell of ras

mapA <- function (model, ras) {
  
  vals <- data.frame(getValues(ras))
  colnames(vals) <- names(ras)
  
  pred <- predict(model,
                  newdata = vals,
                  type = 'response')
  
  pred_ras <- ras[[1]]
  
  pred_ras <- setValues(pred_ras, pred)
  
  return(pred_ras)
  
}

# ~~~~~~~~~~~~
# workflow wrapper function

# input: an extent and one of each of the modules
# output: a list with the extent, the results of each module and a copy of the
# code used to execute the workflow (what's there now should be source-able
# though I'm sure there is a much neater approach than the one I took - the
# ultimate aim would be a much nicer way of enhancing reproducibility).

workflow <- function(ext,
                     occurrenceFn,
                     covariateFn,
                     processFn,
                     modelFn,
                     mapFn) {
  
  # small helper function to dump the code for a function to a text string
  getSource <- function (object) {
    paste(deparse(object), collapse = '\n')
  }
  
  occ <- occurrenceFn(ext)
  cov <- covariateFn(ext)
  df <- processFn(occ, cov)
  m <- modelFn(df)
  map <- mapFn(m, cov)
  
  # get the command used to call this function
  bits <- sys.call()
  call <- paste0(bits[1],
                 '(',
                 paste(bits[-1],
                       collapse = ', '),
                 ')')
  
  # sorry about this spaghetti...
  workflow <- paste0(paste(bits[-2], 
                           c(getSource(workflow),
                             getSource(occurrenceFn),
                             getSource(covariateFn),
                             getSource(processFn),
                             getSource(modelFn),
                             getSource(mapFn)),
                           sep = ' <- ',
                           collapse = '\n\n'),
                     paste0('\n\n',
                            bits[2],
                            ' <- c(',
                            paste(ext, collapse = ', '),
                            ')\n'),
                     '\nans <- ',
                     call,
                     collapse = '\n\n\n')
  
  return(list(extent = extent,
              occ = occ,
              cov = cov,
              df = df,
              m = m,
              map = map,
              workflow = workflow))
}



# ~~~~~~~~~~~~~~
# test drive it!

# define the extent in lat and long
UKextent <- c(xmin = -10,
              xmax = 10,
              ymin = 45,
              ymax = 65)

# run a workflow, using the logistic regression model
ans1 <- workflow(ext = UKextent,
                 occurrenceFn = occurrenceCp,
                 covariateFn = covariateAir,
                 processFn = processA,
                 modelFn = modelLR,
                 mapFn = mapA)

# switch the model to a RandomForest
ans2 <- workflow(ext = UKextent,
                 occurrenceFn = occurrenceCp,
                 covariateFn = covariateAir,
                 processFn = processA,
                 modelFn = modelRF,
                 mapFn = mapA)

# look at the contents of these lists
str(ans1, 1)
str(ans2, 1)

# plot the resulting maps
par(mfrow = c(1, 2))

plot(ans1$map,
     zlim = c(0,1),
     main = 'LR')

points(ans1$occ[, 1:2],
       pch = 16,
       cex = 0.3)

plot(ans2$map,
     zlim = c(0,1),
     main = 'RF')

points(ans2$occ[, 1:2],
       pch = 16,
       cex = 0.3)

# ~~~~~~~~~~~~~~~
# test run the script it outputted

# save the workflow script somewhere
write(ans1$workflow, file = '~/Desktop/ans1_code.txt')

# clear everything in the workspace
rm(list = ls())

# call the script!
source('~/Desktop/ans1_code.txt')

# plot the first map again
par(mfrow = c(1, 1))

plot(ans$map,
     zlim = c(0,1),
     main = 'LR')

points(ans$occ[, 1:2],
       pch = 16,
       cex = 0.3)
