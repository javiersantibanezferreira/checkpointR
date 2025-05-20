#' checkpointR: Versioned Checkpoints for R Projects
#'
#' Tools for saving, tagging, loading and managing data object checkpoints across stages.
#'
#' @keywords internal
#' @import openxlsx dplyr tibble
#' @name checkpointR
"_PACKAGE"
NULL

#' Save a checkpoint of an R object with versioning and logging
#'
#' Saves an object to a versioned .rds file and logs the event in a structured Excel file.
#'
#' @param obj The R object to save. Defaults to `procdata`.
#' @param name Optional. Character. Name to save the object as. Defaults to name of `obj`.
#' @param stage Character. Required. Project stage to categorize the checkpoint.
#' @param comment Optional. Comment to include in the log.
#'
#' @return Invisible NULL. Side effect: saves an .rds file and updates the log.
#' @export
check_save <- function(stage, obj = procdata, name = NULL, comment = NULL) {
  if (missing(name)) name <- deparse(substitute(obj))
  args <- normalize_args(stage = stage, name = name, comment = comment, obj = obj)
  if (toupper(args$stage) == "TAG") {
    stop("❌ 'TAG' cannot be used as a stage name. It is reserved for visual formatting.")
  }
  folder <- "4_checkpoint"
  if (!dir.exists(folder)) dir.create(folder)

  log_path <- file.path(folder, "log.xlsx")

  if (file.exists(log_path)) {
    log_df <- openxlsx::read.xlsx(log_path)
    log_df <- upgrade_log_format(log_df)
  } else {
    log_df <- data.frame(
      TAG = character(),
      STAGE = character(),
      NAME = character(),
      VERSION = integer(),
      DATE = character(),
      COMMENT = character(),
      ID = character(),
      FILE = character(),
      DATE_UNIX = numeric(),
      IS_TAG = logical(),
      stringsAsFactors = FALSE
    )
  }

  subset_versions <- log_df[log_df$STAGE == args$stage & log_df$NAME == args$name & log_df$IS_TAG == FALSE, ]
  version <- if (nrow(subset_versions) == 0) 1 else max(subset_versions$VERSION) + 1

  file_name <- sprintf("%s_%s_v%d.rds", args$stage, args$name, version)
  save_path <- file.path(folder, args$stage, file_name)
  if (!dir.exists(dirname(save_path))) dir.create(dirname(save_path), recursive = TRUE)

  saveRDS(obj, save_path)

  now <- Sys.time()
  now_unix <- as.numeric(now)
  ID <- generate_id(stage = args$stage, name = args$name, version = version)

  new_row <- data.frame(
    TAG = "",
    STAGE = args$stage,
    NAME = args$name,
    VERSION = version,
    DATE = format(now, "%Y-%m-%d %H:%M:%S"),
    COMMENT = ifelse(is.null(args$comment), "", args$comment),
    ID = ID,
    FILE = file.path(args$stage, file_name),
    DATE_UNIX = now_unix,
    IS_TAG = FALSE,
    stringsAsFactors = FALSE
  )

  log_df <- rbind(log_df, new_row)

  # === ESTILO EXCEL ===
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "log")

  # Estilos
  style_center <- openxlsx::createStyle(halign = "center")
  style_nowrap <- openxlsx::createStyle(wrapText = FALSE)
  style_border <- openxlsx::createStyle(border = "bottom", borderColour = "black")
  style_header_full <- openxlsx::createStyle(
    textDecoration = "bold",
    halign = "center",
    fgFill = "#84b6f4",
    border = "bottom",
    borderColour = "black"
  )


  style_gray <- openxlsx::createStyle(fgFill = "#F2F2F2")
  style_white <- openxlsx::createStyle(fgFill = "#FFFFFF")

  style_tag_row <- openxlsx::createStyle(textDecoration = "bold", fgFill = "#C6EFCE")  # verde pastel
  style_tag_stage <- openxlsx::createStyle(fontColour = "#FF0000", textDecoration = "bold") # rojo
  style_tag_version <- openxlsx::createStyle(fontColour = "#FF0000", halign = "center")     # rojo centrado
  style_tag_border <- openxlsx::createStyle(border = "topBottom", borderColour = "black")

  cols_order <- c("TAG", "STAGE", "NAME", "VERSION", "DATE", "COMMENT", "ID", "FILE", "DATE_UNIX", "IS_TAG")
  log_df <- log_df[, cols_order]
  log_df <- log_df[order(-log_df$DATE_UNIX), ]

  openxlsx::writeData(wb, "log", log_df, headerStyle = style_header_full)

  # Ocultar columnas
  hidden_cols <- which(names(log_df) %in% c("FILE", "DATE_UNIX", "IS_TAG"))
  for (col in hidden_cols) {
    openxlsx::setColWidths(wb, "log", cols = col, widths = 0, hidden = TRUE)
  }

  # Estética general por filas
  for (i in 1:nrow(log_df)) {
    row_index <- i + 1
    is_tag <- log_df$IS_TAG[i]

    if (is_tag) {
      # Estilo fila tag
      openxlsx::addStyle(wb, "log", style_tag_row, rows = row_index, cols = 1:ncol(log_df), gridExpand = TRUE)
      openxlsx::addStyle(wb, "log", style_tag_stage, rows = row_index, cols = which(names(log_df) == "STAGE"), stack = TRUE)
      openxlsx::addStyle(wb, "log", style_tag_version, rows = row_index, cols = which(names(log_df) == "VERSION"), stack = TRUE)
      openxlsx::addStyle(wb, "log", style_tag_border, rows = row_index, cols = 1:ncol(log_df), gridExpand = TRUE, stack = TRUE)

    } else {
      # Intercalado por tag
      tag_val <- log_df$TAG[i]
      idx_in_tag <- which(log_df$TAG == tag_val & !log_df$IS_TAG)
      rank <- which(idx_in_tag == i)
      if (length(rank) > 0) {
        fill <- if ((rank %% 2) == 0) style_gray else style_white
        openxlsx::addStyle(wb, "log", fill, rows = row_index, cols = 1:ncol(log_df), gridExpand = TRUE)
      }
    }
  }

  # Centrado y ancho de VERSION
  version_col <- which(names(log_df) == "VERSION")
  header_width <- nchar("VERSION")
  value_width <- max(nchar(as.character(log_df$VERSION)), na.rm = TRUE)
  max_width <- max(header_width, value_width) + 2
  openxlsx::addStyle(wb, "log", style_center, cols = version_col, rows = 2:(nrow(log_df) + 1), gridExpand = TRUE, stack = TRUE)
  openxlsx::setColWidths(wb, "log", cols = version_col, widths = max_width)

  # Ajustar el resto de columnas visibles
  visible_cols <- setdiff(names(log_df), c("DATE_UNIX", "IS_TAG", "VERSION", "FILE"))
  for (colname in visible_cols) {
    idx <- which(names(log_df) == colname)
    openxlsx::setColWidths(wb, "log", cols = idx, widths = "auto")
  }

  # Guardar workbook
  openxlsx::saveWorkbook(wb, log_path, overwrite = TRUE)
  message(sprintf("🏷️️  Checkpoint saved: [%s] %s v%d → %s", args$stage, args$name, version, file.path(args$stage, file_name)))
  invisible(NULL)
}

