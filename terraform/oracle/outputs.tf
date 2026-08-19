output "ips" {
  description = "IP publica de cada maquina"
  value       = { for i in oci_core_instance.agente : i.display_name => i.public_ip }
}

# Todas las maquinas se crean iguales, asi que basta con mirar la primera.
# Indice [0] y no one(): one() solo acepta listas de cero o un elemento, y aca
# la opcion de dos maquinas ARM crearia dos.
output "unidad" {
  description = "Que unidad quedo creada"
  value       = oci_core_instance.agente[0].shape
}

output "dominio" {
  description = "En que dominio de disponibilidad quedaron"
  value       = oci_core_instance.agente[0].availability_domain
}

output "consumo_de_la_cuota" {
  description = "Cuanto de la cuota gratuita estas usando"
  value       = <<-EOT

    CPU     ${local.horas_ocpu_mes} de 1.500 horas de OCPU al mes
    Memoria ${local.horas_memoria_mes} de 9.000 horas de GB al mes
    Disco   ${local.disco_total} de 200 GB

    (Las cifras de disco NO incluyen maquinas que hayas creado por fuera de
    este Terraform. Esas tambien suman.)

  EOT
}

output "entrar" {
  description = "Comando para entrar por SSH a cada maquina"
  value = {
    for i in oci_core_instance.agente :
    i.display_name => "ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} ubuntu@${i.public_ip}"
  }
}

output "tunel_panel" {
  description = "Tunel para abrir el panel de Hermes en tu navegador, sin exponerlo a internet"
  value = {
    for i in oci_core_instance.agente :
    i.display_name => "ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} -L 9119:127.0.0.1:9119 ubuntu@${i.public_ip}   # luego abre http://localhost:9119"
  }
}

locals {
  llave_privada = replace(var.ssh_public_key_path, ".pub", "")
  primera_ip    = oci_core_instance.agente[0].public_ip
}

# Los comandos van COMPLETOS, con la IP y la llave ya puestas. La idea es que
# se copien y peguen tal cual: si hubiera que armarlos juntando dos salidas
# distintas, esta pantalla dejaria de servir.
output "siguiente_paso" {
  value = <<-EOT

    1. Espera a que la maquina termine de configurarse sola (1 o 2 minutos)
       y comprueba que el swap quedo puesto:

       ssh -i ${local.llave_privada} ubuntu@${local.primera_ip} 'ls /var/lib/cloud/LISTO && free -m'

    2. Instala Hermes:

       ssh -i ${local.llave_privada} ubuntu@${local.primera_ip} 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash'

    3. Entra a configurarlo:

       ssh -i ${local.llave_privada} ubuntu@${local.primera_ip}
       hermes model            # elegir el modelo
       hermes gateway setup    # elegir por donde te habla
       hermes gateway install  # dejarlo como servicio

    4. Para el panel web, sin exponerlo a internet:

       ssh -i ${local.llave_privada} -L 9119:127.0.0.1:9119 ubuntu@${local.primera_ip}
       y abre http://localhost:9119

  EOT
}
