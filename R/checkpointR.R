#' @import dplyr
#' @import openxlsx
#' @import tibble
NULL

#' Save a checkpoint of an R object with versioning and styled logging
#'
#' Saves an R object to a versioned .rds file and logs the event in a formatted Excel sheet.
#'
#' @param stage Character. Required. Stage of the project.
#' @param obj The R object to save. Defaults to `procdata`.
#' @param name Character. Optional. Name of the object to save. If NULL, uses the variable name.
#' @param comment Character. Optional. A comment to include in the log.
#'
#' @return Invisibly returns NULL. Side effect: saves an RDS file and updates Excel log.
#' @export
#' Save a checkpoint of an R object with versioning and logging
#'
#' Saves an object to a specified stage folder with version control and logs the save event in an Excel file.
#'
#' @param stage Character. Required. Stage name to categorize the checkpoint.
#' @param obj The R object to save. Default is `procdata`.
#' @param name Character. Optional. Name of the object to save. Default is derived from the object.
#' @param comment Optional character. Additional comment to record with the checkpoint.
#'
#' @return Invisible NULL. Side effect: saves an .rds file and updates the log.
#' @export
check_save <- function(stage, obj = procdata, name = NULL, comment = NULL) {
  if (missing(stage) || stage == "") stop("❌ You must specify a valid 'stage' as a non-empty string.")
  if (is.null(name)) name <- deparse(substitute(obj))

  base_folder <- "4_checkpoint"
  if (!dir.exists(base_folder)) dir.create(base_folder)

  stage_folder <- file.path(base_folder, stage)
  if (!dir.exists(stage_folder)) dir.create(stage_folder)

  log_path <- file.path(base_folder, "log.xlsx")

  if (file.exists(log_path)) {
    log <- openxlsx::read.xlsx(log_path)
  } else {
    log <- data.frame(
      STAGE = character(),
      NAME = character(),
      VERSION = numeric(),
      DATE = character(),
      COMMENT = character(),
      FILE = character(),
      DATE_UNIX = numeric(),
      stringsAsFactors = FALSE
    )
  }

  subset_versions <- log[log$STAGE == stage & log$NAME == name, ]
  version <- if (nrow(subset_versions) == 0) 1 else max(subset_versions$VERSION) + 1

  file_name <- sprintf("%s_%s_v%d.rds", stage, name, version)
  save_path <- file.path(stage_folder, file_name)
  saveRDS(obj, save_path)

  attr(obj, "checkpoint_info") <- list(name = name, stage = stage, version = version)
  attr(obj, "comment") <- ifelse(is.null(comment), "", comment)

  now <- Sys.time()
  new_log <- data.frame(
    STAGE = stage,
    NAME = name,
    VERSION = version,
    DATE = format(now, "%Y-%m-%d %H:%M:%S"),
    COMMENT = ifelse(is.null(comment), "", comment),
    FILE = file.path(stage, file_name),
    DATE_UNIX = as.numeric(now),
    stringsAsFactors = FALSE
  )

  log <- rbind(log, new_log)

  # Ordering logic
  log <- log |>
    dplyr::group_by(STAGE) |>
    dplyr::mutate(STAGE_LATEST = max(DATE_UNIX)) |>
    dplyr::ungroup() |>
    dplyr::group_by(STAGE, NAME) |>
    dplyr::mutate(NAME_LATEST = max(DATE_UNIX)) |>
    dplyr::ungroup() |>
    dplyr::mutate(NAME_PRIORITY = ifelse(NAME == "procdata", 0, 1)) |>
    dplyr::arrange(
      dplyr::desc(STAGE_LATEST),
      NAME_PRIORITY,
      dplyr::desc(NAME_LATEST),
      dplyr::desc(DATE_UNIX)
    ) |>
    dplyr::select(-STAGE_LATEST, -NAME_LATEST, -NAME_PRIORITY)

  # Excel output
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "log")

  header_style <- openxlsx::createStyle(textDecoration = "bold", fgFill = "#DCE6F1")
  openxlsx::writeData(wb, "log", log, headerStyle = header_style)

  center_style <- openxlsx::createStyle(halign = "center")
  nowrap_style <- openxlsx::createStyle(wrapText = FALSE)
  border_header <- openxlsx::createStyle(border = "bottom", borderColour = "black")
  border_stage <- openxlsx::createStyle(border = "bottom", borderColour = "black")

  openxlsx::addStyle(wb, "log", center_style, cols = 3, rows = 2:(nrow(log) + 1), gridExpand = TRUE)
  openxlsx::addStyle(wb, "log", center_style, cols = 4, rows = 2:(nrow(log) + 1), gridExpand = TRUE)
  openxlsx::addStyle(wb, "log", nowrap_style, cols = 6, rows = 2:(nrow(log) + 1), gridExpand = TRUE)
  openxlsx::addStyle(wb, "log", border_header, rows = 1, cols = 1:6, gridExpand = TRUE)

  stage_vector <- log$STAGE
  unique_stages <- unique(stage_vector)
  gray <- "#F2F2F2"
  white <- "#FFFFFF"

  for (i in seq_along(unique_stages)) {
    rows <- which(stage_vector == unique_stages[i]) + 1
    fill_color <- if ((i %% 2) == 1) white else gray
    fill_style <- openxlsx::createStyle(fgFill = fill_color)
    openxlsx::addStyle(wb, "log", style = fill_style, cols = 1:6, rows = rows, gridExpand = TRUE)

    last_row <- max(rows)
    openxlsx::addStyle(wb, "log", style = border_stage, rows = last_row, cols = 1:6, gridExpand = TRUE, stack = TRUE)
  }

  openxlsx::setColWidths(wb, "log", cols = 1:5, widths = "auto")
  openxlsx::setColWidths(wb, "log", cols = 3, widths = 10)
  openxlsx::setColWidths(wb, "log", cols = 6, widths = 25)
  openxlsx::setColWidths(wb, "log", cols = 7, widths = 0, hidden = TRUE)

  openxlsx::saveWorkbook(wb, log_path, overwrite = TRUE)
  message(sprintf("🏷️  Checkpoint saved: [%s] %s v%d → %s", stage, name, version, file.path(stage, file_name)))
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

  stage_folder <- file.path(folder, stage)
  log_path <- file.path(folder, "log.xlsx")

  if (!file.exists(log_path)) {
    stop("❌ Log file not found in ", folder)
  }

  log <- openxlsx::read.xlsx(log_path)
  filtered_log <- log[log$STAGE == stage & log$NAME == name, ]

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
  log_path <- file.path("4_checkpoint", "log.xlsx")

  if (!file.exists(log_path)) {
    stop("❌ Checkpoint log file does not exist.")
  }

  log <- openxlsx::read.xlsx(log_path)

  log <- log %>% dplyr::filter(file.exists(file.path("4_checkpoint", FILE)))

  if (nrow(log) == 0) {
    message("⚠️ No valid checkpoint records found with existing files.")
    return(NULL)
  }

  if (!is.null(stage)) {
    log <- log %>% dplyr::filter(STAGE %in% stage)

    if (nrow(log) == 0) {
      message("⚠️ No checkpoints found for the specified stage.")
      return(NULL)
    }

    # Tabla larga por versión
    version_table <- log %>%
      dplyr::arrange(dplyr::desc(VERSION)) %>%
      dplyr::transmute(
        VERSIONS = VERSION,
        NAME,
        DATE = format(as.POSIXct(DATE_UNIX, origin = "1970-01-01"), "%Y-%m-%d %H:%M:%S")
      )

    comment_table <- log %>%
      dplyr::arrange(dplyr::desc(VERSION)) %>%
      dplyr::transmute(
        VERSIONS = VERSION,
        COMMENT = ifelse(is.na(COMMENT) | COMMENT == "", "(no comment)", COMMENT)
      )

    print_table_clean <- function(df, title, rename_versions = FALSE) {
      message(title)

      df <- as.data.frame(df)
      if (rename_versions) names(df)[1] <- "VERSION"

      headers <- names(df)
      col_widths <- sapply(df, function(col) max(nchar(as.character(col)), na.rm = TRUE))
      col_widths <- pmax(col_widths, nchar(headers))
      formatted_headers <- mapply(format, headers, width = col_widths, MoreArgs = list(justify = "centre"))
      separator <- paste(rep(".", sum(col_widths) + 3 * (ncol(df) - 1)), collapse = "")
      cat(paste(formatted_headers, collapse = "   "), "\n")
      cat(separator, "\n")

      for (i in seq_len(nrow(df))) {
        row <- sapply(seq_along(df), function(j) {
          val <- as.character(df[i, j])
          justify <- if (j == 1) "centre" else "left"
          format(val, width = col_widths[j], justify = justify)
        })
        cat(paste(row, collapse = "   "), "\n")
      }
    }

    version_title <- sprintf("\n✅ CHECKPOINT VERSIONS STAGE: %s ✅\n", unique(log$STAGE))
    print_table_clean(version_table, version_title)
    print_table_clean(comment_table, "\n💬 COMMENTS ASSOCIATED 💬\n", rename_versions = TRUE)

    invisible(list(
      versions_long = version_table,
      comments = comment_table
    ))
  } else {
    # Tabla resumida
    summary <- log %>%
      dplyr::group_by(NAME, STAGE) %>%
      dplyr::summarise(
        VERSIONS = paste(sort(VERSION), collapse = ", "),
        DATE = format(as.POSIXct(max(DATE_UNIX), origin = "1970-01-01"), "%Y-%m-%d"),
        .groups = "drop"
      )

    # Objetos cargados
    env_objs <- ls(envir = envir)
    loaded <- lapply(env_objs, function(obj_name) {
      obj <- get(obj_name, envir = envir)
      info <- attr(obj, "checkpoint_info")
      if (!is.null(info)) {
        unix_time <- log %>%
          dplyr::filter(NAME == obj_name, STAGE == info$stage, VERSION == info$version) %>%
          dplyr::pull(DATE_UNIX) %>%
          dplyr::first()

        tibble::tibble(
          NAME = obj_name,
          STAGE = info$stage,
          VERSION = info$version,
          DATE = format(as.POSIXct(unix_time, origin = "1970-01-01"), "%Y-%m-%d")
        )
      } else {
        NULL
      }
    }) %>% dplyr::bind_rows()

    # Ordenar con procdata primero
    sort_table <- function(df) {
      df %>%
        dplyr::mutate(NAME = factor(NAME, levels = c("procdata", sort(setdiff(unique(NAME), "procdata"))))) %>%
        dplyr::arrange(NAME, STAGE, dplyr::desc(if ("VERSIONS" %in% colnames(df)) VERSIONS else VERSION))
    }

    format_table <- function(df, title, is_summary = FALSE) {
      if (nrow(df) == 0) {
        cat("\n", title, "\n\n")
        headers <- c("NAME", "STAGE", if (is_summary) "VERSIONS" else "VERSION", "DATE")
        header_line <- paste(format(headers, justify = "centre"), collapse = "   ")
        separator <- paste(rep(".", nchar(header_line)), collapse = "")
        cat(header_line, "\n")
        cat(separator, "\n")
        cat("(empty)\n")
        return(invisible(NULL))
      }

      df <- as.data.frame(df)
      name_chr <- as.character(df$NAME)
      stage_chr <- as.character(df$STAGE)
      date_chr <- as.character(df$DATE)

      name <- format(name_chr, width = max(nchar(name_chr)), justify = "left")
      stage <- format(stage_chr, width = max(nchar(stage_chr)), justify = "left")

      if (is_summary) {
        versions_chr <- as.character(df$VERSIONS)
        versions <- format(versions_chr, width = max(nchar(versions_chr)), justify = "centre")
      } else {
        version_chr <- as.character(df$VERSION)
        versions <- format(version_chr, width = max(nchar(version_chr)), justify = "centre")
      }

      date <- format(date_chr, width = max(nchar(date_chr)), justify = "centre")

      # Anchura por columna para encabezado
      widths <- c(
        max(nchar(name_chr)),
        max(nchar(stage_chr)),
        if (is_summary) max(nchar(versions_chr)) else max(nchar(version_chr)),
        max(nchar(date_chr))
      )

      headers <- c("NAME", "STAGE", if (is_summary) "VERSIONS" else "VERSION", "DATE")
      headers_fmt <- mapply(format, headers, width = widths, MoreArgs = list(justify = "centre"))
      separator <- paste(rep(".", sum(widths) + 3 * (length(headers) - 1)), collapse = "")
      body <- paste(name, stage, versions, date, sep = "   ")

      # Mostrar tabla
      cat("\n", title, "\n\n")
      cat(paste(headers_fmt, collapse = "   "), "\n")
      cat(separator, "\n")
      cat(paste(body, collapse = "\n"), "\n")
    }

    format_table(sort_table(summary), title = "\n✅ AVAILABLE CHECKPOINTS ✅", is_summary = TRUE)
    format_table(sort_table(loaded), title = "\n✅ LOADED CHECKPOINTS ✅", is_summary = FALSE)

    invisible(list(
      available_versions = sort_table(summary),
      loaded_bases = sort_table(loaded)
    ))
  }
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
    check_load(stage = stage, name = obj, version = version, quiet = TRUE)
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