#' Load a saved checkpoint object from a given stage and version
#'
#' @param stage Character. Stage from which to load the checkpoint.
#' @param name Character. Name of the object to load. Default is "procdata".
#' @param version Integer. Specific version to load. If NULL, loads the most recent.
#' @param folder Character. Folder where checkpoints are stored. Default is "4_checkpoint".
#' @param envir Environment. Where to assign the loaded object. Default is global environment.
#' @param quiet Logical. If TRUE, suppress console output. Default is FALSE.
#'
#' @return Invisible NULL. Assigns the object in the specified environment.
#' @export
check_load <- function(stage, name = "procdata", version = NULL, folder = "4_checkpoint",
                       envir = .GlobalEnv, quiet = FALSE) {
  if (stage == "TAG") stop("❌ Stage name 'TAG' is reserved and cannot be used.")
  stage_folder <- file.path(folder, stage)
  log_path <- file.path(folder, "log.xlsx")

  if (!file.exists(log_path)) {
    stop("❌ Log file not found in ", folder)
  }

  log <- openxlsx::read.xlsx(log_path)
  log <- upgrade_log_format(log)

  filtered_log <- log[log$STAGE == stage & log$NAME == name & log$IS_TAG == FALSE, ]

  if (nrow(filtered_log) == 0) {
    stop(sprintf("❌ No checkpoints found for stage '%s' and name '%s'.", stage, name))
  }

  if (is.null(version)) {
    version <- max(filtered_log$VERSION)
  }

  version_log <- filtered_log[filtered_log$VERSION == version, ]
  if (nrow(version_log) == 0) {
    stop(sprintf("❌ Version %d not found for stage '%s' and name '%s'.", version, stage, name))
  }

  file_name <- basename(version_log$FILE)
  file_path <- file.path(stage_folder, file_name)

  if (!file.exists(file_path)) {
    stop("❌ Checkpoint file not found: ", file_path)
  }

  obj <- readRDS(file_path)

  attr(obj, "checkpoint_info") <- list(
    name = name,
    stage = stage,
    version = version
  )

  assign(name, obj, envir = envir)

  if (!quiet) {
    message(sprintf("✅ Loaded checkpoint: [%s] %s v%d", stage, name, version))
  }

  invisible(NULL)
}

#' Show an overview of available and loaded checkpoints
#'
#' @param stage Optional character vector. If provided, filters by stage(s).
#' @param envir Environment. The environment where loaded objects are searched. Default is global.
#'
#' @return A list with two tibbles: available_versions and loaded_bases.
#' @export
check_overview <- function(stage = NULL, envir = .GlobalEnv) {
  log <- load_log()
  if (is.null(stage)) {
    ov1(log = log, envir = envir)
  } else if (toupper(stage) == "TAGS") {
    ov3(log = log)
  } else {
    ov2(log = log, stage = stage)
  }
}


