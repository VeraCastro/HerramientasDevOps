# --- 1. DEFINICIÓN DE VARIABLES ---
# Estas variables nos permiten cambiar la configuración sin tocar el código principal.
variable "gcp_project_id" {
  type        = string
  description = "El ID de tu proyecto en Google Cloud"
}

variable "gcp_zone" {
  type        = string
  default     = "us-central1-a"
  description = "La zona donde se creará la instancia temporal"
}

# ¡IMPORTANTE! La ruta al archivo JSON que descargaste de GCP
variable "gcp_account_file_path" {
  type        = string
  sensitive   = true
  description = "Ruta local al archivo JSON de credenciales de la Service Account"
  default     = "./teak-optics-479123-a6-1770ea2731d0.json" # Asume que el archivo está en la misma carpeta
}


# --- 2. BLOQUE PACKER (EL PLUGIN) ---
# Aquí le decimos a Packer que descargue el "traductor" para Google Compute Engine.
packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}


# --- 3. BLOQUE SOURCE (EL MOLDE) ---
# Usamos el builder "googlecompute"
source "googlecompute" "ubuntu-gcp" {
  # Autenticación y Proyecto
  project_id   = var.gcp_project_id
  credentials_file = var.gcp_account_file_path
  zone         = var.gcp_zone

  # Imagen Base:
  # En GCP es muy fácil usar familias de imágenes. Esto buscará la última
  # versión disponible de Ubuntu 22.04 LTS.
  source_image_family = "ubuntu-2204-lts"
  
  # Configuración de la instancia temporal
  ssh_username = "packer"
  machine_type = "e2-medium" # Un tipo de instancia económico en GCP

  # Nombre de la imagen final que se creará
  image_name        = "practica3-{{timestamp}}"
  image_description = "Imagen creada con Packer en GCP"
}


# --- 4. BLOQUE BUILD (EL ENSAMBLAJE) ---
# Esto es casi idéntico a lo que hacíamos en AWS
build {
  sources = ["source.googlecompute.ubuntu-gcp"]

  provisioner "shell" {
    script = "./install.sh"
  }
}
