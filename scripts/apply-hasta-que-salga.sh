#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# El martillo, pero con Terraform.
#
# La capacidad del nivel gratuito de Oracle se libera cuando alguien mas borra
# su maquina. O sea que conseguirla es estar ahi en el momento justo.
#
# Lo que circula por ahi es un script que aprieta el boton "crear" en el
# navegador. Esto hace lo mismo, pero contra la API, rotando el dominio de
# disponibilidad en cada intento, y cuando por fin sale te deja la maquina
# creada, con red, con swap y con el puerto 22 cerrado a tu IP.
#
# Uso:
#   ./apply-hasta-que-salga.sh                 # cada 3 minutos, 480 intentos
#   ./apply-hasta-que-salga.sh 60 1000         # cada 60s, 1000 intentos
#
# Dejalo corriendo. En macOS, ojo con que el equipo se duerma: usa
#   caffeinate -si ./apply-hasta-que-salga.sh
# ---------------------------------------------------------------------------
set -uo pipefail

ESPERA="${1:-180}"
MAX="${2:-480}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform/oracle" && pwd)"
LOG="$DIR/intentos.log"

cd "$DIR"

if [ ! -f terraform.tfvars ]; then
  echo "Falta terraform.tfvars. Copia terraform.tfvars.example y llenalo."
  exit 1
fi

terraform init -input=false >/dev/null || { echo "terraform init fallo"; exit 1; }

# Cuantos dominios de disponibilidad tiene tu region. Si es 1, rotar no sirve
# de nada y conviene saberlo de entrada en vez de descubrirlo en el intento 300.
DOMINIOS=$(terraform console <<<'length(data.oci_identity_availability_domains.todos.availability_domains)' 2>/dev/null | tr -d '"' | tr -dc '0-9')
DOMINIOS=${DOMINIOS:-1}

echo "Region con $DOMINIOS dominio(s) de disponibilidad."
if [ "$DOMINIOS" -eq 1 ]; then
  echo
  echo "  AVISO: tu region tiene UN SOLO dominio de disponibilidad."
  echo "  Rotar no te va a ayudar, porque no hay a donde rotar. Si la A1 no"
  echo "  aparece en unas horas, lo mas probable es que no aparezca."
  echo "  El plan B es la Intel chica: en terraform.tfvars pon"
  echo "      shape = \"VM.Standard.E2.1.Micro\""
  echo "  Esa casi siempre esta disponible."
  echo
fi

for (( i=1; i<=MAX; i++ )); do
  IDX=$(( (i - 1) % DOMINIOS ))

  SALIDA=$(terraform apply -auto-approve -input=false -var="dominio_index=$IDX" 2>&1)
  CODIGO=$?

  if [ $CODIGO -eq 0 ]; then
    echo "$(date -u +%FT%TZ) intento $i: CREADA" | tee -a "$LOG"
    echo
    terraform output
    exit 0
  fi

  # "Out of host capacity" es el unico error que vale la pena reintentar.
  # Cualquier otro (credenciales malas, cuota excedida, error de sintaxis)
  # se va a repetir igual 480 veces, asi que mejor parar y mostrarlo.
  if echo "$SALIDA" | grep -qiE "out of host capacity|insufficient.*capacity"; then

    # Cuantas maquinas llevamos. Con cantidad = 2 es normal que Oracle te de
    # una y te niegue la otra, y conviene saberlo: ya tienes donde trabajar
    # mientras el script sigue peleando por la que falta.
    #
    # Y por esto mismo el script NUNCA hace destroy al fallar: borraria la
    # maquina que acabas de conseguir despues de horas esperando.
    LISTAS=$(terraform state list 2>/dev/null | grep -c '^oci_core_instance\.' || echo 0)

    if [ "$LISTAS" -gt 0 ]; then
      echo "$(date -u +%FT%TZ) intento $i (dominio $IDX): sin capacidad, pero ya tienes $LISTAS maquina(s) creada(s)" | tee -a "$LOG"
      echo "   Puedes empezar a trabajar en esa mientras esto sigue:"
      terraform output -json entrar 2>/dev/null | sed 's/[{}"]//g; s/,/\n/g; s/^/     /'
    else
      echo "$(date -u +%FT%TZ) intento $i (dominio $IDX): sin capacidad" | tee -a "$LOG"
    fi

    sleep "$ESPERA"
    continue
  fi

  echo "$(date -u +%FT%TZ) intento $i: error DISTINTO, me detengo" | tee -a "$LOG"
  echo "$SALIDA" | tail -25
  exit 1
done

echo "$(date -u +%FT%TZ) agotados $MAX intentos sin conseguir capacidad" | tee -a "$LOG"
echo
echo "Tu region no tiene capacidad libre para esa unidad. Opciones, en orden:"
echo "  1. Cambiar a la Intel chica: en terraform.tfvars pon"
echo "       shape = \"VM.Standard.E2.1.Micro\""
echo "  2. Irte a Google Cloud, en ../gcp, que no tiene loteria de capacidad"
echo
echo "La red que quedo creada NO la borro a proposito: no cuesta nada, y si"
echo "vuelves a intentar mañana el reintento parte desde ahi en vez de crearla"
echo "de nuevo. Si quieres limpiarla igual:"
echo "       cd $DIR && terraform destroy"
exit 1
