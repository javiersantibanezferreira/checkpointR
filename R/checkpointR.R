#' @import dplyr
#' @import openxlsx
#' @import tibble

#' Save a checkpoint of an R object with versioning and logging
#'
#' Saves an object to a specified stage folder with version control and logs the save event in an Excel file.
#'
#' @param obj The R object to save. Default is `procdata`.
#' @param name Character. Name of the object to save. Default is `"procdata"`.
#' @param stage Character. Required. Stage name to categorize the checkpoint.
#' @param comment Optional character. Additional comment to record with the checkpoint.
#'
#' @return Invisible NULL. Side effect: saves an .rds file and updates the log.
#' @export
#'
#' @examples
#' \dontrun{
#' check_save(mydata, name = "mydata", stage = "preprocessing", comment = "After cleaning")
#' }
check_save <- function(obj = procdata, name = "procdata", stage, comment = NULL) {
  if (missing(stage) || stage == "") {
    stop("You must specify a 'stage' to save the checkpoint.")
  }

  base_folder <- "4_checkpoint"
  if (!dir.exists(base_folder)) {
    dir.create(base_folder)
  }

  stage_folder <- file.path(base_folder, stage)
  if (!dir.exists(stage_folder)) {
    dir.create(stage_folder)
  }

  log_path <- file.path(base_folder, "log.xlsx")

  if (file.exists(log_path)) {
    log <- openxlsx::read.xlsx(log_path)
  } else {
    log <- data.frame(
      date = character(),
      stage = character(),
      name = character(),
      version = numeric(),
      comment = character(),
      file = character(),
      stringsAsFactors = FALSE
    )
  }

  subset_versions <- log[log$stage == stage & log$name == name, ]
  if (nrow(subset_versions) == 0) {
    version <- 1
  } else {
    version <- max(subset_versions$version) + 1
  }

  attr(obj, "checkpoint_info") <- list(
    name = name,
    stage = stage,
    version = version
  )

  attr(obj, "comment") <- ifelse(is.null(comment), "", comment)

  file_name <- sprintf("%s_%s_v%d.rds", stage, name, version)
  save_path <- file.path(stage_folder, file_name)

  saveRDS(obj, save_path)

  new_log <- data.frame(
    date = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    stage = stage,
    name = name,
    version = version,
    comment = ifelse(is.null(comment), "", comment),
    file = file.path(stage, file_name),
    stringsAsFactors = FALSE
  )

  log <- rbind(log, new_log)

  openxlsx::write.xlsx(log, log_path, overwrite = TRUE)

  message(sprintf("Checkpoint saved: %s (version %d)", file_name, version))
}


#' Load a checkpointed R object by stage, name, and version
#'
#' Loads a previously saved checkpoint object from the specified stage folder.
#'
#' @param stage Character. Stage name where the checkpoint was saved.
#' @param name Character. Name of the object to load. Default is `"procdata"`.
#' @param version Numeric or NULL. Version number to load. If NULL, loads the latest version.
#' @param folder Character. Base folder where checkpoints are stored. Default is `"4_checkpoint"`.
#' @param envir Environment where to assign the loaded object. Default is `.GlobalEnv`.
#' @param quiet Logical. If TRUE, suppresses informational output. Default is FALSE.
#'
#' @return Invisible NULL. Side effect: assigns the loaded object into the environment.
#' @export
#'
#' @examples
#' \dontrun{
#' check_load(stage = "preprocessing", name = "mydata", version = 2)
#' }
check_load <- function(stage, name = "procdata", version = NULL, folder = "4_checkpoint",
                       envir = .GlobalEnv, quiet = FALSE) {
  stage_folder <- file.path(folder, stage)
  log_path <- file.path(folder, "log.xlsx")
  if (!file.exists(log_path)) {
    stop("Log file not found in ", folder)
  }

  log <- openxlsx::read.xlsx(log_path)
  filtered_log <- log[log$stage == stage & log$name == name, ]

  if (nrow(filtered_log) == 0) {
    stop(sprintf("No checkpoints found for stage '%s' and name '%s'.", stage, name))
  }

  if (is.null(version)) {
    version <- max(filtered_log$version)
  }

  version_log <- filtered_log[filtered_log$version == version, ]
  if (nrow(version_log) == 0) {
    stop(sprintf("Version %d not found for stage '%s' and name '%s'.", version, stage, name))
  }

  file_name <- basename(version_log$file)
  file_path <- file.path(stage_folder, file_name)

  if (!file.exists(file_path)) {
    stop("Checkpoint file not found: ", file_path)
  }

  obj <- readRDS(file_path)

  attr(obj, "checkpoint_info") <- list(
    name = name,
    stage = stage,
    version = version
  )

  assign(name, obj, envir = envir)
  date <- format(file.info(file_path)$ctime, "%Y-%m-%d")

  if (!quiet) {
    cat(sprintf("\n  %-8s | %-7s | %-7s | %s\n", "name", "stage", "version", "date"))
    cat(sprintf("  %-8s | %-7s | %-7d | %s\n\n", name, stage, version, date))
  }
  invisible(NULL)
}


