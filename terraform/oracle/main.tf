terraform {
  required_version = ">= 1.5"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# ---------------------------------------------------------------------------
# Que hay disponible en tu region
# ---------------------------------------------------------------------------
# Nada de OCIDs pegados a mano. Todo se consulta, asi el codigo funciona en
# cualquier region sin tocar una linea.

data "oci_identity_availability_domains" "todos" {
  compartment_id = var.tenancy_ocid
}

locals {
  dominios = data.oci_identity_availability_domains.todos.availability_domains

  # La A1 puede ir en cualquier dominio de disponibilidad, asi que el script
  # de reintento va rotando este indice. Si tu region tiene uno solo, como
  # Santiago, el modulo siempre cae en el mismo y no hay nada que rotar.
  # Ese detalle es la diferencia entre conseguir la maquina o no.
  dominio = local.dominios[var.dominio_index % length(local.dominios)].name

  # Las unidades que terminan en .Flex aceptan nucleos y RAM a medida.
  # Las fijas no, y si les mandas shape_config el apply falla.
  es_flexible = can(regex("\\.Flex$", var.shape))

  # ---------------------------------------------------------------------
  # La cuenta que decide si esto te sale gratis o te llega en la factura
  # ---------------------------------------------------------------------
  # Oracle NO regala "4 nucleos y 24 GB", aunque eso repitan todos. Regala un
  # presupuesto de HORAS: 1.500 de OCPU y 9.000 de GB al mes.
  #
  # Son 744, las horas de un mes de 31 dias. Es el peor caso a
  # proposito: si tu configuracion pasa en agosto, pasa todo el año. Con el
  # promedio de 730 te podrias colar en los meses largos.
  horas_mes = 744

  # --- Lo que ya tienes creado --------------------------------------------
  # Los nombres que crea ESTE modulo. Hacen falta para no contarlos dos
  # veces: una como maquina existente en la cuenta y otra como maquina por
  # crear. Sin esto, la segunda vez que corres un apply sin cambiar nada el
  # validador te bloquea un plan que no iba a crear absolutamente nada.
  #
  # Contrapartida honesta: si creaste a mano una maquina con este mismo
  # nombre y fuera de Terraform, no va a entrar en la cuenta. Por eso conviene
  # dejarle un nombre propio en var.nombre.
  nombres_propios = var.cantidad > 1 ? [
    for i in range(var.cantidad) : "${var.nombre}-${i + 1}"
  ] : [var.nombre]

  # Fuera las terminadas, que ya no ocupan nada, y las que crea este modulo.
  vivas = [
    for i in data.oci_core_instances.existentes.instances : i
    if i.state != "TERMINATED" && !contains(local.nombres_propios, i.display_name)
  ]

  # Las A1 gastan de la bolsa de horas. Las Intel micro no, tienen su propio
  # limite de dos instancias.
  a1_vivas    = [for i in local.vivas : i if can(regex("\\.A1\\.", i.shape))]
  micro_vivas = [for i in local.vivas : i if i.shape == "VM.Standard.E2.1.Micro"]

  ocpus_en_uso = length(local.a1_vivas) == 0 ? 0 : sum(
    [for i in local.a1_vivas : try(i.shape_config[0].ocpus, 0)]
  )
  memoria_en_uso = length(local.a1_vivas) == 0 ? 0 : sum(
    [for i in local.a1_vivas : try(i.shape_config[0].memory_in_gbs, 0)]
  )

  # --- Lo que vas a pedir ahora -------------------------------------------
  ocpus_nuevos  = var.ocpus * var.cantidad
  memoria_nueva = var.memoria_gb * var.cantidad
  micros_nuevos = var.shape == "VM.Standard.E2.1.Micro" ? var.cantidad : 0

  # --- El total, que es lo que Oracle mira --------------------------------
  horas_ocpu_mes    = (local.ocpus_en_uso + local.ocpus_nuevos) * local.horas_mes
  horas_memoria_mes = (local.memoria_en_uso + local.memoria_nueva) * local.horas_mes
  micros_totales    = length(local.micro_vivas) + local.micros_nuevos

  # El disco de las maquinas existentes no se puede leer sin permisos extra,
  # asi que aca solo cuentan las nuevas y la salida lo advierte. Es la unica de
  # las tres cuotas que queda a ojo.
  disco_total = var.disco_gb * var.cantidad

}

# La A1 es ARM y la Intel es x86, asi que la imagen tiene que coincidir con la
# arquitectura o la maquina no arranca. No hay que calcularlo a mano: al filtrar
# por "shape" aca abajo, Oracle ya devuelve solo las imagenes compatibles.

# ---------------------------------------------------------------------------
# Que tienes YA creado en la cuenta
# ---------------------------------------------------------------------------
# Sin esto, el modulo solo cuenta lo que el mismo crea. Y el caso normal es
# justamente el otro: ya tienes una o dos maquinas hechas a mano desde la
# consola, y al pedir otra te pasas de la cuota sin enterarte.
#
# Oracle no te avisa. Si tu cuenta esta en pago por uso, simplemente te cobra.

data "oci_core_instances" "existentes" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ---------------------------------------------------------------------------
# La red
# ---------------------------------------------------------------------------
# Esto va ANTES de la maquina. Si lo haces al reves salen errores que no
# dicen lo que realmente pasa.

resource "oci_core_vcn" "red" {
  compartment_id = var.tenancy_ocid
  display_name   = "${var.nombre}-red"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "red"
}

resource "oci_core_internet_gateway" "salida" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.red.id
  display_name   = "${var.nombre}-salida"
  enabled        = true
}

