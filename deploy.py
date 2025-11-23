import subprocess
import argparse
import sys # Necesario para sys.exit()

# --- Configuración de Argumentos (Igual que tu script) ---
parser = argparse.ArgumentParser(
    description="Script de automatización de Packer con manejo de errores."
)
args = parser.parse_args()
print("Script de Python iniciado.", flush=True)
# ---------------------------------------------------------


def ejecutar_comando_seguro(comando_lista, mensaje_exito):
    """
    Ejecuta un comando con Popen, espera a que termine, y detiene el script si falla.
    """
    print(f"\n--- Ejecutando: {' '.join(comando_lista)} ---", flush=True)

    try:
        # 1. Iniciamos el proceso.
        # stdout=None y stderr=None hacen que la salida se muestre directamente en la terminal.
        proceso = subprocess.Popen(comando_lista, stdout=None, stderr=None)

        # 2. ¡ESTA ES LA CLAVE!
        # Esperamos indefinidamente hasta que este comando termine.
        # Bloquea el script de Python aquí hasta que Packer finalice esta tarea.
        codigo_salida = proceso.wait()

        # 3. Verificamos el resultado.
        if codigo_salida != 0:
            # Si el código no es 0, algo salió mal.
            print(f"\n❌ ERROR FATAL. El comando falló con código de salida: {codigo_salida}")
            print("Deteniendo la ejecución de la secuencia.")
            # Salimos del script de Python inmediatamente indicando un error (1).
            sys.exit(1)
        else:
            # Si es 0, todo salió bien.
            print(f"✅ {mensaje_exito}", flush=True)

    except FileNotFoundError:
        print(f"\n❌ ERROR: No se encontró el ejecutable '{comando_lista[0]}'. ¿Está instalado?")
        sys.exit(1)
    except KeyboardInterrupt:
         print("\n🛑 Ejecución interrumpida por el usuario.")
         proceso.kill()
         sys.exit(130)


# === SECUENCIA PRINCIPAL AWS ===

# Paso 1: Init
ejecutar_comando_seguro(
    ["packer", "init", "aws.pkr.hcl"],
    "Plugins instalados correctamente."
)

# Paso 2: Validate (Solo se ejecuta si el paso 1 tuvo éxito)
ejecutar_comando_seguro(
    ["packer", "validate", "aws.pkr.hcl"],
    "Template validado correctamente."
)

# Paso 3: Build (Solo se ejecuta si los pasos 1 y 2 tuvieron éxito)
ejecutar_comando_seguro(
    ["packer", "build", "aws.pkr.hcl"],
    "Imagen en AMAZON construida con éxito."
)

print("\n🎉 --- Secuencia completa finalizada sin errores ---")


# === SECUENCIA SECUNDARIA GOOGLE CLOUD===

# Paso 1: Init
ejecutar_comando_seguro(
    ["packer", "init", "google.pkr.hcl"],
    "Plugins instalados correctamente."
)

# Paso 2: Validate (Solo se ejecuta si el paso 1 tuvo éxito)
ejecutar_comando_seguro(
    ["packer", "validate", "google.pkr.hcl"],
    "Template validado correctamente."
)

# Paso 3: Build (Solo se ejecuta si los pasos 1 y 2 tuvieron éxito)
ejecutar_comando_seguro(
    ["packer", "build", "google.pkr.hcl"],
    "Imagen en AMAZON construida con éxito."
