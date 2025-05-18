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
check_save <- function(obj = procdata, name = NULL, stage, comment = NULL) {
  args <- normalize_args(stage = stage, name = name, comment = comment, obj = obj)

  folder <- "4_checkpoint"
  if (!dir.exists(folder)) dir.create(folder)

  log_path <- file.path(folder, "log.xlsx")

  if (file.exists(log_path)) {
    log_df <- openxlsx::read.xlsx(log_path)
    # Asegurar columnas obligatorias en orden correcto
    if (!"TAG" %in% names(log_df)) log_df$TAG <- ""
    if (!"IS_TAG" %in% names(log_df)) log_df$IS_TAG <- FALSE
    if (!"ID" %in% names(log_df)) log_df$ID <- mapply(generate_id, log_df$STAGE, log_df$NAME, log_df$VERSION)
    log_df <- log_df[, c("TAG", "STAGE", "NAME", "VERSION", "DATE", "COMMENT", "ID", "FILE", "DATE_UNIX", "IS_TAG")]
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

  # === FORMATO EXCEL ===
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "log")

  header_style <- openxlsx::createStyle(textDecoration = "bold", halign = "center", fgFill = "#DCE6F1")
  openxlsx::writeData(wb, "log", log_df, headerStyle = header_style)

  border_style <- openxlsx::createStyle(border = "bottom", borderColour = "black")
  openxlsx::addStyle(wb, "log", style = border_style, rows = 1, cols = 1:ncol(log_df), gridExpand = TRUE)

  gray <- "#F2F2F2"
  white <- "#FFFFFF"
  unique_stages <- unique(log_df$STAGE)
  for (i in seq_along(unique_stages)) {
    rows <- which(log_df$STAGE == unique_stages[i]) + 1
    fill_color <- if ((i %% 2) == 1) white else gray
    fill_style <- openxlsx::createStyle(fgFill = fill_color)
    openxlsx::addStyle(wb, "log", style = fill_style, rows = rows, cols = 1:ncol(log_df), gridExpand = TRUE)

    last_row <- max(rows)
    openxlsx::addStyle(wb, "log", style = border_style, rows = last_row, cols = 1:ncol(log_df), gridExpand = TRUE, stack = TRUE)
  }

  # Alineación y ancho
  center_style <- openxlsx::createStyle(halign = "center")
  nowrap_style <- openxlsx::createStyle(wrapText = FALSE)
  openxlsx::addStyle(wb, "log", center_style, cols = which(names(log_df) %in% c("VERSION", "DATE")), rows = 2:(nrow(log_df)+1), gridExpand = TRUE)
  openxlsx::addStyle(wb, "log", nowrap_style, cols = which(names(log_df) == "FILE"), rows = 2:(nrow(log_df)+1), gridExpand = TRUE)

  # Anchos automáticos y ajustes especiales
  visible_cols <- setdiff(names(log_df), c("DATE_UNIX", "IS_TAG"))
  for (col in visible_cols) {
    idx <- which(names(log_df) == col)
    width <- if (col == "FILE") max(nchar("FILE")) else "auto"
    openxlsx::setColWidths(wb, "log", cols = idx, widths = width)
  }

  # Ocultar columnas DATE_UNIX e IS_TAG
  for (col in c("DATE_UNIX", "IS_TAG")) {
    idx <- which(names(log_df) == col)
    openxlsx::setColWidths(wb, "log", cols = idx, widths = 0, hidden = TRUE)
  }

  openxlsx::saveWorkbook(wb, log_path, overwrite = TRUE)

  message(sprintf("🏷️  Checkpoint saved: [%s] %s v%d → %s", args$stage, args$name, version, file.path(args$stage, file_name)))
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
      if (!"NAME" %in% colnames(df)) return(df)

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
  if (is.null(stage)) {
    loaded <- ls(envir = .GlobalEnv)
    rows <- list()

    for (name_loaded in loaded) {
      base <- get(name_loaded, envir = .GlobalEnv)
      info <- attr(base, "checkpoint_info")
      comment <- attr(base, "comment")

      log_path <- file.path("4_checkpoint", "log.xlsx")
      if (!file.exists(log_path)) {
        stop("❌ Log file not found.")
      }
      log_df <- openxlsx::read.xlsx(log_path)
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
    headers <- c("NAME", "STAGE", "VERSION", "DATE")
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
  comment <- attr(base, "comment")

  folder <- file.path("4_checkpoint", info$stage)
  file_path <- file.path(folder, sprintf("%s_%s_v%d.rds", info$stage, info$name, info$version))
  date <- if (file.exists(file_path)) {
    format(file.info(file_path)$ctime, "%Y-%m-%d %H:%M:%S")
  } else {
    "Date not available"
  }

  comment_text <- ifelse(is.null(comment) || comment == "", "(no comment)", comment)

  cat("\n✅ CHECKPOINT ATTRIBUTES ✅\n\n")
  cat(sprintf("%-8s | %-7s | %-7s | %s\n", "NAME", "STAGE", "VERSION", "DATE"))
  cat("-----------------------------------------------\n")
  cat(sprintf("%-8s | %-7s | v%-6d | %s\n\n", info$name, info$stage, info$version, date))
  cat("COMMENT:\n")
  cat(comment_text, "\n")

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
  if (!dir.exists(folder)) stop("❌ Folder '4_checkpoint' not found.")
  log_path <- file.path(folder, "log.xlsx")

  if (!file.exists(log_path)) stop("❌ Cannot tag: log.xlsx not found.")
  log <- openxlsx::read.xlsx(log_path)
  log <- upgrade_log_format(log)

  now <- Sys.time()
  now_unix <- as.numeric(now)

  # Obtener último tag anterior
  last_tag_time <- max(c(0, log$DATE_UNIX[log$IS_TAG]), na.rm = TRUE)

  # Identificar checkpoints no taggeados previos
  to_tag <- which(!log$IS_TAG & (is.na(log$TAG) | log$TAG == "") & log$DATE_UNIX > last_tag_time & log$DATE_UNIX <= now_unix)

  # Aplicar tag
  log$TAG[to_tag] <- tag

  # Crear fila para marcar tag
  tag_row <- data.frame(
    STAGE = "(tag)", NAME = "", VERSION = NA,
    DATE = format(now, "%Y-%m-%d %H:%M:%S"),
    COMMENT = comment,
    ID = generate_id(stage = "(tag)", name = "", tag = tag),
    FILE = NA,
    DATE_UNIX = now_unix,
    IS_TAG = TRUE,
    TAG = tag,
    stringsAsFactors = FALSE
  )

  # Añadir tag al log y guardar
  log <- rbind(log, tag_row)
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "log")
  openxlsx::writeData(wb, "log", log)
  openxlsx::saveWorkbook(wb, log_path, overwrite = TRUE)

  message(sprintf("🏷️  Tag '%s' saved and applied to %d checkpoint(s).", tag, length(to_tag)))
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

normalize_args <- function(stage = NULL, name = NULL, version = NULL, tag = NULL, comment = NULL, obj = NULL, ID = NULL) {
  # Caso especial: sólo se entrega tag, se permite para tags globales
  if (is.null(stage) && is.null(ID) && !is.null(tag)) {
    return(list(
      stage = NULL,
      name = NULL,
      version = NULL,
      tag = tag,
      comment = comment,
      obj = NULL,
      ID = NULL
    ))
  }

  if (!is.null(ID)) {
    parsed <- parse_id(ID)
    tag <- parsed$tag
    stage <- parsed$stage
    name <- parsed$name
    version <- parsed$version
  }

  if (is.null(stage) && is.null(ID)) {
    stop("❌ Either 'stage', 'ID', or a global 'tag' must be provided.")
  }

  if (missing(obj)) obj <- procdata
  if (is.null(obj)) obj <- procdata

  if (is.null(name)) {
    name <- if (!missing(obj)) deparse(substitute(obj)) else "procdata"
  }

  if (!is.null(ID) && is.null(obj)) {
    if (!exists(name, envir = .GlobalEnv)) {
      stop(sprintf("❌ Object '%s' specified in ID does not exist in the environment. Provide it with `obj = ...`.", name))
    } else {
      obj <- get(name, envir = .GlobalEnv)
    }
  }

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