#' Overview of available and loaded checkpoints
#'
#' Provides a summary table of saved checkpoint versions and currently loaded checkpoint objects.
#'
#' @param stage Optional character vector. Filter checkpoints by stage(s). Default is NULL (all stages).
#' @param envir Environment to check loaded objects. Default is `.GlobalEnv`.
#'
#' @return A list with two tibbles: `available_versions` and `loaded_bases`.
#' @export
#'
#' @examples
#' \dontrun{
#' overview <- check_overview()
#' print(overview$available_versions)
#' print(overview$loaded_bases)
#' }
check_overview <- function(stage = NULL, envir = .GlobalEnv) {
  log_path <- file.path("4_checkpoint", "log.xlsx")

  if (!file.exists(log_path)) {
    stop("Checkpoint log file does not exist.")
  }

  log <- openxlsx::read.xlsx(log_path)

  if (!is.null(stage)) {
    log <- log %>% dplyr::filter(stage %in% stage)
  }

  log <- log %>%
    dplyr::filter(file.exists(file.path("4_checkpoint", file)))

  if (nrow(log) == 0) {
    message("No checkpoint records with existing files.")
    return(NULL)
  }

  summary <- log %>%
    dplyr::group_by(name, stage) %>%
    dplyr::summarise(
      versions = paste(sort(version), collapse = ", "),
      date = max(date),
      .groups = "drop"
    )

  env_objs <- ls(envir = envir)

  loaded <- lapply(env_objs, function(obj_name) {
    obj <- get(obj_name, envir = envir)
    info <- attr(obj, "checkpoint_info")
    if (!is.null(info)) {
      tibble::tibble(
        name = obj_name,
        stage = info$stage,
        version = info$version,
        date = log %>%
          dplyr::filter(name == obj_name, stage == info$stage, version == info$version) %>%
          dplyr::pull(date) %>%
          dplyr::first()
      )
    } else {
      NULL
    }
  }) %>% dplyr::bind_rows()

  sort_table <- function(df) {
    df %>%
      dplyr::mutate(
        name = factor(name, levels = c("procdata", sort(setdiff(unique(name), "procdata"))))
      ) %>%
      dplyr::arrange(name, stage, if ("versions" %in% colnames(df)) versions else version)
  }

  list(
    available_versions = sort_table(summary),
    loaded_bases = sort_table(loaded)
  )
}


#' Print attributes and metadata of checkpointed objects
#'
#' Displays checkpoint information and comments for loaded or saved objects.
#'
#' @param stage Optional character. Stage name to filter or inspect. If NULL, prints all loaded objects with checkpoint info.
#' @param obj Character. Name of the object to inspect. Default is `"procdata"`.
#' @param version Numeric or NULL. Version to inspect. If NULL, latest version is used.
#'
#' @return Invisible NULL. Prints metadata to console.
#' @export
#'
#' @examples
#' \dontrun{
#' check_attr(stage = "preprocessing", obj = "mydata", version = 2)
#' }
check_attr <- function(stage = NULL, obj = "procdata", version = NULL) {
  if (is.null(stage)) {
    loaded <- ls(envir = .GlobalEnv)

    for (name in loaded) {
      base <- get(name, envir = .GlobalEnv)
      info <- attr(base, "checkpoint_info")
      comment <- attr(base, "comment")

      if (!is.null(info)) {
        folder <- file.path("4_checkpoint", info$stage)
        file_path <- file.path(folder, sprintf("%s_%s_v%d.rds", info$stage, info$name, info$version))
        date <- if (file.exists(file_path)) {
          format(file.info(file_path)$ctime, "%Y-%m-%d %H:%M:%S")
        } else {
          "Date not available"
        }

        cat(sprintf("\n  %-8s | %-7s | %-7s | %s\n", "name", "stage", "version", "date"))
        cat(sprintf("  %-8s | %-7s | %-7d | %s\n", info$name, info$stage, info$version, date))

        if (!is.null(comment)) {
          cat("\n(", comment, ")\n", sep = "")
        } else {
          cat("\n(No comment)\n")
        }
      }
    }

    return(invisible(NULL))
  }

  if (is.null(stage)) {
    stop("You must specify the stage to inspect a specific object.")
  }

  if (is.null(obj)) obj <- "procdata"

  if (is.null(version)) {
    folder <- file.path("4_checkpoint", stage)
    files <- list.files(folder, pattern = paste0("^", stage, "_", obj, "_v[0-9]+\\.rds$"))

    if (length(files) == 0) {
      stop("No checkpoints found for ", obj, " in stage ", stage)
    }

    versions <- as.integer(gsub(paste0("^", stage, "_", obj, "_v([0-9]+)\\.rds$"), "\\1", files))
    version <- max(versions, na.rm = TRUE)
  }

  if (!exists(obj, envir = .GlobalEnv)) {
    check_load(stage = stage, name = obj, version = version)
  } else {
    current <- get(obj, envir = .GlobalEnv)
    attr_info <- attr(current, "checkpoint_info")
    if (is.null(attr_info) || attr_info$version != version || attr_info$stage != stage || attr_info$name != obj) {
      check_load(stage = stage, name = obj, version = version, quiet = TRUE)
    }
  }

  base <- get(obj, envir = .GlobalEnv)
  info <- attr(base, "checkpoint_info")
  comment <- attr(base, "comment")

  folder <- file.path("4_checkpoint", info$stage)
  file_path <- file.path(folder, sprintf("%s_%s_v%d.rds", info$stage, info$name, info$version))
  date <- if (file.exists(file_path)) {
    format(file.info(file_path)$ctime, "%Y-%m-%d %H:%M:%S")
  } else {
    "Date not available"
  }

  cat(sprintf("\n  %-8s | %-7s | %-7s | %s\n", "name", "stage", "version", "date"))
  cat(sprintf("  %-8s | %-7s | %-7d | %s\n", info$name, info$stage, info$version, date))

  if (!is.null(comment)) {
    cat("\n(", comment, ")\n", sep = "")
  } else {
    cat("\n(No comment)\n")
  }

  invisible(NULL)
}

