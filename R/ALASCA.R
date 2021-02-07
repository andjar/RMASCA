#' Get an ALASCA object
#' 
#' `ALASCA` initializes an ALASCA model and returns an ALASCA object
#'
#' This function builds your ALASCA model. It needs a data frame containing at least a column identifying participants, a column called `time` contining time information, a column `group` containing group information, a column `variable` containing variable names, and a value column. In addition you need to specify the model you want, and whether you want to separate group and time effects (defaults to `TRUE`).
#'
#' @param df Data frame to be analyzed
#' @param formula Regression model
#' @param separateTimeAndGroup Logical: should time and group effect be separated?
#' @param pAdjustMethod Method for correcting p values for multiple testing, see p.adjust.methods
#' @param validate Logical. If `TRUE`, give estimates for robustness
#' @param participantColumn String. Name of the column containing participant identification
#' @param minimizeObject Logical. If `TRUE`, remove unnecessary clutter, optimize for validation
#' @param scaleFun If `TRUE` (default), each variable is scaled to unit SD and zero mean. If `FALSE`, no scaling is performed. You can also provide a custom scaling function that has the data frame `df` as input and output
#' @param forceEqualBaseline Set to `TRUE` to remove interaction between group and first time point (defaults to `FALSE`)
#' @param useSumCoding Set to `TRUE` to use sum coding instead of contrast coding for group (defaults to `FALSE`)
#' @param method Defaults to `NA` where method is either LM or LMM, depending on whether your formula contains a random effect or not
#' @param nValFold Partitions when validating
#' @param nValRuns number of validation runs
#' @param validationMethod among  `loo` (leave-one-out, default)
#' @param validationObject Don't worry about me:)
#' @param validationParticipants Don't worry about me:)
#' @return An ALASCA object
#' 
#' @examples
#' load("PE.Rdata")
#' model <- ALASCA(df = df, formula = value~time*group + (1|ID))
#' 
#' @export
ALASCA <- function(df,
                   formula,
                   separateTimeAndGroup = TRUE,
                   pAdjustMethod = NA,
                   participantColumn = FALSE,
                   validate = FALSE,
                   scaleFun = TRUE,
                   forceEqualBaseline = FALSE,
                   useSumCoding = FALSE,
                   method = NA,
                   minimizeObject = FALSE,
                   nValFold = 7,
                   nValRuns = 50,
                   validationMethod = "loo",
                   validationObject = NA,
                   validationParticipants = NA){

  if(!is.na(validationObject[1])){
    # This is a validation run
    
    object <- validationObject
    # Overwrite some data
    
    ## Unscaled values
    object$df <- validationObject$dfRaw
    
    ## Avoid recursion
    object$validate <- FALSE
    
    ## Save space
    object$minimizeObject <- TRUE
    
    ## Selected participants for this run
    object$validationParticipants <- validationParticipants
    
    ## Keep original object?
    object$validationObject = NULL #validationObject
  }else{
    object <- list(df = df,
                   formula = formula,
                   separateTimeAndGroup = separateTimeAndGroup,
                   pAdjustMethod = pAdjustMethod,
                   participantColumn = participantColumn,
                   validate = validate,
                   scaleFun = scaleFun,
                   forceEqualBaseline = forceEqualBaseline,
                   useSumCoding = FALSE,
                   method = method,
                   minimizeObject = minimizeObject,
                   nValFold = nValFold,
                   nValRuns = nValRuns,
                   validationMethod = validationMethod,
                   validationObject = validationObject,
                   validationParticipants = validationParticipants
    )
  }
  class(object) <- "ALASCA"

  object <- sanitizeObject(object)
  object <- getLMECoefficients(object)
  object <- removeCovars(object)
  object <- separateLMECoefficients(object)
  object <- getEffectMatrix(object)
  object <- doPCA(object)
  object <- cleanPCA(object)
  
  if(object$minimizeObject){
    # To save space, we remove unnecessary embedded data
    object <- removeEmbedded(object)
  }
  if(object$validate){
    object <- validate(object)
  }

  return(object)
}

#' Run RMASCA
#'
#' Same as calling ALASCA with `method = "LMM"`
#'
#' @inheritParams ALASCA
#' @return An ALASCA object
#' @export
RMASCA <- function(...){
  object <- ALASCA(..., method = "LMM")
  return(object)
}

#' Run SMASCA
#'
#' Same as calling ALASCA with `method = "LM"`
#'
#' @inheritParams ALASCA
#' @return An ALASCA object
#' @export
SMASCA <- function(...){
  object <- ALASCA(..., method = "LM")
  return(object)
}