#' Add a new checkpoint tag with comment
#'
#' \code{check_tag} adds a new comment tag for a given project stage.
#' The tag includes an automatically assigned version, timestamp, and optional description.
#'
#' If the file \code{4_checkpoint/tags_log.xlsx} does not exist, it is created automatically.
#'
#' @param stage Character. The project stage (required).
#' @param comment Character. Optional comment describing the stage or changes.
#'
#' @return Invisibly returns the new tag as a data.frame.
#' @export
#'
#' @examples
#' \dontrun{
#' check_tag("data_cleaning", "Removed NA values and filtered rows")
#' }
#' Add a new checkpoint tag with comment
#'
#' @param stage Character. The project stage (required).
#' @param comment Character. Optional comment describing the stage or changes.
#'
#' @return Invisibly returns the new tag as a data.frame.
#' @export
#'
#' @examples
#' \dontrun{
#' check_tag("data_cleaning", "Removed NA values and filtered rows")
#' }
#' Add a new checkpoint tag with comment
#'
#' @param stage Character. The project stage (required).
#' @param comment Character. Optional comment describing the stage or changes.
#'
#' @return Invisibly returns the new tag as a data.frame.
#' @export
#'
#' @examples
#' \dontrun{
#' check_tag("data_cleaning", "Removed NA values and filtered rows")
#' }
check_tag <- function(stage, comment = "") {
  if (missing(stage) || !is.character(stage) || length(stage) != 1) {
    stop("You must provide a single 'stage' string.")
  }

  folder <- "4_checkpoint"
  if (!dir.exists(folder)) dir.create(folder)

  file_path <- file.path(folder, "tags_log.xlsx")

  if (file.exists(file_path)) {
    tags_log <- openxlsx::read.xlsx(file_path)
  } else {
    tags_log <- data.frame(
      STAGE = character(),
      VERSION = integer(),
      DATE = character(),
      COMMENT = character(),
      DATE_UNIX = numeric(),
      stringsAsFactors = FALSE
    )
  }

  existing_versions <- tags_log$VERSION[tags_log$STAGE == stage]
  next_version <- if (length(existing_versions) == 0) 1 else max(existing_versions, na.rm = TRUE) + 1

  now <- Sys.time()
  now_unix <- as.numeric(now)

  new_row <- data.frame(
    STAGE = stage,
    VERSION = next_version,
    DATE = format(now, "%Y-%m-%d %H:%M:%S"),
    COMMENT = comment,
    DATE_UNIX = now_unix,
    stringsAsFactors = FALSE
  )

  tags_log <- rbind(tags_log, new_row)
  tags_log <- tags_log[order(tags_log$DATE_UNIX, decreasing = TRUE), ]

  # === FORMATO DE EXCEL ===
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Tags")

  # Escribir datos
  header_style <- openxlsx::createStyle(textDecoration = "bold", fgFill = "#DCE6F1")  # Azul pastel
  openxlsx::writeData(wb, sheet = 1, x = tags_log, headerStyle = header_style)
  # Línea negra fina debajo de la fila de encabezado
  header_border <- openxlsx::createStyle(border = "bottom", borderColour = "black")
  openxlsx::addStyle(wb, sheet = 1, style = header_border, rows = 1, cols = 1:4, gridExpand = TRUE, stack = TRUE)

  # Estilo centrado
  center_style <- openxlsx::createStyle(halign = "center")
  openxlsx::addStyle(wb, 1, center_style, cols = 2, rows = 2:(nrow(tags_log) + 1), gridExpand = TRUE)
  openxlsx::addStyle(wb, 1, center_style, cols = 3, rows = 2:(nrow(tags_log) + 1), gridExpand = TRUE)

  # Colores alternos por STAGE (blanco y gris claro)
  unique_stages <- unique(tags_log$STAGE)
  row_offset <- 1
  for (i in seq_along(unique_stages)) {
    rows <- which(tags_log$STAGE == unique_stages[i]) + 1  # +1 por encabezado
    fill_color <- if ((i %% 2) == 1) "#FFFFFF" else "#F2F2F2"
    style <- openxlsx::createStyle(fgFill = fill_color)
    openxlsx::addStyle(wb, 1, style, cols = 1:4, rows = rows, gridExpand = TRUE)

    # Línea negra fina abajo del grupo
    last_row <- max(rows)
    border_style <- openxlsx::createStyle(border = "bottom", borderColour = "black")
    openxlsx::addStyle(wb, 1, border_style, cols = 1:4, rows = last_row, gridExpand = TRUE, stack = TRUE)
  }

  # Ancho columnas 1 a 4 automático
  openxlsx::setColWidths(wb, 1, cols = 1:4, widths = "auto")

  openxlsx::setColWidths(wb, sheet = 1, cols = 5, widths = 0, hidden = TRUE)

  # Guardar archivo
  openxlsx::saveWorkbook(wb, file = file_path, overwrite = TRUE)

  message("✅ Tag saved successfully.")
  invisible(new_row)
}




