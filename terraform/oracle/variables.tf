# Credenciales de la API de Oracle.
#
# En la consola: icono de perfil arriba a la derecha, tu cuenta de correo,
# pestaña "Tokens y claves", seccion "Claves de API", "Agregar clave de API".
# Deja marcado "Generar par de claves" y descarga la clave privada.
#
# Al agregarla, Oracle muestra una "Vista previa del archivo de configuracion"
# con estos cuatro valores adentro. Copialos aca antes de cerrar esa ventana,
# porque no vuelve a aparecer.
#
# El instalador hace todo esto por ti si le pegas ese bloque completo.

variable "tenancy_ocid" {
  description = "OCID de tu tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID de tu usuario"
  type        = string
}

variable "fingerprint" {
  description = "Huella de la llave de API"
  type        = string
}

variable "private_key_path" {
  description = "Ruta a la llave privada de la API (el .pem que descargaste)"
  type        = string
}

variable "region" {
  description = "Tu region de origen. OJO: las maquinas gratis SOLO se crean aca."
  type        = string
  # Ejemplo: "sa-santiago-1", "us-ashburn-1", "eu-frankfurt-1"
}

# Que maquina quieres

variable "shape" {
  description = <<-EOT
    La unidad de computo.

      VM.Standard.A1.Flex      ARM. Hasta 4 nucleos y 24 GB gratis.
                               Es la buena. Tambien es la que puede no
                               aparecer nunca por falta de capacidad.

      VM.Standard.E2.1.Micro   Intel. 1 nucleo y 1 GB. Puedes tener dos.
                               Casi siempre disponible.
  EOT
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "ocpus" {
  description = "Nucleos. Solo aplica a la A1. Pedir menos mejora tus posibilidades."
  type        = number
  default     = 1
}

variable "memoria_gb" {
  description = "RAM en GB. Solo aplica a la A1. La proporcion gratis es 6 GB por nucleo."
  type        = number
  default     = 6
}

variable "cantidad" {
  description = <<-EOT
    Cuantas maquinas iguales crear.

    Sirve para repartir la cuota. Con la A1 tienes 1.500 horas de OCPU al mes,
    que dan para 2 nucleos encendidos siempre. Puedes gastarlos en:

      cantidad = 1, ocpus = 2, memoria_gb = 12    una maquina grande
      cantidad = 2, ocpus = 1, memoria_gb = 6     dos maquinas, mas resistente

    La segunda opcion es la que uso yo: si una se cae o hay que reinstalarla,
    la otra sigue en pie. Y ademas pedir 1 nucleo tiene mas posibilidades de
    encontrar capacidad que pedir 2.
  EOT
  type        = number
  default     = 1

  # OJO: la cuota de la A1 y la de las micro Intel NO se suman. La doc de
  # Oracle describe combinaciones, y una de ellas es explicita: dos A1 de 1
  # nucleo cada una implica CERO micro Intel. Los 200 GB de disco tambien son
  # un total compartido entre todas tus maquinas, incluidas las que hayas
  # creado por fuera de este Terraform.
  validation {
    condition     = var.cantidad >= 1 && var.cantidad <= 2
    error_message = "Entre 1 y 2. La cuota de OCPU no da para mas maquinas encendidas 24/7."
  }
}

variable "nombre" {
  description = "Nombre de la instancia. Con cantidad > 1 se le agrega un numero."
  type        = string
  default     = "agente"
}

variable "dominio_index" {
  description = <<-EOT
    Cual de los dominios de disponibilidad usar. Lo rota solo el script
    apply-hasta-que-salga.sh.

    Si tu region tiene tres dominios, rotar multiplica tus posibilidades.
    Si tiene uno solo, como Santiago, esto no hace nada y ahi esta el
    problema de raiz.
  EOT
  type        = number
  default     = 0
}

variable "disco_gb" {
  description = "Disco de arranque. El nivel gratis cubre 200 GB en total entre todas tus maquinas."
  type        = number
  default     = 50
}

# Acceso

variable "ssh_public_key_path" {
  description = "Ruta a tu llave publica SSH (la .pub)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_origen_cidr" {
  description = <<-EOT
    Desde donde se permite entrar por SSH.

    Dejarlo en 0.0.0.0/0 abre el puerto 22 a todo internet. Funciona, pero
    en menos de dos horas vas a tener bots intentando entrar.

    Pon tu IP con /32 al final. La averiguas con: curl ifconfig.me
    Ejemplo: "203.0.113.25/32"
  EOT
  type        = string
  default     = "0.0.0.0/0"
}

variable "swap_gb" {
  description = "Swap que se crea al arrancar. En maquinas de 1 GB no es opcional."
  type        = number
  default     = 2
}
