output "ip" {
  description = "IP publica de la maquina"
  value       = google_compute_instance.agente.network_interface[0].access_config[0].nat_ip
}

output "entrar" {
  description = "Comando para entrar por SSH"
  value       = "ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} ubuntu@${google_compute_instance.agente.network_interface[0].access_config[0].nat_ip}"
}

output "tunel_panel" {
  description = "Tunel para el panel de Hermes, sin exponerlo a internet"
  value       = "ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} -L 9119:127.0.0.1:9119 ubuntu@${google_compute_instance.agente.network_interface[0].access_config[0].nat_ip}   # luego abre http://localhost:9119"
}

output "aviso_trafico" {
  value = <<-EOT

    RECUERDA: el nivel siempre gratis de Google cubre 1 GB de salida al mes.

    Para un agente que conversa por Telegram sobra de lejos. Si le vas a pedir
    que navegue o descargue archivos, ese limite se te va en dias y ahi si
    empiezan a cobrarte.

    Lo miras en la consola, en Facturacion, Informes, filtrando por Network.

  EOT
}