#' Sanitize an ALASCA object
#'
#' This function checks that the input to an ALASCA object is as expected
#'
#' @param object An ALASCA object to be sanitized
#' @return An ALASCA object
sanitizeObject <- function(object){
  
  # Check formula from user
  formulaTerms <- colnames(attr(terms.formula(object$formula),"factors"))
  if(!is.na(object$method)){ 
    # The user has specified a method to use
    if(object$method == "LMM"){
      if(!any(grepl("\\|",formulaTerms))){
        stop("The model must contain at least one random effect. Sure you wanted linear mixed models?")
      }
    }else if(object$method == "LM"){
      if(any(grepl("\\|",formulaTerms))){
        stop("The model contains at least one random effect. Sure you not wanted linear mixed models instead?")
      }
    }else{
      stop("You entered an undefined method. Use `LMM` or `LM`!")
    }
  }else{ 
    # Find which default method to use
    if(any(grepl("\\|",formulaTerms))){
      object$method <- "LMM"
      cat("Will use linear mixed models!\n")
    }else{
      object$method <- "LM"
      cat("Will use linear models!\n")
    }
  }
  
  # Check that the input is as expected
  if(!("time" %in% colnames(object$df))){
    stop("The dataframe must contain a column names 'time'")
  }
  if(!("group" %in% colnames(object$df))){
    stop("The dataframe must contain a column names 'group'")
  }
  if(!("variable" %in% colnames(object$df))){
    stop("The dataframe must contain a column names 'variable'")
  }

  if(object$minimizeObject){
    # This is usually a validation object
    object$df <- object$df[object$validationParticipants,]
    partColumn <- which(colnames(object$df) == object$participantColumn)
    object$df[,partColumn] <- factor(object$df[,partColumn])
  }
  
  object$df$time <- factor(object$df$time)
  object$df$group <- factor(object$df$group)
  object$df$variable <- factor(object$df$variable)

  if(any(is.na(object$df$time) | is.na(object$df$group))){
    cat("\n\n!!! -> Oh dear, at least on of your rows is missing either time or group. I have removed it/them for now, but you should check if this is a problem...\n\n")
    object$df <- object$df[!is.na(object$df$time) & !is.na(object$df$group),]
  }
  
  # Keep a copy of unscaled data
  object$dfRaw <- object$df
  
  # Use sum coding?
  if(object$useSumCoding){
    contrasts(object$df$group) <- contr.sum(length(unique(object$df$group)))
  }
  
  if(is.function(object$scaleFun)){
    if(!object$minimizeObject){
      cat("Scaling data with custom function...\n")
    }
    for(i in unique(object$df$variable)){
      object$df <- scaleFun(object$df)
    }
  }else if(object$scaleFun == TRUE){
    if(!object$minimizeObject){
      cat("Scaling data...\n")
    }
    for(i in unique(object$df$variable)){
      valColumn <- which(as.character(object$formula)[2] == colnames(object$df))
      object$df[object$df$variable == i,valColumn] <- (object$df[object$df$variable == i,valColumn] - mean(object$df[object$df$variable == i,valColumn]))/sd(object$df[object$df$variable == i,valColumn])
    }
  }else{
    if(!object$minimizeObject){
      cat("Not scaling data...\n")
    }
  }

  object$hasGroupTerm <- ifelse(any(formulaTerms == "group"), TRUE, FALSE)
  # if(!object$hasGroupTerm){
  #   object$separateTimeAndGroup <- FALSE
  # }
  object$hasInteractionTerm <- ifelse(any(formulaTerms == "group:time" | formulaTerms == "time:group"), TRUE, FALSE)
  object$covars <- formulaTerms[!(formulaTerms %in% c("time","group","group:time","time:group"))]

  return(object)
}

#' Remove df from objectt
#'
#' This function checks that the input to an ALASCA object is as expected
#'
#' @param object An ALASCA object
#' @return An ALASCA object
removeEmbedded <- function(object){
  object$df <- NULL
  object$dfRaw <- NULL
  object$validationObject <- NULL
  object$lmer.models <- NULL
  object$LMM.coefficients <- NULL
  object$effect.matrix <- NULL
  return(object)
}

#' Flip an ALASCA object
#'
#' Changes the sign of loadings and scores
#'
#' @param object An ALASCA object
#' @return An ALASCA object
#' @export
flipIt <- function(object){
  PC_col <- Reduce(cbind,lapply(object$ALASCA$score$time[1,], FUN = function(x) is.numeric(x)))
  object$ALASCA$score$time[,PC_col] <- object$ALASCA$score$time[,PC_col]*(-1)
  PC_col <- Reduce(cbind,lapply(object$ALASCA$loading$time[1,], FUN = function(x) is.numeric(x)))
  object$ALASCA$loading$time[,PC_col] <- object$ALASCA$loading$time[,PC_col]*(-1)
  if(object$separateTimeAndGroup){
    PC_col <- Reduce(cbind,lapply(object$ALASCA$score$group[1,], FUN = function(x) is.numeric(x)))
    object$ALASCA$score$group[,PC_col] <- object$ALASCA$score$group[,PC_col]*(-1)
    PC_col <- Reduce(cbind,lapply(object$ALASCA$loading$group[1,], FUN = function(x) is.numeric(x)))
    object$ALASCA$loading$group[,PC_col] <- object$ALASCA$loading$group[,PC_col]*(-1)
  }
  if(object$validate){
    PC_col <- Reduce(cbind,lapply(object$validation$score$time[1,], FUN = function(x) is.numeric(x)))
    object$validation$score$time[,PC_col] <- object$validation$score$time[,PC_col]*(-1)
    PC_col <- Reduce(cbind,lapply(object$validation$loading$time[1,], FUN = function(x) is.numeric(x)))
    object$validation$loading$time[,PC_col] <- object$validation$loading$time[,PC_col]*(-1)
    if(object$separateTimeAndGroup){
      PC_col <- Reduce(cbind,lapply(object$validation$score$group[1,], FUN = function(x) is.numeric(x)))
      object$validation$score$group[,PC_col] <- object$validation$score$group[,PC_col]*(-1)
      PC_col <- Reduce(cbind,lapply(object$validation$loading$group[1,], FUN = function(x) is.numeric(x)))
      object$validation$loading$group[,PC_col] <- object$validation$loading$group[,PC_col]*(-1)
    }
  }
  return(object)
}