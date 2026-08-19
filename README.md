# Hermes 24/7, gratis

Tu agente encendido las 24 horas en un servidor que no pagas nunca, en el nivel
siempre gratuito de Oracle Cloud o de Google Cloud.

```bash
chmod +x hermes.sh
./hermes.sh
```

Un menú de tres opciones: crear una máquina, arreglar tu acceso si te cambió la
IP, o ver las indicaciones de las máquinas que ya tienes.

## Antes de correrlo

Necesitas macOS o Linux, `git`, y una cuenta en Oracle Cloud o Google Cloud.

Terraform y `gcloud` **no** hacen falta: si no los tienes, el script los baja a
`~/.local` sin sudo y sin tocar tu sistema.

## Qué hay en cada carpeta

```
hermes.sh                    el instalador. Es lo único que ejecutas.

scripts/
  apply-hasta-que-salga.sh   reintenta cuando Oracle dice que no hay capacidad

terraform/oracle/
  main.tf                    red, reglas y máquina, con el validador de cuota
  variables.tf               lo que puedes cambiar, y qué valores son válidos
  outputs.tf                 lo que ves al terminar
  cloud-init.yaml            lo que hace la máquina en su primer arranque
  terraform.tfvars.example   plantilla de tus datos

terraform/gcp/               lo mismo, para Google
```

Tus datos van en `terraform.tfvars`, que el script escribe por ti y que el
`.gitignore` bloquea. El código no se toca.

## El paso a paso está en la comunidad

Este repo es el código. El **cómo** y el **por qué** están en el curso, gratis:

**skool.com/agentic-engineers** → Classroom → *Hermes 24/7 gratis en Oracle y Google*

Ahí está lo que Oracle regala de verdad (no son 4 núcleos y 24 GB), por qué la
región que eliges al registrarte no se cambia nunca, las cinco cosas que Google
exige antes de dejarte crear nada, y qué cabe de verdad en una máquina de 1 GB.

---

Nicolás Neira García
[youtube.com/@nicolasneiragarcia](https://youtube.com/@nicolasneiragarcia) ·
[skool.com/agentic-engineers](https://skool.com/agentic-engineers)
