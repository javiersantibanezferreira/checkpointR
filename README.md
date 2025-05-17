# checkpoint.R – versioned data manager for R projects

*🇬🇧 English*  
R system to manage checkpoints of databases during data analysis. It allows saving versions with metadata, loading specific checkpoints, viewing version summaries, and querying attributes. Facilitates organization and reproducibility in complex and collaborative projects.  

*🇪🇸 Español*  
Sistema en R para gestionar checkpoints de bbdd durante análisis de datos. Permite guardar versiones con metadatos, cargar checkpoints específicos, visualizar resumen de versiones y consultar atributos. Facilita la organización y reproducibilidad en proyectos complejos y colaborativos.  

**(Explicación en español debajo)**

---
## Índice / Table of Contents

- [Features](#features) / [Funcionalidad](#funcionalidad)
- [Installation](#installation-and-requirements) / [Instalación](#instalación-y-requisitos)
- [Basic usage](#basic-usage) / [Uso básico](#uso-básico) 
- [Parameters](#function-parameters) / [Parámetros](#parámetros-de-las-funciones) 
- [Saves](#saves) / [Guardado](#guardado) 
- [Author](#author) / [Autor](#autor)

---

## Features

- **Save checkpoint (`check_save`)**  
  Saves an object to disk with automatic versioning and metadata (stage, name, comment).

- **Load checkpoint (`check_load`)**  
  Loads a specific checkpoint into the global environment by stage, name, and version.

- **Checkpoint summary (`check_overview`)**  
  Displays a summary of all saved versions and objects loaded in memory.

- **Query attributes (`check_attr`)**  
  Shows detailed information (stage, version, date, comment) of loaded or saved objects.

- **Compare identical versions (check_equal) - experimental**  
  Identifies objects with identical content within a given stage.  

---

## Installation and requirements

- Requires R with packages: `openxlsx`, `dplyr`, `tibble` (installed automatically if missing).  
- Simply copy and paste the functions into your session or include them in your script.
  It is recommended to install the package directly from GitHub using:
  
  ```r
  remotes::install_github("javiersantibanezferreira/checkpointR")
  ```


---

## Basic usage

```r
# Save a checkpoint
check_save(procdata, nombre = "procdata", etapa = "stage1", comentario = "Clean data")

# Load the latest checkpoint from a stage
check_load("stage1", nombre = "procdata")

# View checkpoint summary
check_overview()

# Query object attributes
check_attr()

# Check for duplicate versions
check_equal("stage")
*Experimental function*

```
## Function parameters

| Function         | Parameter    | Description                          | Required / Default        |
| ---------------- | ------------ | ------------------------------------ | ------------------------- |
| `check_save`     | `obj`        | Object to save                       | `procdata` by default     |
|                  | `name`       | Name to save the object as           | Name of `obj` by default  |
|                  | `stage`      | Name of the analysis stage           | Required                  |
|                  | `comment`    | Optional comment for the checkpoint  | Optional                  |
| `check_load`     | `stage`      | Stage to load checkpoint from        | Required                  |
|                  | `name`       | Name of the object to load           | `"procdata"` by default   |
|                  | `version`    | Specific version to load             | Latest version by default |
|                  | `envir`      | Environment to load objects into     | `.GlobalEnv` by default   |
| `check_overview` | `stage`      | Filter summary by stage              | Optional                  |
|                  | `envir`      | Environment to search loaded objects | `.GlobalEnv` by default   |
| `check_attr`     | `stage`      | Stage to query attributes            | Optional                  |
|                  | `obj`        | Name of the object to query          | `"procdata"` by default   |
|                  | `version`    | Version to query                     | Latest version by default |
| `check_equal`*   | `stage`      | Check for duplicate versions         | Required                  |

**(experimental)*

---

## Saves

4_checkpoint/  
Root folder where subfolders per stage are created to store `.rds` files and the `registro.xlsx` log.

---

## Author

Javier S.F.

---
---

# checkpoint.R – Gestor de versiones de datos para R  

## Funcionalidad

- **Guardar checkpoint (`check_save`)**  
  Guarda un objeto en disco con versión automática y metadatos (etapa, nombre, comentario).

- **Cargar checkpoint (`check_load`)**  
  Carga un checkpoint específico al entorno global por etapa, nombre y versión.

- **Resumen de checkpoints (`check_overview`)**  
  Muestra un resumen de todas las versiones guardadas y los objetos cargados en memoria.

- **Consultar atributos (`check_attr`)**  
  Muestra información detallada (etapa, versión, fecha, comentario) de los objetos cargados o guardados.

- **Comparar versiones (`check_equal`) - experimental**  
  Identifica si existen objetos con contenido idéntico dentro de una misma etapa.  

---

## Instalación y requisitos

- Requiere R con los paquetes: `openxlsx`, `dplyr`, `tibble` (se instala automáticamente si falta).
- Solo copia y pega las funciones en tu sesión o inclúyelas en tu script.
  Se recomienda instalar el paquete directamente desde GitHub usando:
  
  ```r
  remotes::install_github("javiersantibanezferreira/checkpointR")
  ```

---

## Uso básico

```r
# Guardar un checkpoint
check_save(procdata, nombre = "procdata", etapa = "etapa1", comentario = "Datos limpios")

# Cargar el último checkpoint guardado de una etapa
check_load("etapa1", nombre = "procdata")

# Ver resumen de checkpoints
check_overview()

# Consultar atributos del objeto cargado
check_attr()

# Ver si hay versiones idénticas dentro de una etapa
check_equal("etapa")
*Fase experimental*

```
---

## Parámetros de las funciones

| Función          | Parámetro    | Descripción                            | Obligatorio / Por defecto  |
| ---------------- | ------------ | -------------------------------------- | -------------------------- |
| `check_save`     | `obj`        | Objeto a guardar                       | `procdata` por defecto     |
|                  | `nombre`     | Nombre con que se guardará el objeto   | Igual a `obj` por defecto  |
|                  | `etapa`      | Nombre de la etapa o fase del análisis | Obligatorio                |
|                  | `comentario` | Comentario opcional para el checkpoint | Opcional                   |
| `check_load`     | `etapa`      | Etapa para cargar el checkpoint        | Obligatorio                |
|                  | `nombre`     | Nombre del objeto a cargar             | `"procdata"` por defecto   |
|                  | `version`    | Versión específica a cargar            | Última versión por defecto |
|                  | `envir`      | Entorno donde cargar los objetos       | `.GlobalEnv` por defecto   |
| `check_overview` | `etapa`      | Filtra resumen por etapa               | Opcional                   |
|                  | `envir`      | Entorno donde buscar objetos cargados  | `.GlobalEnv` por defecto   |
| `check_attr`     | `etapa`      | Etapa para consultar atributos         | Opcional                   |
|                  | `obj`        | Nombre del objeto a consultar          | `"procdata"` por defecto   |
|                  | `version`    | Versión a consultar                    | Última versión por defecto |
| `check_equal`*   | `etapa`      | Identifica bases duplicadas            | Obligatorio                |

**(en desarrollo)*

---

## Guardado

4_checkpoint/  
Carpeta base donde se crean subcarpetas por etapa para almacenar los archivos .rds y el registro registro.xlsx.

---

## Autor
Javier S.F.