#' Display attributes of checkpointed objects
#'
#' Shows checkpoint metadata for a specific object or for all loaded objects with checkpoint attributes.
#'
#' @param stage Optional. Character. Stage name to filter or load from. If NULL, checks all loaded objects.
#' @param name Optional. Character. Name of the object to inspect. Default is `"procdata"`.
#' @param version Optional. Numeric. Version to inspect. If NULL, uses the most recent version.
#'
#' @return Invisibly returns NULL. Outputs formatted checkpoint metadata to the console.
#' @export
check_attr <- function(stage = NULL, name = "procdata", version = NULL) {
  log_df <- load_log()
  if (is.null(stage)) {
    loaded <- ls(envir = .GlobalEnv)
    rows <- list()

    for (name_loaded in loaded) {
      base <- get(name_loaded, envir = .GlobalEnv)
      info <- attr(base, "checkpoint_info")
      row_log <- log_df[log_df$STAGE == info$stage & log_df$NAME == info$name &
                          log_df$VERSION == info$version & !log_df$IS_TAG, ]

      comment <- ifelse(nrow(row_log) == 0 || row_log$COMMENT == "", "(no comment)", row_log$COMMENT)
      tag <- ifelse(nrow(row_log) == 0 || is.na(row_log$TAG) || row_log$TAG == "", "(no tag)", row_log$TAG)

      log_df <- log_df[log_df$STAGE == info$stage & log_df$NAME == info$name & log_df$VERSION == info$version, ]

      if (nrow(log_df) > 0) {
        comment <- ifelse(is.na(log_df$COMMENT) || log_df$COMMENT == "", "(no comment)", log_df$COMMENT)
      } else {
        comment <- "(no comment)"
      }


      if (!is.null(info)) {
        folder <- file.path("4_checkpoint", info$stage)
        file_path <- file.path(folder, sprintf("%s_%s_v%d.rds", info$stage, info$name, info$version))
        date <- if (file.exists(file_path)) {
          format(file.info(file_path)$ctime, "%Y-%m-%d %H:%M:%S")
        } else {
          "Date not available"
        }

        comment_text <- ifelse(is.null(comment) || comment == "", "(no comment)", comment)

        rows[[length(rows) + 1]] <- list(
          NAME = info$name,
          STAGE = info$stage,
          VERSION = info$version,
          DATE = date,
          COMMENT = comment_text
        )
      }
    }

    if (length(rows) == 0) {
      message("❌ No loaded objects with checkpoint information found.")
      return(invisible(NULL))
    }

    df <- do.call(rbind.data.frame, rows)
    names(df) <- c("NAME", "STAGE", "VERSION", "DATE", "COMMENT")

    cat("\n✅ ATTRIBUTES FOR LOADED OBJECTS ✅\n\n")
    headers <- c("NAME", "STAGE", "VERSION", "TAG", "DATE")
    widths <- sapply(df[headers], function(col) max(nchar(as.character(col))))
    headers_fmt <- mapply(format, headers, width = widths, MoreArgs = list(justify = "centre"))
    separator <- paste(rep(".", sum(widths) + 3 * (length(headers) - 1)), collapse = "")

    cat(paste(headers_fmt, collapse = "   "), "\n")
    cat(separator, "\n")

    for (i in seq_len(nrow(df))) {
      row <- sapply(seq_along(headers), function(j) {
        col_value <- as.character(df[i, headers[j]])
        align <- if (headers[j] %in% c("VERSION", "DATE")) "centre" else "left"
        format(col_value, width = widths[j], justify = align)
      })
      cat(paste(row, collapse = "   "), "
")
    }

    cat("\nCOMMENTS:\n")
    for (i in seq_len(nrow(df))) {
      cat(sprintf("%s v%d: %s\n", df$NAME[i], df$VERSION[i], df$COMMENT[i]))
    }

    return(invisible(NULL))
  }

  if (is.null(stage)) {
    stop("❌ You must specify the stage to inspect a specific object.")
  }

  if (is.null(name)) name <- "procdata"

  if (is.null(version)) {
    folder <- file.path("4_checkpoint", stage)
    files <- list.files(folder, pattern = paste0("^", stage, "_", name, "_v[0-9]+\\.rds$"))

    if (length(files) == 0) {
      stop("❌ No checkpoints found for ", name, " in stage ", stage)
    }

    versions <- as.integer(gsub(paste0("^", stage, "_", name, "_v([0-9]+)\\.rds$"), "\\1", files))
    version <- max(versions, na.rm = TRUE)
  }

  if (!exists(name, envir = .GlobalEnv)) {
    check_load(stage = stage, name = name, version = version, quiet = TRUE)
  } else {
    current <- get(name, envir = .GlobalEnv)
    attr_info <- attr(current, "checkpoint_info")
    if (is.null(attr_info) || attr_info$version != version || attr_info$stage != stage || attr_info$name != name) {
      check_load(stage = stage, name = name, version = version, quiet = TRUE)
    }
  }

  base <- get(name, envir = .GlobalEnv)
  info <- attr(base, "checkpoint_info")
  row_log <- log_df[log_df$STAGE == info$stage & log_df$NAME == info$name &
                      log_df$VERSION == info$version & !log_df$IS_TAG, ]

  comment <- ifelse(nrow(row_log) == 0 || row_log$COMMENT == "", "(no comment)", row_log$COMMENT)
  tag <- ifelse(nrow(row_log) == 0 || is.na(row_log$TAG) || row_log$TAG == "", "(no tag)", row_log$TAG)

  folder <- file.path("4_checkpoint", info$stage)
  file_path <- file.path(folder, sprintf("%s_%s_v%d.rds", info$stage, info$name, info$version))
  date <- if (file.exists(file_path)) {
    format(file.info(file_path)$ctime, "%Y-%m-%d %H:%M:%S")
  } else {
    "Date not available"
  }

  comment_text <- ifelse(is.null(comment) || comment == "", "(no comment)", comment)

  cat("\n✅ CHECKPOINT ATTRIBUTES ✅\n\n")
  cat(sprintf("%-8s | %-7s | %-7s | %s\n", "NAME", "STAGE", "VERSION", "TAG", "DATE"))
  cat("-----------------------------------------------\n")
  cat(sprintf("%-8s | %-7s | v%-6d | %s\n\n", info$name, info$stage, info$version, tag, date))
  cat("COMMENT:\n")
  cat(comment_text, "\n")
  # Comentario del TAG si existe
  tag_row <- log[log$IS_TAG & log$TAG == tag, ]
  if (nrow(tag_row) > 0) {
    tag_comment <- tag_row$COMMENT
    tag_comment <- ifelse(is.na(tag_comment) || tag_comment == "", "(no comment)", tag_comment)
    cat("\nTAG COMMENT:\n")
    cat(tag_comment, "\n")
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

#' Register a tag and apply it to previous checkpoints
#'
#' Creates a tag with a comment and assigns it to all prior untagged checkpoints.
#' If an `ID` is specified, the tag is applied only to that checkpoint.
#'
#' @param tag Character. Required. Tag label.
#' @param ID Optional. Full ID of a specific checkpoint to tag.
#' @param comment Optional. A comment associated with the tag.
#'
#' @return Invisibly returns the new tag entry as a data.frame.
#' @export
check_tag <- function(tag, comment = "") {
  if (missing(tag) || is.null(tag)) {
    stop("❌ You must provide a 'tag' value.")
  }

  folder <- "4_checkpoint"
  if (!dir.exists(folder)) dir.create(folder)
  log_path <- file.path(folder, "log.xlsx")

  if (!file.exists(log_path)) stop("❌ Cannot tag: log.xlsx not found.")
  log_df <- openxlsx::read.xlsx(log_path)
  log_df <- upgrade_log_format(log_df)

  now <- Sys.time()
  now_unix <- as.numeric(now)

  # Último tag previo (si existe)
  last_tag_time <- max(c(0, log_df$DATE_UNIX[log_df$IS_TAG]), na.rm = TRUE)

  # Identificar checkpoints sin tag y posteriores al último tag
  eligible_rows <- which(!log_df$IS_TAG & (is.na(log_df$TAG) | log_df$TAG == "") & log_df$DATE_UNIX > last_tag_time)
  log_df$TAG[eligible_rows] <- tag

  # Crear fila nueva de tag
  tag_row <- data.frame(
    TAG = tag,
    STAGE = "TAG",
    NAME = "--",
    VERSION = length(which(log_df$IS_TAG)) + 1,
    DATE = format(now, "%Y-%m-%d %H:%M:%S"),
    COMMENT = comment,
    ID = paste0("tag:", tag),
    FILE = NA,
    DATE_UNIX = now_unix,
    IS_TAG = TRUE,
    stringsAsFactors = FALSE
  )

  log_df <- rbind(log_df, tag_row)

  # === ESTILO EXCEL ===
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "log")

  # Estilos
  style_header <- openxlsx::createStyle(textDecoration = "bold", halign = "center", fgFill = "#84b6f4", border = "bottom", borderColour = "black")
  style_center <- openxlsx::createStyle(halign = "center")
  style_nowrap <- openxlsx::createStyle(wrapText = FALSE)
  style_border <- openxlsx::createStyle(border = "bottom", borderColour = "black")
  style_gray <- openxlsx::createStyle(fgFill = "#F2F2F2")
  style_white <- openxlsx::createStyle(fgFill = "#FFFFFF")
  style_tag_stage <- openxlsx::createStyle(fontColour = "#FF0000", textDecoration = "bold")
  style_tag_version <- openxlsx::createStyle(fontColour = "#FF0000", halign = "center")
  style_tag_row <- openxlsx::createStyle(textDecoration = "bold", fgFill = "#C6EFCE")
  style_tag_border <- openxlsx::createStyle(border = "topBottom", borderColour = "black")

  cols_order <- c("TAG", "STAGE", "NAME", "VERSION", "DATE", "COMMENT", "ID", "FILE", "DATE_UNIX", "IS_TAG")
  log_df <- log_df[, cols_order]
  log_df <- log_df[order(-log_df$DATE_UNIX), ]

  openxlsx::writeData(wb, "log", log_df, headerStyle = style_header)
  openxlsx::addStyle(wb, "log", style_header, rows = 1, cols = 1:ncol(log_df), gridExpand = TRUE)

  # Ocultar columnas
  hidden_cols <- which(names(log_df) %in% c("FILE", "DATE_UNIX", "IS_TAG"))
  for (col in hidden_cols) {
    openxlsx::setColWidths(wb, "log", cols = col, widths = 0, hidden = TRUE)
  }

  for (i in 1:nrow(log_df)) {
    row_index <- i + 1
    is_tag <- log_df$IS_TAG[i]

    if (is_tag) {
      openxlsx::addStyle(wb, "log", style_tag_row, rows = row_index, cols = 1:ncol(log_df), gridExpand = TRUE)
      openxlsx::addStyle(wb, "log", style_tag_stage, rows = row_index, cols = which(names(log_df) == "STAGE"), stack = TRUE)
      openxlsx::addStyle(wb, "log", style_tag_version, rows = row_index, cols = which(names(log_df) == "VERSION"), stack = TRUE)
      openxlsx::addStyle(wb, "log", style_tag_border, rows = row_index, cols = 1:ncol(log_df), gridExpand = TRUE, stack = TRUE)

    } else {
      tag_val <- log_df$TAG[i]
      idx_in_tag <- which(log_df$TAG == tag_val & !log_df$IS_TAG)
      rank <- which(idx_in_tag == i)
      if (length(rank) > 0) {
        fill <- if ((rank %% 2) == 0) style_gray else style_white
        openxlsx::addStyle(wb, "log", fill, rows = row_index, cols = 1:ncol(log_df), gridExpand = TRUE)
      }
    }
  }

  # Ajustes de ancho y alineación
  version_col <- which(names(log_df) == "VERSION")
  header_width <- nchar("VERSION")
  value_width <- max(nchar(as.character(log_df$VERSION)), na.rm = TRUE)
  max_width <- max(header_width, value_width) + 2
  openxlsx::addStyle(wb, "log", style_center, cols = version_col, rows = 2:(nrow(log_df) + 1), gridExpand = TRUE, stack = TRUE)
  openxlsx::setColWidths(wb, "log", cols = version_col, widths = max_width)

  visible_cols <- setdiff(names(log_df), c("DATE_UNIX", "IS_TAG", "FILE", "VERSION"))
  for (colname in visible_cols) {
    idx <- which(names(log_df) == colname)
    openxlsx::setColWidths(wb, "log", cols = idx, widths = "auto")
  }

  openxlsx::saveWorkbook(wb, log_path, overwrite = TRUE)
  message(sprintf("🏷️️  Tag '%s' saved and applied to %d checkpoint(s).", tag, length(eligible_rows)))
  invisible(tag_row)
}

#' Show registered checkpoint tags
#'
#' Displays information from the tags log (`tags_log.xlsx`) including summaries, specific tags, or the latest tag.
#'
#' @param stage Optional. Character. Stage name. Use `"stages"` to show one tag per stage.
#' @param version Optional. Integer. Specific version to display from a stage.
#'
#' @return Invisibly returns NULL. Outputs tag data to the console.
#' @export
check_tags <- function(stage = NULL, version = NULL) {
  log_path <- file.path("4_checkpoint", "tags_log.xlsx")
  if (!dir.exists("4_checkpoint")) dir.create("4_checkpoint")

  if (!file.exists(log_path)) {
    empty_df <- data.frame(
      STAGE = character(),
      VERSION = integer(),
      DATE = character(),
      COMMENT = character(),
      DATE_UNIX = numeric(),
      stringsAsFactors = FALSE
    )
    openxlsx::write.xlsx(empty_df, log_path)
  }

  tags <- openxlsx::read.xlsx(log_path)

  if (nrow(tags) == 0) {
    message("❌ No tags found in tags_log.xlsx.")
    return(invisible(NULL))
  }

  tags$date <- as.POSIXct(tags$DATE_UNIX, origin = "1970-01-01", tz = "UTC")

  # === 1. SUMMARY OF STAGES ===
  if (!is.null(stage) && stage == "stages") {
    summary_df <- tags |>
      dplyr::group_by(STAGE) |>
      dplyr::slice_max(order_by = date, n = 1) |>
      dplyr::ungroup() |>
      dplyr::arrange(dplyr::desc(date)) |>
      dplyr::mutate(date_short = format(date, "%d %b %Y")) |>
      dplyr::select(STAGE, VERSION, date_short)

    cat("\n✅ TAG STAGES SUMMARY ✅\n\n")
    cat(sprintf("%-15s | %-7s | %-17s\n", "STAGE", "VERSION", "LAST COMMENT DATE"))
    cat("----------------------------------------------------\n")
    for (i in seq_len(nrow(summary_df))) {
      cat(sprintf("%-15s | v%-6d | %-17s\n",
                  summary_df$STAGE[i], summary_df$VERSION[i], summary_df$date_short[i]))
    }
    return(invisible(NULL))
  }

  # === 2. SPECIFIC TAG ===
  if (!is.null(stage) && !is.null(version)) {
    tag_row <- tags[tags$STAGE == stage & tags$VERSION == version, ]
    if (nrow(tag_row) == 0) {
      message(sprintf("❌ No tag found for stage '%s' with version %d.", stage, version))
      return(invisible(NULL))
    }
    cat(sprintf("\n✅ TAG FOR STAGE: %s | VERSION v%d ✅\n\n", toupper(stage), version))
    cat(sprintf("%-8s | %-19s\n", "VERSION", "DATE AND TIME"))
    cat("--------------------------------\n")
    cat(sprintf("v%-7d | %s\n\n", tag_row$VERSION, format(tag_row$date, "%Y-%m-%d %H:%M:%S")))
    cat("COMMENT:\n")
    comment_text <- ifelse(is.na(tag_row$COMMENT) || tag_row$COMMENT == "", "(no comment)", tag_row$COMMENT)
    cat(sprintf("%s\n", comment_text))
    return(invisible(NULL))
  }

  # === 3. ALL TAGS FOR A STAGE ===
  if (!is.null(stage)) {
    stage_tags <- tags[tags$STAGE == stage, ]
    if (nrow(stage_tags) == 0) {
      message(sprintf("❌ No tags found for stage '%s'.", stage))
      return(invisible(NULL))
    }

    stage_tags <- stage_tags[order(stage_tags$date, decreasing = TRUE), ]
    cat(sprintf("\n✅ TAGS FOR STAGE: %s ✅\n\n", toupper(stage)))
    cat(sprintf("%-8s | %-19s\n", "VERSION", "DATE AND TIME"))
    cat("--------------------------------\n")
    for (i in seq_len(nrow(stage_tags))) {
      cat(sprintf("v%-7d | %s\n", stage_tags$VERSION[i], format(stage_tags$date[i], "%Y-%m-%d %H:%M:%S")))
    }
    cat("\nCOMMENTS:\n")
    for (i in seq_len(nrow(stage_tags))) {
      comment <- ifelse(is.na(stage_tags$COMMENT[i]) || stage_tags$COMMENT[i] == "", "(no comment)", stage_tags$COMMENT[i])
      cat(sprintf("v%d: %s\n", stage_tags$VERSION[i], comment))
    }
    return(invisible(NULL))
  }

  # === 4. LAST TAG OVERALL ===
  last_tag <- tags[which.max(tags$date), ]
  cat("\n✅ LAST TAG ✅\n\n")
  cat(sprintf("%-10s | %-8s | %-10s\n", "STAGE", "VERSION", "DATE"))
  cat("------------------------------------\n")
  cat(sprintf("%-10s | v%-7d | %s\n\n",
              last_tag$STAGE,
              last_tag$VERSION,
              format(last_tag$date, "%Y-%m-%d")))
  comment_text <- ifelse(is.na(last_tag$COMMENT) || last_tag$COMMENT == "", "(no comment)", last_tag$COMMENT)
  cat(comment_text, "\n")
  return(invisible(NULL))
}

# ---- FUNCIONES AUXILIARES GENERALES----

generate_id <- function(stage, name, version = NULL, tag = NULL) {
  id <- paste0(
    if (!is.null(tag)) paste0("tag:", tag, "_") else "",
    "stage:", stage, "_",
    "name:", name,
    if (!is.null(version)) paste0("_v", version) else ""
  )
  return(id)
}

parse_id <- function(ID) {
  # Extraer partes con expresiones regulares
  tag <- if (grepl("^tag:", ID)) sub("^tag:([^_]+)_.*", "\\1", ID) else NULL
  stage <- sub(".*stage:([^_]+)_.*", "\\1", ID)
  name <- sub(".*name:([^_]+)(_v[0-9]+)?$", "\\1", ID)
  version <- if (grepl("_v[0-9]+$", ID)) {
    as.numeric(sub(".*_v([0-9]+)$", "\\1", ID))
  } else {
    NULL
  }

  return(list(tag = tag, stage = stage, name = name, version = version))
}

normalize_args <- function(stage = NULL, name = NULL, version = NULL,
                           tag = NULL, comment = NULL, obj = NULL,
                           ID = NULL) {
  if (!is.null(ID)) {
    parsed <- parse_id(ID)
    tag <- parsed$tag
    stage <- parsed$stage
    name <- parsed$name
    version <- parsed$version
  }

  if (is.null(stage)) stop("❌ 'stage' is required.")

  # Si obj no fue entregado explícitamente, usar procdata
  if (missing(obj)) obj <- procdata
  if (is.null(obj)) obj <- procdata
  if (is.null(ID)) {
    ID <- generate_id(stage, name, version, tag)
  }

  return(list(
    stage = stage,
    name = name,
    version = version,
    tag = tag,
    comment = comment,
    obj = obj,
    ID = ID
  ))
}

upgrade_log_format <- function(log_df) {
  if (!"ID" %in% names(log_df)) {
    log_df$ID <- mapply(generate_id, log_df$stage, log_df$name, log_df$version, MoreArgs = list(tag = NULL))
  }
  if (!"IS_TAG" %in% names(log_df)) {
    log_df$IS_TAG <- FALSE
  }
  return(log_df)
}

load_log <- function(path = "4_checkpoint/log.xlsx") {
  if (!file.exists(path)) {
    stop("❌ Log file not found at: ", path)
  }

  # Cargar log
  log <- openxlsx::read.xlsx(path)

  # Verificación mínima
  required_cols <- c("STAGE", "NAME", "VERSION", "FILE", "DATE_UNIX", "COMMENT", "TAG")
  missing <- setdiff(required_cols, names(log))
  if (length(missing) > 0) {
    stop("❌ Missing required columns in log: ", paste(missing, collapse = ", "))
  }

  # Normalización
  log <- upgrade_log_format(log)

  return(log)
}

# ----  TAG AUXILIARES PARA OVERVIEW ----
#TAG
last_tag <- function(log) {
  log <- log[log$TAG != "" & !is.na(log$TAG), ]

  if (nrow(log) == 0) {
    cat("⚠️ No tags found in log.\n")
    return(invisible(NULL))
  }

  tag_row <- log[log$IS_TAG, ]
  tag_row <- tag_row[which.max(tag_row$DATE_UNIX), ]
  tag_id <- tag_row$TAG
  tag_version <- tag_row$VERSION
  tag_date <- format(as.POSIXct(tag_row$DATE_UNIX, origin = "1970-01-01"), "%Y-%m-%d")
  tag_comment <- tag_row$COMMENT

  checks <- log[log$TAG == tag_id & !log$IS_TAG, ]
  checks_latest <- checks %>%
    dplyr::group_by(STAGE, NAME) %>%
    dplyr::slice_max(DATE_UNIX, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::arrange(dplyr::desc(DATE_UNIX))

  cat(sprintf("\n🏷️️  TAG: %s   📁 V%d   📅 %s\n\n", tag_id, tag_version, tag_date))
  cat("N°   STAGE       CHECKS     VERSION   DATE\n")
  cat("...................................................\n")

  for (i in seq_len(nrow(checks_latest))) {
    row <- checks_latest[i, ]
    fecha <- format(as.POSIXct(row$DATE_UNIX, origin = "1970-01-01"), "%Y-%m-%d")
    cat(sprintf("%-4d %-11s %-10s %-8d %s\n",
                i, row$STAGE, row$NAME, row$VERSION, fecha))
  }

  cat("\n💬 TAG & CHECK COMMENTS 💬\n\n")
  cat("N°   OBJ              COMMENT\n")
  cat("...........................................\n")
  cat(sprintf("%-4s %-16s %s\n", "🏷️️", "  TAG", ifelse(tag_comment != "", tag_comment, "(no comment)")))

  for (i in seq_len(nrow(checks_latest))) {
    row <- checks_latest[i, ]
    comment <- ifelse(row$COMMENT == "", "(no comment)", row$COMMENT)
    cat(sprintf("%-4d %-16s %s\n", i, row$NAME, comment))
  }

  invisible(checks_latest)
}

env_tags <- function(log, envir = .GlobalEnv) {

  log <- log[log$TAG != "" & !is.na(log$TAG), ]

  # Identificar objetos cargados
  env_objs <- ls(envir = envir)
  checkpoint_objs <- lapply(env_objs, function(obj_name) {
    obj <- get(obj_name, envir = envir)
    info <- attr(obj, "checkpoint_info")
    if (!is.null(info)) {
      data.frame(NAME = obj_name, STAGE = info$stage, VERSION = info$version, stringsAsFactors = FALSE)
    } else {
      NULL
    }
  })
  checkpoint_objs <- do.call(rbind, checkpoint_objs)

  if (is.null(checkpoint_objs) || nrow(checkpoint_objs) == 0) {
    cat("\n⚠️ No loaded checkpoints with metadata found.\n")
    return(invisible(NULL))
  }

  # Unir con log para obtener TAG
  tag_info <- merge(checkpoint_objs, log, by = c("NAME", "STAGE", "VERSION"))
  tag_info <- tag_info[!is.na(tag_info$TAG) & tag_info$TAG != "", ]

  if (nrow(tag_info) == 0) {
    cat("\n⚠️ No tags associated with currently loaded checkpoints.\n")
    return(invisible(NULL))
  }

  # Extraer info del tag con nombres únicos
  tag_versions <- log[log$IS_TAG, c("TAG", "VERSION", "DATE_UNIX")]
  names(tag_versions)[2:3] <- c("TAG_VERSION", "TAG_DATE")

  # Unir con la info de checkpoints cargados
  tag_data <- merge(tag_info, tag_versions, by = "TAG", all.x = TRUE)

  # Ordenar por fecha descendente
  tag_data <- tag_data %>%
    dplyr::arrange(dplyr::desc(TAG_DATE))

  # Agregar N
  tag_data$N <- seq_len(nrow(tag_data))

  # === TABLA PRINCIPAL ===
  cat("\n✅ TAGS OF LOADED CHECKPOINTS ✅\n\n")
  headers <- c("N", "CHECK", "🏷️️ TAG 🏷️️", "VERSION", "DATE")
  widths <- sapply(headers, function(h) {
    max(nchar(as.character(tag_data[[h]])), nchar(h))
  })
  widths["CHECK"] <- max(nchar("CHECK"), max(nchar(tag_data$NAME)))

  # Imprimir encabezado
  header_line <- mapply(format, headers, width = widths, MoreArgs = list(justify = "centre"))
  cat(paste(header_line, collapse = "   "), "\n")
  cat(paste(rep(".", sum(widths) + 3 * (length(widths) - 1)), collapse = ""), "\n")

  # Imprimir filas
  for (i in seq_len(nrow(tag_data))) {
    row <- tag_data[i, ]
    values <- c(
      format(row$N, width = widths["N"], justify = "right"),
      format(row$NAME, width = widths["CHECK"], justify = "left"),
      format(row$TAG, width = widths["🏷️️ TAG 🏷️️"], justify = "left"),
      format(row$TAG_VERSION, width = widths["VERSION"], justify = "right"),
      format(format(as.POSIXct(row$DATE, origin = "1970-01-01"), "%Y-%m-%d"), width = widths["DATE"], justify = "left")
    )
    cat(paste(values, collapse = "   "), "\n")
  }

  # === COMENTARIOS ===
  cat("\n💬 TAG COMMENTS 💬\n\n")
  comment_headers <- c("N", "COMMENT")
  comment_widths <- c(
    max(nchar(as.character(tag_data$N)), nchar("N")),
    max(nchar(as.character(tag_data$COMMENT)), nchar("COMMENT"))
  )
  cat(sprintf("%-*s   %-*s\n", comment_widths[1], "N", comment_widths[2], "COMMENT"))
  cat(paste(rep(".", sum(comment_widths) + 3), collapse = ""), "\n")
  for (i in seq_len(nrow(tag_data))) {
    cat(sprintf("%-*d   %-*s\n", comment_widths[1], tag_data$N[i], comment_widths[2], tag_data$COMMENT[i]))
  }

  invisible(tag_data)
}

hist_tag <- function(log, n = 5) {

  log <- log[log$TAG != "" & !is.na(log$TAG), ]

  tag_rows <- log[log$IS_TAG == TRUE, ]
  if (nrow(tag_rows) == 0) {
    cat("\n⚠️ No tags found in log.\n")
    return(invisible(NULL))
  }

  tag_rows <- tag_rows[order(-tag_rows$DATE_UNIX), ]
  tag_rows <- head(tag_rows, n)

  # Resumen por tag
  tag_summary <- lapply(tag_rows$TAG, function(tag) {
    checks <- log[log$TAG == tag & !log$IS_TAG, ]
    data.frame(
      TAG = tag,
      VERSION = tag_rows$VERSION[tag_rows$TAG == tag],
      STAGES = length(unique(checks$STAGE)),
      CHECKS = nrow(checks),
      DATE = format(as.POSIXct(tag_rows$DATE_UNIX[tag_rows$TAG == tag], origin = "1970-01-01"), "%Y-%m-%d"),
      COMMENT = tag_rows$COMMENT[tag_rows$TAG == tag],
      stringsAsFactors = FALSE
    )
  }) |> dplyr::bind_rows()

  # Mostrar tabla
  cat("\n🏷️ LAST CREATED TAGS (up to", n, ") 🏷️\n\n")
  headers <- c("N°", "TAG", "VERSION", "STAGES", "CHECKS", "DATE")
  widths <- sapply(headers, nchar)
  widths["TAG"] <- max(widths["TAG"], max(nchar(tag_summary$TAG)))
  widths["VERSION"] <- max(widths["VERSION"], max(nchar(as.character(tag_summary$VERSION))))
  widths["DATE"] <- max(widths["DATE"], max(nchar(tag_summary$DATE)))

  # Header
  header_line <- mapply(format, headers, width = widths, MoreArgs = list(justify = "centre"))
  cat(paste(header_line, collapse = "   "), "\n")
  cat(paste(rep(".", sum(widths) + 3 * (length(headers) - 1)), collapse = ""), "\n")

  for (i in seq_len(nrow(tag_summary))) {
    row <- tag_summary[i, ]
    line <- sprintf(
      "%*d   %-*s   %*d   %*d   %*d   %-*s",
      widths["N°"], i,
      widths["TAG"], row$TAG,
      widths["VERSION"], row$VERSION,
      widths["STAGES"], row$STAGES,
      widths["CHECKS"], row$CHECKS,
      widths["DATE"], row$DATE
    )
    cat(line, "\n")
  }

  # Comentarios
  cat("\n💬 TAG COMMENTS 💬\n\n")
  comment_headers <- c("N°", "COMMENT")
  comment_widths <- c(
    max(nchar(as.character(seq_len(nrow(tag_summary)))), nchar("N°")),
    max(nchar(as.character(tag_summary$COMMENT)), nchar("COMMENT"))
  )

  cat(sprintf("%-*s   %-*s\n", comment_widths[1], "N°", comment_widths[2], "COMMENT"))
  cat(paste(rep(".", sum(comment_widths) + 3), collapse = ""), "\n")

  for (i in seq_len(nrow(tag_summary))) {
    cat(sprintf("%-*d   %-*s\n", comment_widths[1], i, comment_widths[2], tag_summary$COMMENT[i]))
  }

  invisible(tag_summary)
}

search_tag <- function(log, stage) {

  log <- log[log$TAG != "" & !is.na(log$TAG), ]

  log_stage <- log[log$STAGE == stage & !log$IS_TAG, ]
  if (nrow(log_stage) == 0) {
    cat("\n⚠️ No checkpoints found for stage: ", stage, "\n")
    return(invisible(NULL))
  }

  latest <- log_stage[which.max(log_stage$DATE_UNIX), ]
  tag <- latest$TAG

  if (is.na(tag) || tag == "") {
    cat(sprintf("\n⚠️ Last version of stage '%s' is not tagged.\n", stage))
    return(invisible(NULL))
  }

  tag_row <- log[log$IS_TAG & log$TAG == tag, ]
  if (nrow(tag_row) == 0) {
    cat(sprintf("\n⚠️ Tag '%s' not found as a tag row in log.\n", tag))
    return(invisible(NULL))
  }

  # Buscar todos los checkpoints asociados a este tag
  checks <- log[log$TAG == tag & !log$IS_TAG, ]

  # Construir tabla
  result <- data.frame(
    TAG = tag,
    VERSION = tag_row$VERSION,
    STAGES = length(unique(checks$STAGE)),
    CHECKS = nrow(checks),
    DATE = format(as.POSIXct(tag_row$DATE_UNIX, origin = "1970-01-01"), "%Y-%m-%d"),
    COMMENT = tag_row$COMMENT,
    stringsAsFactors = FALSE
  )

  # Mostrar tabla
  cat(sprintf("\n🏷️️ TAG FOR STAGE '%s' 🏷️️\n\n", stage))
  headers <- c("TAG", "VERSION", "STAGES", "CHECKS", "DATE")
  widths <- sapply(headers, nchar)
  widths["TAG"] <- max(widths["TAG"], nchar(result$TAG))
  widths["DATE"] <- max(widths["DATE"], nchar(result$DATE))

  # Header
  header_line <- mapply(format, headers, width = widths, MoreArgs = list(justify = "centre"))
  cat(paste(header_line, collapse = "   "), "\n")
  cat(paste(rep(".", sum(widths) + 3 * (length(headers) - 1)), collapse = ""), "\n")

  line <- sprintf(
    "%-*s   %*d   %*d   %*d   %-*s",
    widths["TAG"], result$TAG,
    widths["VERSION"], result$VERSION,
    widths["STAGES"], result$STAGES,
    widths["CHECKS"], result$CHECKS,
    widths["DATE"], result$DATE
  )
  cat(line, "\n")

  # Comentario
  #cat("\n💬 TAG COMMENT 💬\n\n")
  #cat(sprintf("COMMENT: %s\n", result$COMMENT))

  invisible(result)
}

search_com <- function(log, stage) {

  log <- log[log$TAG != "" & !is.na(log$TAG), ]

  # Filtrar solo saves del stage
  log_stage <- log[log$STAGE == stage & !log$IS_TAG, ]

  if (nrow(log_stage) == 0) {
    cat("\n⚠️ No checkpoints found for stage '", stage, "'.\n", sep = "")
    return(invisible(NULL))
  }

  # Última versión
  last_version <- max(log_stage$VERSION)
  last_entry <- log_stage[log_stage$VERSION == last_version, ]
  tag_id <- last_entry$TAG[1]

  if (is.na(tag_id) || tag_id == "") {
    cat("\n⚠️ No tag found for latest checkpoint in stage '", stage, "'.\n", sep = "")
    return(invisible(NULL))
  }

  # Comentario del tag
  tag_row <- log[log$IS_TAG & log$TAG == tag_id, ]
  tag_comment <- tag_row$COMMENT[1]

  # Comentarios de checkpoints del mismo tag y stage
  checks <- log[!log$IS_TAG & log$TAG == tag_id & log$STAGE == stage, ]
  checks <- checks[order(-checks$DATE_UNIX), ]

  # Construir tabla de comentarios
  all_comments <- rbind(
    data.frame(N = "🏷️️", OBJ = "️️ TAG", COMMENT = tag_comment, stringsAsFactors = FALSE),
    data.frame(
      N = seq(nrow(checks)),
      OBJ = checks$NAME,
      COMMENT = ifelse(checks$COMMENT == "", "(no comment)", checks$COMMENT),
      stringsAsFactors = FALSE
    )
  )

  # Calcular anchos
  widths <- sapply(all_comments, function(col) max(nchar(as.character(col))))
  widths <- pmax(widths, nchar(c("N", "OBJ", "COMMENT")))
  names(widths) <- c("N", "OBJ", "COMMENT")  # <- ESTA LÍNEA ES CLAVE

  # Imprimir
  cat("\n💬 TAG & STAGE COMMENTS 💬\n\n")
  header_line <- mapply(format, c("N", "OBJ", "COMMENT"), width = widths, MoreArgs = list(justify = "centre"))
  cat(paste(header_line, collapse = "   "), "\n")
  cat(paste(rep(".", sum(widths) + 3 * (length(widths) - 1)), collapse = ""), "\n")

  for (i in 1:nrow(all_comments)) {
    line <- mapply(format, all_comments[i, ], width = widths, MoreArgs = list(justify = "left"))
    cat(paste(line, collapse = "   "), "\n")
  }

  invisible(all_comments)
}

#OVERVIEW

ov1 <- function(log, envir = .GlobalEnv) {

  if (nrow(log) == 0) {
    message("⚠️ No valid checkpoint records found with existing files.")
    return(NULL)
  }

  # === Mostrar último tag ===
  last_tag(log = log)

  # === Generar tabla resumen ===
  summary <- log %>%
    dplyr::filter(!IS_TAG) %>%
    dplyr::group_by(NAME, STAGE) %>%
    dplyr::summarise(
      VERSIONS = paste(sort(VERSION), collapse = ", "),
      DATE = format(as.POSIXct(max(DATE_UNIX), origin = "1970-01-01"), "%Y-%m-%d"),
      .groups = "drop"
    )

  # === Generar tabla de cargados ===
  env_objs <- ls(envir = envir)
  loaded <- lapply(env_objs, function(obj_name) {
    obj <- get(obj_name, envir = envir)
    info <- attr(obj, "checkpoint_info")
    if (!is.null(info)) {
      unix_time <- log %>%
        dplyr::filter(NAME == info$name, STAGE == info$stage, VERSION == info$version) %>%
        dplyr::pull(DATE_UNIX) %>%
        dplyr::first()

      tibble::tibble(
        NAME = info$name,
        STAGE = info$stage,
        VERSION = info$version,
        DATE = format(as.POSIXct(unix_time, origin = "1970-01-01"), "%Y-%m-%d")
      )
    } else {
      NULL
    }
  }) %>% dplyr::bind_rows()

  # === Estilo tabla ===
  print_table <- function(df, title, is_summary = FALSE) {
    if (nrow(df) == 0) {
      cat("\n", title, "\n\n")
      headers <- c("NAME", "STAGE", if (is_summary) "VERSIONS" else "VERSION", "DATE")
      header_line <- paste(format(headers, justify = "centre"), collapse = "   ")
      separator <- paste(rep(".", nchar(header_line)), collapse = "")
      cat(header_line, "\n")
      cat(separator, "\n")
      cat("(empty)\n")
      return()
    }

    name <- as.character(df$NAME)
    stage <- as.character(df$STAGE)
    date <- as.character(df$DATE)

    versions <- if (is_summary) {
      as.character(df$VERSIONS)
    } else {
      as.character(df$VERSION)
    }

    w_name <- max(nchar(name))
    w_stage <- max(nchar(stage))
    w_version <- max(nchar(versions))
    w_date <- max(nchar(date))

    headers <- c("NAME", "STAGE", if (is_summary) "VERSIONS" else "VERSION", "DATE")
    widths <- c(w_name, w_stage, w_version, w_date)
    formatted_headers <- mapply(format, headers, width = widths, MoreArgs = list(justify = "centre"))
    separator <- paste(rep(".", sum(widths) + 3 * (length(widths) - 1)), collapse = "")

    body <- mapply(format, list(name, stage, versions, date), width = widths, SIMPLIFY = FALSE)
    body_lines <- do.call(mapply, c(FUN = paste, body, MoreArgs = list(sep = "   ")))

    cat("\n", title, "\n\n")
    cat(paste(formatted_headers, collapse = "   "), "\n")
    cat(separator, "\n")
    cat(paste(body_lines, collapse = "\n"), "\n")
  }

  print_table(summary, "\n✅ AVAILABLE CHECKPOINTS ✅", is_summary = TRUE)
  print_table(loaded, "\n✅ LOADED CHECKPOINTS ✅", is_summary = FALSE)

  invisible(list(
    available_versions = summary,
    loaded_bases = loaded
  ))
}

ov2 <- function(log, stage) {

  # Filtrar solo saves del stage
  log_stage <- log[log$STAGE == stage & !log$IS_TAG, ]

  if (nrow(log_stage) == 0) {
    cat("\n⚠️ No checkpoints found for stage '", stage, "'.\n", sep = "")
    return(invisible(NULL))
  }

  # ============================
  # 1. Mostrar tag asociado
  # ============================
search_tag(log = log, stage = stage)

  # ============================
  # 2. Tabla principal de versiones
  # ============================
  log_stage <- log_stage[order(-log_stage$VERSION), ]
  df_main <- data.frame(
    N = seq_len(nrow(log_stage)),
    NAME = log_stage$NAME,
    VERSIONS = log_stage$VERSION,
    DATE = format(as.POSIXct(log_stage$DATE_UNIX, origin = "1970-01-01"), "%Y-%m-%d %H:%M:%S"),
    stringsAsFactors = FALSE
  )

  cat(sprintf("\n✅ CHECKPOINT STAGE %s ✅\n\n", stage))

  widths <- sapply(df_main, function(col) max(nchar(as.character(col))))
  widths <- pmax(widths, nchar(names(df_main)))

  # Header
  header_line <- mapply(format, names(df_main), width = widths, MoreArgs = list(justify = "centre"))
  cat(paste(header_line, collapse = "   "), "\n")
  cat(paste(rep(".", sum(widths) + 3 * (length(widths) - 1)), collapse = ""), "\n")

  # Filas
  for (i in seq_len(nrow(df_main))) {
    line <- mapply(format, df_main[i, ], width = widths, MoreArgs = list(justify = "left"))
    cat(paste(line, collapse = "   "), "\n")
  }

  # ============================
  # 3. Comentarios unificados
  # ============================
  search_com(log = log, stage = stage)

  invisible(list(
    versions_table = df_main
  ))
}

ov3 <- function(log, envir = .GlobalEnv) {

  # 1. Mostrar último tag
  cat("\n\n=== ✅ 1. LAST TAG CREATED ✅ ===\n\n")
  last_tag(log = log)

  # 2. Mostrar tags asociados a objetos cargados
  cat("\n\n=== ✅ 2. TAGS OF LOADED OBJECTS ✅ ===\n\n")
  env_tags(log = log, envir = envir)

  # 3. Historial de los últimos 5 tags
  cat("\n\n=== ✅ 3. TAGS HISTORY (Last 5) ✅ ===\n\n")
  hist_tag(log = log)

  invisible(NULL)
}

# ---- ATTR AUXILIARES----

get_log_row <- function(info, log) {
  id <- if (!is.null(info$ID)) info$ID else generate_id(info$stage, info$name, info$version)
  row <- log[log$ID == id & !log$IS_TAG, ]
  if (nrow(row) == 0) return(NULL)
  return(row[1, ])
}

get_file_date <- function(stage, name, version) {
  folder <- file.path("4_checkpoint", stage)
  file_path <- file.path(folder, sprintf("%s_%s_v%d.rds", stage, name, version))
  if (file.exists(file_path)) {
    return(format(file.info(file_path)$ctime, "%Y-%m-%d %H:%M:%S"))
  } else {
    return("Date not available")
  }
}

get_tag_comment <- function(info, log) {
  row <- get_log_row(info, log)
  tag <- if (!is.null(row)) row$TAG else NA

  if (is.na(tag) || tag == "") return("(no tag comment)")

  tag_row <- log[log$IS_TAG & log$TAG == tag, ]
  if (nrow(tag_row) == 0) return("(no tag comment)")

  comment <- tag_row$COMMENT[1]
  ifelse(is.na(comment) || comment == "", "(no tag comment)", comment)
}

build_attr_row <- function(name, info, log) {
  log_row <- get_log_row(info, log)
  comment <- if (!is.null(log_row)) {
    ifelse(is.na(log_row$COMMENT) || log_row$COMMENT == "", "(no comment)", log_row$COMMENT)
  } else {
    "(no comment)"
  }

  tag_comment <- get_tag_comment(info, log)
  full_comment <- paste0(comment, " | TAG: ", tag_comment)

  list(
    NAME = name,
    STAGE = info$stage,
    VERSION = info$version,
    DATE = get_file_date(info$stage, info$name, info$version),
    COMMENT = full_comment
  )
}

attr1 <- function(log, envir = .GlobalEnv) {
  env_objs <- ls(envir = envir)
  rows <- list()

  for (obj_name in env_objs) {
    obj <- get(obj_name, envir = envir)
    info <- attr(obj, "checkpoint_info")

    if (!is.null(info)) {
      log_row <- get_log_row(info, log)
      date <- get_file_date(info$stage, info$name, info$version)
      tag_comment <- get_tag_comment(info, log)

      row <- build_attr_row(info$name, info$stage, info$version, date, log_row$COMMENT, tag_comment)
      rows[[length(rows) + 1]] <- row
    }
  }

  if (length(rows) == 0) {
    cat("\n❌ No loaded objects with checkpoint information found.\n")
    return(invisible(NULL))
  }

  df <- do.call(rbind.data.frame, rows)
  names(df) <- c("NAME", "STAGE", "VERSION", "DATE", "COMMENT", "TAG_COMMENT")

  # === Imprimir tabla ===
  cat("\n✅ ATTRIBUTES FOR LOADED OBJECTS ✅\n\n")
  headers <- c("NAME", "STAGE", "VERSION", "DATE")
  widths <- sapply(df[headers], function(col) max(nchar(as.character(col))))
  headers_fmt <- mapply(format, headers, width = widths, MoreArgs = list(justify = "centre"))
  separator <- paste(rep(".", sum(widths) + 3 * (length(headers) - 1)), collapse = "")
  cat(paste(headers_fmt, collapse = "   "), "\n")
  cat(separator, "\n")

  for (i in seq_len(nrow(df))) {
    row <- sapply(seq_along(headers), function(j) {
      format(df[i, headers[j]], width = widths[j], justify = "left")
    })
    cat(paste(row, collapse = "   "), "\n")
  }

  # === Comentarios ===
  cat("\nCOMMENTS:\n")
  for (i in seq_len(nrow(df))) {
    cat(sprintf("%s v%d: %s | 🏷️ %s\n",
                df$NAME[i],
                df$VERSION[i],
                df$COMMENT[i],
                ifelse(is.na(df$TAG_COMMENT[i]) || df$TAG_COMMENT[i] == "", "(no tag comment)", df$TAG_COMMENT[i])
    ))
  }

  invisible(df)
}

