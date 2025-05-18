# checkpointR 0.2.0

## Highlights

✨ This release introduces a fully redesigned checkpoint logging and tagging system with enhanced formatting, metadata handling, and visual clarity.

------------------------------------------------------------------------

## 🚀 New Features

-   **Styled Excel Logs**: `check_save()` now writes checkpoints to `log.xlsx` with:
    -   Alternating colors by stage
    -   Priority order: `procdata` first, then others by recency
    -   Column alignment and truncation for long filenames
    -   Hidden internal metadata column `DATE_UNIX`
-   **Tags system**:
    -   `check_tag()` allows saving stage-wide tags with comments and timestamps
    -   `check_tags()` supports multiple views:
        -   Most recent tag
        -   All tags for a given stage
        -   Specific tag version
        -   Summary of latest tag per stage
-   **Version summaries**: `check_overview()` now:
    -   Shows available and loaded checkpoints in aligned, styled tables
    -   Accepts `stage` as argument for a long-format version view
    -   Separates version listings and comments visually
-   **Object attributes display**:
    -   `check_attr()` now queries both loaded objects and saved checkpoint metadata
    -   Table formatting consistent with `check_overview()`

------------------------------------------------------------------------

## ⚠️ Breaking Changes

-   `name` replaces previous parameter aliases like `obj`, `nombre`, etc.
-   Logs now include `DATE_UNIX` and require `openxlsx`, `dplyr`, and `tibble` as dependencies
-   The Excel formatting is not backwards compatible with previous versions' `.xlsx` files

------------------------------------------------------------------------

## 🔧 Internal Improvements

-   Messages standardized with emojis:
    -   ✅ success or confirmation
    -   ❌ error messages
    -   🏷️ tagging or saving checkpoints
-   Better console formatting for visual clarity
-   Full test script included for local validation

------------------------------------------------------------------------

## 🗂️ Files Used

-   `log.xlsx`: stores checkpoints metadata
-   `tags_log.xlsx`: stores stage-level tags and comments
-   `4_checkpoint/`: root directory with one folder per stage

------------------------------------------------------------------------
