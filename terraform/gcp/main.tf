terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.proyecto
  region  = var.region
  zone    = var.zona
}

# ---------------------------------------------------------------------------
# Por que este modulo es mas corto que el de Oracle
# ---------------------------------------------------------------------------
# Porque aca no hay loteria. Google te entrega la e2-micro y punto. No hace
# falta script de reintento ni rotar dominios.
#
# El precio de esa tranquilidad esta en los limites, y conviene tenerlos a la
# vista antes de escribir una linea:
#
#   1 e2-micro         solo en us-west1, us-central1 o us-east1
#   30 GB de disco     estandar, no SSD
#   1 GB de salida     al mes, desde Norteamerica
#
# Ese ultimo numero es el que decide. Oracle te da 10 TB. Si tu agente solo
# conversa por Telegram, 1 GB te sobra. Si navega o descarga, se te acaba en
# dias.

resource "google_compute_network" "red" {
  name                    = "${var.nombre}-red"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subred" {
  name          = "${var.nombre}-subred"
  network       = google_compute_network.red.id
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
}

resource "google_compute_firewall" "ssh" {
  name    = "${var.nombre}-ssh"
  network = google_compute_network.red.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Igual que en Oracle: el panel de Hermes no se expone. Se llega por tunel.
  source_ranges = [var.ssh_origen_cidr]
  target_tags   = ["agente"]
}

resource "google_compute_instance" "agente" {
  name         = var.nombre
  machine_type = "e2-micro" # el unico que entra en el nivel siempre gratis
  zone         = var.zona
  tags         = ["agente"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = var.disco_gb
      type  = "pd-standard" # el SSD NO entra en el nivel gratuito
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subred.id

    # Bloque vacio a proposito: es lo que le asigna IP publica efimera.
    access_config {}
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.ssh_public_key_path)}"
    user-data = templatefile("${path.module}/../oracle/cloud-init.yaml", {
      swap_gb = var.swap_gb
    })
  }

  # Preemptible seria mas barato, pero Google la puede apagar cuando quiera y
  # ademas no entra en el nivel gratis. Para un agente 24/7 no sirve.
  scheduling {
    preemptible       = false
    automatic_restart = true
  }
}