#' Manage and Display Checkpoint Tags
#'
#' \code{check_tags} retrieves and displays information from checkpoint tags stored in an Excel log.
#'
#' If no \code{tags_log.xlsx} exists, it will create an empty log file.
#'
#' @param stage Optional. A character string specifying the project stage to filter tags.
#' Use \code{"stages"} to list all stages with their latest tag.
#' @param version Optional. An integer specifying a version number for a given stage.
#'
#' @return Invisibly returns NULL. Outputs tag information to the console.
#'
#' @details
#' - If called with no arguments, shows the most recent tag overall.
#' - If called with \code{stage} only, shows all tags for that stage ordered newest to oldest.
#' - If called with \code{stage = "stages"}, shows all stages with their latest tag summary.
#' - If called with \code{stage} and \code{version}, shows the specific tag for that stage.
#'
#' The tags log file is saved as \code{"4_checkpoint/tags_log.xlsx"}.
#'
#' @examples
#' \dontrun{
#' check_tags()                               # Show last tag overall
#' check_tags(stage = "data_clean")          # Show all tags for 'data_clean' stage
#' check_tags(stage = "data_clean", version = 2)  # Show tag version 2
#' check_tags(stage = "stages")              # Show summary of all stages
#' }
#' @export
#' Manage and Display Checkpoint Tags
#'
#' \code{check_tags} retrieves and displays information from checkpoint tags stored in an Excel log.
#'
#' If no \code{tags_log.xlsx} exists, it will create an empty log file.
#'
#' @param stage Optional. A character string specifying the project stage to filter tags.
#' Use \code{"stages"} to list all stages with their latest tag.
#' @param version Optional. An integer specifying a version number for a given stage.
#'
#' @return Invisibly returns NULL. Outputs tag information to the console.
#'
#' @details
#' - If called with no arguments, shows the most recent tag overall.
#' - If called with \code{stage} only, shows all tags for that stage ordered newest to oldest.
#' - If called with \code{stage = "stages"}, shows all stages with their latest tag summary.
#' - If called with \code{stage} and \code{version}, shows the specific tag for that stage.
#'
#' The tags log file is saved as \code{"4_checkpoint/tags_log.xlsx"}.
#'
#' @examples
#' \dontrun{
#' check_tags()                               # Show last tag overall
#' check_tags(stage = "data_clean")          # Show all tags for 'data_clean' stage
#' check_tags(stage = "data_clean", version = 2)  # Show tag version 2
#' check_tags(stage = "stages")              # Show summary of all stages
#' }
#' @export
#' Manage and Display Checkpoint Tags
#'
#' \code{check_tags} retrieves and displays information from checkpoint tags stored in an Excel log.
#'
#' If no \code{tags_log.xlsx} exists, it will create an empty log file.
#'
#' @param stage Optional. A character string specifying the project stage to filter tags.
#' Use \code{"stages"} to list all stages with their latest tag.
#' @param version Optional. An integer specifying a version number for a given stage.
#'
#' @return Invisibly returns NULL. Outputs tag information to the console.
#'
#' @details
#' - If called with no arguments, shows the most recent tag overall.
#' - If called with \code{stage} only, shows all tags for that stage ordered newest to oldest.
#' - If called with \code{stage = "stages"}, shows all stages with their latest tag summary.
#' - If called with \code{stage} and \code{version}, shows the specific tag for that stage.
#'
#' The tags log file is saved as \code{"4_checkpoint/tags_log.xlsx"}.
#'
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
    message("No tags found in tags_log.xlsx.")
    return(invisible(NULL))
  }

  # Convertir DATE_UNIX a formato POSIXct y guardarlo como 'date'
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
    cat(sprintf("%-15s | %-7s | %-12s\n", "Stage", "Version", "Last Comment Date"))
    cat("-------------------------------------------\n")
    for (i in seq_len(nrow(summary_df))) {
      cat(sprintf("%-15s | v%-6d | %-12s\n",
                  summary_df$STAGE[i], summary_df$VERSION[i], summary_df$date_short[i]))
    }
    return(invisible(NULL))
  }

  # === 2. SPECIFIC TAG ===
  if (!is.null(stage) && !is.null(version)) {
    tag_row <- tags[tags$STAGE == stage & tags$VERSION == version, ]
    if (nrow(tag_row) == 0) {
      message(sprintf("No tag found for stage '%s' with version %d.", stage, version))
      return(invisible(NULL))
    }
    cat(sprintf("\n✅ TAG FOR STAGE: %s | VERSION v%d ✅\n\n", toupper(stage), version))
    cat("Version | Date and Time\n")
    cat("------------------------\n")
    cat(sprintf("v%d      | %s\n\n", tag_row$VERSION, format(tag_row$date, "%Y-%m-%d %H:%M:%S")))
    cat("Comment:\n")
    cat(sprintf("%s\n", tag_row$COMMENT))
    return(invisible(NULL))
  }

  # === 3. ALL TAGS FOR A STAGE ===
  if (!is.null(stage)) {
    stage_tags <- tags[tags$STAGE == stage, ]
    if (nrow(stage_tags) == 0) {
      message(sprintf("No tags found for stage '%s'.", stage))
      return(invisible(NULL))
    }

    stage_tags <- stage_tags[order(stage_tags$date, decreasing = TRUE), ]
    cat(sprintf("\n✅ TAGS FOR STAGE: %s ✅\n\n", toupper(stage)))
    cat("Version | Date and Time\n")
    cat("------------------------\n")
    for (i in seq_len(nrow(stage_tags))) {
      cat(sprintf("v%d      | %s\n", stage_tags$VERSION[i], format(stage_tags$date[i], "%Y-%m-%d %H:%M:%S")))
    }
    cat("\nComments:\n")
    for (i in seq_len(nrow(stage_tags))) {
      cat(sprintf("v%d: %s\n", stage_tags$VERSION[i], stage_tags$COMMENT[i]))
    }
    return(invisible(NULL))
  }

  # === 4. LAST TAG OVERALL ===
  last_tag <- tags[which.max(tags$date), ]
  cat("\n✅ LAST TAG ✅\n\n")
  cat(sprintf("Stage     | Version | Date\n"))
  cat(sprintf("-----------------------------\n"))
  cat(sprintf("%-9s | v%-6d | %s\n\n",
              last_tag$STAGE,
              last_tag$VERSION,
              format(last_tag$date, "%Y-%m-%d")))
  cat(last_tag$COMMENT, "\n")
  return(invisible(NULL))
}

