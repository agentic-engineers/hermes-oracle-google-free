variable "proyecto" {
  description = "ID de tu proyecto de Google Cloud"
  type        = string
}

variable "region" {
  description = <<-EOT
    Region. El nivel siempre gratis SOLO cubre estas tres:
      us-west1     Oregon
      us-central1  Iowa
      us-east1     Carolina del Sur
    Cualquier otra te cobra.
  EOT
  type        = string
  default     = "us-central1"
}

variable "zona" {
  description = "Zona dentro de la region"
  type        = string
  default     = "us-central1-a"

  validation {
    condition     = can(regex("^(us-west1|us-central1|us-east1)-", var.zona))
    error_message = "Esa zona no entra en el nivel siempre gratis. Usa us-west1, us-central1 o us-east1."
  }
}

variable "nombre" {
  description = "Nombre de la maquina"
  type        = string
  default     = "agente"
}

variable "disco_gb" {
  description = "Disco. El nivel gratis cubre 30 GB estandar. Mas que eso se cobra."
  type        = number
  default     = 30

  validation {
    condition     = var.disco_gb <= 30
    error_message = "El nivel siempre gratis cubre hasta 30 GB. Mas que eso te van a cobrar."
  }
}

variable "ssh_public_key_path" {
  description = "Ruta a tu llave publica SSH"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_origen_cidr" {
  description = "Desde donde se permite SSH. Tu IP con /32. La sacas con: curl ifconfig.me"
  type        = string
  default     = "0.0.0.0/0"
}

variable "swap_gb" {
  description = "Swap. Con 1 GB de RAM no lo bajes de 2."
  type        = number
  default     = 2
}
