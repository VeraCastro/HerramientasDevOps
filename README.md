# HerramientasDevOps
Practicas con herramientas

Automatización de Imágenes de Máquina (AMI) con Packer

Este repositorio contiene prácticas progresivas para la creación automatizada de imágenes de máquina (Golden Images) en AWS y Google Cloud Platform (GCP) utilizando HashiCorp Packer. El proyecto evoluciona desde la ejecución manual hasta la orquestación mediante scripts de Python.

📂 Estructura del Repositorio

    aws.pkr.hcl: Plantilla de Packer para la creación de la imagen en Amazon Web Services.

    google.pkr.hcl: Plantilla de Packer para la creación de la imagen en Google Cloud Platform.

    deploy.py: Script de automatización en Python para ejecutar el flujo de Packer.

    install.sh: Script de provisionamiento (Bash) ejecutado dentro de las instancias durante la construcción.

⚙️ Prerrequisitos

Antes de comenzar, asegúrate de tener instalado:

    Packer: Guía de instalación.

    Python 3.x: Para ejecutar los scripts de automatización.

    Cuentas de Cloud: Acceso a AWS (Access/Secret Keys) y GCP (Service Account JSON).

🚀 Práctica 1: Ejecución Manual (AWS)

En esta primera etapa, se interactúa directamente con la CLI de Packer para crear una imagen en AWS.

Pasos:

    Abre tu terminal en la raíz del proyecto.

    Ejecuta los siguientes comandos en orden secuencial apuntando a la plantilla de AWS:

Bash

# 1. Inicializar la configuración de Packer (descarga plugins necesarios)
packer init aws.pkr.hcl

# 2. Validar la sintaxis y configuración de la plantilla
packer validate aws.pkr.hcl

# 3. Construir la imagen (Build)
packer build aws.pkr.hcl

🐍 Práctica 2: Automatización con Variables de Entorno (AWS + Python)

En esta práctica se introduce el uso de Variables de Entorno para manejar credenciales de forma segura (sin hardcodearlas en el código) y se utiliza Python para orquestar los comandos.

1. Configuración de Variables (Windows)

Debes dar de alta las variables de entorno de usuario en tu sistema operativo. Packer detecta automáticamente las variables que inician con PKR_VAR_.

En PowerShell o CMD (o desde la GUI de Variables de Entorno):
PowerShell

setx PKR_VAR_aws_access_key "Tu_Access_Key_Aqui"
setx PKR_VAR_aws_secret_key "Tu_Secret_Key_Aqui"

    Nota: Reinicia tu terminal o IDE después de configurar las variables para que los cambios surtan efecto.

2. Ejecución

Ejecuta el script de Python que se encargará de correr init, validate y build automáticamente:
Bash

python deploy.py

☁️ Práctica 3: Despliegue Multi-Cloud (AWS + GCP)

Esta práctica extiende la automatización para construir imágenes simultáneamente en AWS y Google Cloud Platform.

1. Configuración GCP

    Debes tener un archivo de credenciales JSON (Service Account Key) descargado de GCP.

    Configura la variable de entorno para el ID del proyecto:

PowerShell

setx PKR_VAR_gcp_project_id "id-de-tu-proyecto-gcp"

2. Ajustes en Plantillas

El archivo google.pkr.hcl debe estar configurado para leer la variable credentials_file o utilizar la autenticación por defecto de la máquina.

3. Ejecución

El script deploy.py ha sido actualizado para detectar la configuración de GCP y ejecutar la construcción en ambas nubes.
Bash

python deploy.py

⚠️ Notas de Seguridad

    Nunca subas tus credenciales (Access Keys, Secret Keys o archivos JSON) al repositorio.

    Asegúrate de que el archivo .gitignore incluya exclusiones para *.json (si guardas credenciales localmente) y archivos de estado de Packer.