resource "oci_core_route_table" "rutas" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.red.id
  display_name   = "${var.nombre}-rutas"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.salida.id
  }
}

resource "oci_core_security_list" "reglas" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.red.id
  display_name   = "${var.nombre}-reglas"

  # Salida: todo permitido. La maquina necesita llamar a las APIs de modelos.
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # Entrada: SOLO SSH, y solo desde donde tu digas.
  # El panel de Hermes NO se abre aca a proposito. Se llega por tunel SSH,
  # porque ese panel administra tus llaves de API.
  ingress_security_rules {
    source   = var.ssh_origen_cidr
    protocol = "6" # TCP
    tcp_options {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_subnet" "publica" {
  compartment_id             = var.tenancy_ocid
  vcn_id                     = oci_core_vcn.red.id
  display_name               = "${var.nombre}-publica"
  cidr_block                 = "10.0.1.0/24"
  route_table_id             = oci_core_route_table.rutas.id
  security_list_ids          = [oci_core_security_list.reglas.id]
  prohibit_public_ip_on_vnic = false
  dns_label                  = "publica"
}

# ---------------------------------------------------------------------------
# La maquina
# ---------------------------------------------------------------------------

resource "oci_core_instance" "agente" {
  count = var.cantidad

  compartment_id      = var.tenancy_ocid
  availability_domain = local.dominio
  display_name        = var.cantidad > 1 ? "${var.nombre}-${count.index + 1}" : var.nombre
  shape               = var.shape

  # Solo para las unidades .Flex. En las fijas este bloque no se genera.
  dynamic "shape_config" {
    for_each = local.es_flexible ? [1] : []
    content {
      ocpus         = var.ocpus
      memory_in_gbs = var.memoria_gb
    }
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = var.disco_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.publica.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      swap_gb = var.swap_gb
    }))
  }

  # Al destruir la instancia se borra tambien su disco. Es a proposito: si lo
  # dejaras conservado, cada destroy te iria dejando discos huerfanos que
  # consumen tu cuota gratuita de 200 GB sin que los veas.
  preserve_boot_volume = false

  lifecycle {
    ignore_changes = [source_details[0].source_id]

    # ---------------------------------------------------------------------
    # La baranda que Oracle te quita
    # ---------------------------------------------------------------------
    # En una cuenta de nivel gratuito puro, Oracle no te deja pasarte. Pero el
    # remedio que todos recomiendan contra la falta de capacidad es subir a
    # pago por uso, y ahi la baranda desaparece: te deja crear lo que quieras
    # y te cobra la diferencia sin preguntar.
    #
    # Estas dos comprobaciones la reponen. Si tu configuracion se pasa de la
    # cuota gratuita, el plan falla ANTES de crear nada.

    precondition {
      condition     = !local.es_flexible || local.horas_ocpu_mes <= 1500
      error_message = <<-EOT
        Te pasarias de la cuota gratuita de CPU.

        Ya tienes en la cuenta : ${local.ocpus_en_uso} OCPU en maquinas A1
        Estas pidiendo ahora    : ${local.ocpus_nuevos} OCPU (${var.ocpus} x ${var.cantidad} maquina(s))
        Total                   : ${local.horas_ocpu_mes} horas al mes, de 1.500 permitidas

        Oracle NO regala nucleos, regala horas: 1.500 de OCPU al mes. Una
        maquina encendida siempre gasta 744 horas por nucleo.

        Y ojo con el sello "siempre gratis elegible": dice que la UNIDAD
        califica, no que TU configuracion sea gratis. Por eso los 4 nucleos
        que repiten todos los tutoriales no caben, serian 2.976 horas.

        Encendido 24/7 te alcanza para 2 OCPU en total. Repartelos como
        quieras: una maquina de 2, o dos de 1.

        Si lo que ya tienes creado no lo usas, borralo antes de seguir.
      EOT
    }

    precondition {
      condition     = !local.es_flexible || local.horas_memoria_mes <= 9000
      error_message = <<-EOT
        Te pasarias de la cuota gratuita de memoria.

        Ya tienes en la cuenta : ${local.memoria_en_uso} GB en maquinas A1
        Estas pidiendo ahora    : ${local.memoria_nueva} GB
        Total                   : ${local.horas_memoria_mes} horas al mes, de 9.000 permitidas

        Encendido 24/7 te alcanza para 12 GB en total.
      EOT
    }

    precondition {
      condition     = local.micros_totales <= 2
      error_message = <<-EOT
        Te pasarias del limite de maquinas Intel.

        Ya tienes creadas : ${length(local.micro_vivas)}
        Estas pidiendo    : ${local.micros_nuevos}
        Total             : ${local.micros_totales}, y el maximo gratis son 2.

        Esta es la trampa mas facil de pisar, porque la tercera se crea sin
        una sola advertencia de Oracle y aparece en la factura del mes.
      EOT
    }

    precondition {
      condition     = local.disco_total <= 200
      error_message = <<-EOT
        Te pasaste de la cuota gratuita de disco.

        Oracle regala 200 GB de almacenamiento en total, sumando TODAS tus
        maquinas, incluidas las que ya tengas creadas por otro lado.

        Tu configuracion pide ${local.disco_total} GB (${var.disco_gb} GB x ${var.cantidad}).
      EOT
    }
  }
}