#' Check for Equal Checkpoints in a Given Stage
#'
#' This function compares saved checkpoints within a specified stage and identifies groups of identical objects
#' (ignoring their attributes). It returns a data frame grouping checkpoints that are exactly the same.
#'
#' @param stage A character string specifying the stage folder to check within the "4_checkpoint" directory.
#'
#' @return A data frame listing groups of identical checkpoints with columns:
#' \describe{
#'   \item{ID}{Group identifier (letters).}
#'   \item{name}{Name of the checkpoint object.}
#'   \item{version}{Version number of the checkpoint.}
#'   \item{file}{File path of the checkpoint.}
#' }
#' If no equal checkpoints are found or fewer than two checkpoints exist in the stage, returns NULL with a message.
#'
#' @details
#' The function reads the checkpoint log file "register.xlsx" inside the "4_checkpoint" folder, filters by the specified stage,
#' and loads all existing checkpoint files for comparison. It ignores object attributes when comparing.
#'
#' @examples
#' \dontrun{
#' check_equal("data_cleaning")
#' }
#'
#' @importFrom openxlsx read.xlsx
#' @export
check_equal <- function(stage) {
  strip_attributes <- function(obj) {
    attributes(obj) <- NULL
    obj
  }

  base_folder <- "4_checkpoint"
  stage_folder <- file.path(base_folder, stage)
  log_path <- file.path(base_folder, "register.xlsx")

  if (!file.exists(log_path)) {
    stop("The file 'register.xlsx' does not exist in ", base_folder)
  }

  log <- openxlsx::read.xlsx(log_path)
  log_stage <- log[log$etapa == stage, ]

  # Filter only files that exist
  existing_log <- log_stage[file.exists(file.path(base_folder, log_stage$archivo)), ]

  n <- nrow(existing_log)
  if (n < 2) {
    message("There are not enough existing checkpoints to compare in stage '", stage, "'.")
    return(NULL)
  }

  objects <- vector("list", n)
  files <- file.path(base_folder, existing_log$archivo)
  for (i in seq_len(n)) {
    objects[[i]] <- readRDS(files[i])
  }

  # Create duplicate groups
  groups <- list()
  assigned <- rep(FALSE, n)

  for (i in 1:(n - 1)) {
    if (!assigned[i]) {
      current_group <- i
      assigned[i] <- TRUE
      for (j in (i + 1):n) {
        if (!assigned[j]) {
          if (identical(strip_attributes(objects[[i]]), strip_attributes(objects[[j]]))) {
            current_group <- c(current_group, j)
            assigned[j] <- TRUE
          }
        }
      }
      if (length(current_group) > 1) {
        groups[[length(groups) + 1]] <- current_group
      }
    }
  }

  if (length(groups) == 0) {
    message("No identical checkpoints were found in stage '", stage, "'.")
    return(NULL)
  }

  # Assign letters as group IDs
  letters_id <- LETTERS[seq_along(groups)]

  # Build final data frame
  result <- do.call(rbind, lapply(seq_along(groups), function(idx) {
    idxs <- groups[[idx]]
    data.frame(
      ID = letters_id[idx],
      name = existing_log$nombre[idxs],
      version = existing_log$version[idxs],
      file = existing_log$archivo[idxs],
      stringsAsFactors = FALSE
    )
  }))

  return(result)
}
