# checkpoint.R – versioned data manager for R projects

*🇬🇧 English*\
R system to manage checkpoints of data objects during analysis. It allows saving versioned files with metadata, loading specific checkpoints, viewing summaries, and querying comments and attributes. Facilitates organization and reproducibility in complex and collaborative projects.

*🇪🇸 Español*\
Sistema en R para gestionar checkpoints de objetos de datos durante el análisis. Permite guardar archivos versionados con metadatos, cargar checkpoints específicos, visualizar resúmenes y consultar comentarios y atributos. Facilita la organización y reproducibilidad en proyectos complejos y colaborativos.

**(Explicación en español debajo)**

------------------------------------------------------------------------

## Índice / Table of Contents

-   [Features](#features) / [Funcionalidad](#funcionalidad)
-   [Installation](#installation-and-requirements) / [Instalación](#instalación-y-requisitos)
-   [Basic usage](#basic-usage) / [Uso básico](#uso-básico)
-   [Parameters](#function-parameters) / [Parámetros](#parámetros-de-las-funciones)
-   [Saves](#saves) / [Guardado](#guardado)
-   [Author](#author) / [Autor](#autor)

------------------------------------------------------------------------

## Features {#features}

-   **Save checkpoint (`check_save`)**\
    Saves an object to disk with automatic versioning, metadata (stage, name, comment), and logs it in a styled Excel sheet.

-   **Load checkpoint (`check_load`)**\
    Loads a specific checkpoint into the environment by stage, name, and version.

-   **Checkpoint summary (`check_overview`)**\
    Displays a summary of all saved versions and loaded objects. Also allows detailed inspection by stage.

-   **Query attributes (`check_attr`)**\
    Shows checkpoint metadata and comments for objects in memory or saved in disk.

-   **Tag stages (`check_tag`, `check_tags`)**\
    Create and retrieve tags associated with a project stage, independent of specific objects.

-   **Compare identical versions (`check_equal`)** – experimental\
    Detects whether saved objects in a stage are identical in content.

------------------------------------------------------------------------

## Installation and requirements {#installation-and-requirements}

-   Requires R with packages: `openxlsx`, `dplyr`, `tibble`\
-   Functions can be sourced manually, or install the package directly from GitHub:

``` r
remotes::install_github("javiersantibanezferreira/checkpointR")
```

------------------------------------------------------------------------

## Basic usage {#basic-usage}

``` r
# Save a checkpoint
check_save(procdata, name = "procdata", stage = "stage1", comment = "Clean data")

# Load latest version
check_load("stage1", name = "procdata")

# Overview of available and loaded checkpoints
check_overview()

# See attributes and comments
check_attr()

# Add a tag to a stage (not tied to a specific object)
check_tag("stage1", comment = "Preliminary stage closed")

# Review all tags
check_tags()

# Find identical objects
check_equal("stage1")  # Experimental
```

------------------------------------------------------------------------

## Function parameters {#function-parameters}

| Function         | Parameter | Description                      | Required / Default      |
|---------------|---------------|-------------------------|-----------------|
| `check_save`     | `obj`     | R object to save                 | `procdata` by default   |
|                  | `name`    | Name to save                     | From `obj` by default   |
|                  | `stage`   | Project stage name               | Required                |
|                  | `comment` | Optional description             | Optional                |
| `check_load`     | `stage`   | Stage to load from               | Required                |
|                  | `name`    | Object name                      | `"procdata"` by default |
|                  | `version` | Version to load                  | Latest by default       |
|                  | `envir`   | Target environment               | `.GlobalEnv`            |
| `check_overview` | `stage`   | Filter by stage                  | Optional                |
|                  | `envir`   | Environment to search            | `.GlobalEnv`            |
| `check_attr`     | `stage`   | Stage to inspect                 | Optional                |
|                  | `name`    | Object name to inspect           | `"procdata"` by default |
|                  | `version` | Version to inspect               | Latest by default       |
| `check_tag`      | `stage`   | Stage to tag                     | Required                |
|                  | `comment` | Optional tag comment             | Optional                |
| `check_tags`     | `stage`   | Stage to view tags or `"stages"` | Optional                |
|                  | `version` | Specific version to inspect      | Optional                |
| `check_equal`\*  | `stage`   | Compare for duplicates           | Required                |

------------------------------------------------------------------------

## Saves {#saves}

`4_checkpoint/`\
Root directory where a folder is created per stage. Each stage contains `.rds` files, and the main logs:

-   `log.xlsx` → log of saved objects\
-   `tags_log.xlsx` → log of stage tags

------------------------------------------------------------------------

## Author {#author}

Javier S.F.

------------------------------------------------------------------------

------------------------------------------------------------------------

# checkpoint.R – Gestor de versiones de datos para R

## Funcionalidad {#funcionalidad}

-   **Guardar checkpoint (`check_save`)**\
    Guarda un objeto en disco con versión automática, metadatos (etapa, nombre, comentario) y un registro visual en Excel.

-   **Cargar checkpoint (`check_load`)**\
    Carga un checkpoint específico al entorno global según etapa, nombre y versión.

-   **Resumen de checkpoints (`check_overview`)**\
    Muestra un resumen de versiones disponibles y objetos cargados. También permite ver detalle por etapa.

-   **Consultar atributos (`check_attr`)**\
    Muestra información y comentarios de los objetos cargados o guardados.

-   **Etiquetar etapas (`check_tag`, `check_tags`)**\
    Permite registrar y visualizar etiquetas por etapa, sin estar asociadas a objetos específicos.

-   **Comparar versiones (`check_equal`) – experimental**\
    Detecta si existen objetos con contenido idéntico dentro de una misma etapa.

------------------------------------------------------------------------

## Instalación y requisitos {#instalación-y-requisitos}

-   Requiere R con los paquetes: `openxlsx`, `dplyr`, `tibble`\
-   Puedes incluir las funciones directamente en tu script o instalar el paquete desde GitHub:

``` r
remotes::install_github("javiersantibanezferreira/checkpointR")
```

------------------------------------------------------------------------

## Uso básico {#uso-básico}

``` r
# Guardar un checkpoint
check_save(procdata, name = "procdata", stage = "etapa1", comment = "Datos limpios")

# Cargar última versión
check_load("etapa1", name = "procdata")

# Ver resumen de checkpoints
check_overview()

# Consultar atributos y comentarios
check_attr()

# Agregar una etiqueta a una etapa
check_tag("etapa1", comment = "Cierre preliminar")

# Revisar todas las etiquetas
check_tags()

# Verificar duplicados (experimental)
check_equal("etapa1")
```

------------------------------------------------------------------------

## Parámetros de las funciones {#parámetros-de-las-funciones}

| Función          | Parámetro | Descripción                            | Obligatorio / Por defecto  |
|---------------|---------------|--------------------------|-----------------|
| `check_save`     | `obj`     | Objeto a guardar                       | `procdata` por defecto     |
|                  | `name`    | Nombre con que se guardará             | Desde `obj` por defecto    |
|                  | `stage`   | Nombre de la etapa o fase del análisis | Obligatorio                |
|                  | `comment` | Comentario opcional                    | Opcional                   |
| `check_load`     | `stage`   | Etapa desde donde cargar               | Obligatorio                |
|                  | `name`    | Nombre del objeto a cargar             | `"procdata"` por defecto   |
|                  | `version` | Versión a cargar                       | Última versión por defecto |
|                  | `envir`   | Entorno donde cargar el objeto         | `.GlobalEnv`               |
| `check_overview` | `stage`   | Etapa a filtrar                        | Opcional                   |
|                  | `envir`   | Entorno donde buscar objetos cargados  | `.GlobalEnv`               |
| `check_attr`     | `stage`   | Etapa para consultar                   | Opcional                   |
|                  | `name`    | Nombre del objeto a consultar          | `"procdata"` por defecto   |
|                  | `version` | Versión a consultar                    | Última versión por defecto |
| `check_tag`      | `stage`   | Etapa para etiquetar                   | Obligatorio                |
|                  | `comment` | Comentario de la etiqueta              | Opcional                   |
| `check_tags`     | `stage`   | Etapa a visualizar o `"stages"`        | Opcional                   |
|                  | `version` | Versión específica                     | Opcional                   |
| `check_equal`\*  | `stage`   | Compara versiones duplicadas           | Obligatorio                |

------------------------------------------------------------------------

## Guardado {#guardado}

`4_checkpoint/`\
Directorio base donde se crean subcarpetas por etapa. Cada etapa guarda archivos `.rds`, además de los siguientes registros:

-   `log.xlsx` → registro de objetos guardados\
-   `tags_log.xlsx` → registro de etiquetas por etapa

------------------------------------------------------------------------

## Autor {#autor}

Javier S.F.
