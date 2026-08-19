#!/usr/bin/env bash
# Hermes 24/7 gratis en la nube
#
#   ./hermes.sh
#
# Nicolas Neira Garcia
# youtube.com/@nicolasneiragarcia  ·  skool.com/agentic-engineers
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORACLE="$RAIZ/terraform/oracle"
GCP="$RAIZ/terraform/gcp"

if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  C_OK=$'\033[0;32m'; C_AVISO=$'\033[0;33m'; C_MAL=$'\033[0;31m'
  C_TIT=$'\033[1;36m'; C_TEN=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_AVISO=""; C_MAL=""; C_TIT=""; C_TEN=""; C_OFF=""
fi

banner() {
  clear 2>/dev/null || true
  printf '%s' "$C_TIT"
  cat <<'ASCII'
  _   _ _____ ____  __  __ _____ ____
 | | | | ____|  _ \|  \/  | ____/ ___|
 | |_| |  _| | |_) | |\/| |  _| \___ \
 |  _  | |___|  _ <| |  | | |___ ___) |
 |_| |_|_____|_| \_\_|  |_|_____|____/

     I N S T A L L   F R E E   E N   C L O U D
ASCII
  printf '%s' "$C_OFF"
  echo
  echo "  ${C_TEN}──────────────────────────────────────────────────────${C_OFF}"
  echo "   Creado por:  ${C_OK}Nicolás Neira García${C_OFF}"
  echo "   Para:        ${C_TIT}skool.com/agentic-engineers${C_OFF}"
  echo "                ${C_TEN}Comunidad de ingenieros${C_OFF}"
  echo "                ${C_TIT}youtube.com/@nicolasneiragarcia${C_OFF}"
  echo "  ${C_TEN}──────────────────────────────────────────────────────${C_OFF}"
  echo
  echo "   ${C_TEN}Un agente encendido 24/7 por \$0. Sin VPS de pago.${C_OFF}"
  echo
}

titulo()      { echo; echo "${C_TIT}$1${C_OFF}"; echo; }
salto_atras() { echo "  ${C_TEN}<< volviendo atras${C_OFF}"; echo; }
pausa()       { echo; read -r -p "  ${C_TEN}Enter para volver al menu${C_OFF} "; }
ok()     { echo "  ${C_OK}OK${C_OFF}   $1"; }
aviso()  { echo "  ${C_AVISO}OJO${C_OFF}  $1"; }
malo()   { echo "  ${C_MAL}ERROR${C_OFF} $1"; }

instalar_terraform() {
  local version="1.15.4"
  local so arq tmp

  case "$(uname -s)" in
    Darwin) so=darwin ;;
    Linux)  so=linux ;;
    *) malo "Sistema no soportado. Instalalo a mano."; exit 1 ;;
  esac

  case "$(uname -m)" in
    arm64|aarch64) arq=arm64 ;;
    x86_64|amd64)  arq=amd64 ;;
    *) malo "Arquitectura no soportada. Instalalo a mano."; exit 1 ;;
  esac

  tmp=$(mktemp -d)
  local url="https://releases.hashicorp.com/terraform/${version}/terraform_${version}_${so}_${arq}.zip"

  echo "  bajando terraform ${version} para ${so}/${arq}..."
  if ! curl -fsSL "$url" -o "$tmp/tf.zip"; then
    malo "No pude bajarlo. Revisa tu conexion o instalalo a mano."
    rm -rf "$tmp"; exit 1
  fi

  mkdir -p "$HOME/.local/bin"
  unzip -oq "$tmp/tf.zip" -d "$tmp" && mv "$tmp/terraform" "$HOME/.local/bin/terraform"
  chmod +x "$HOME/.local/bin/terraform"
  rm -rf "$tmp"

  export PATH="$HOME/.local/bin:$PATH"

  if command -v terraform >/dev/null 2>&1; then
    ok "terraform instalado en ~/.local/bin"
    aviso "agrega esto a tu perfil para tenerlo siempre:"
    echo '       export PATH="$HOME/.local/bin:$PATH"'
  else
    malo "Quedo en ~/.local/bin pero no esta en tu PATH."
    exit 1
  fi
}

elegir_llave_existente() {
  local usables="" k priv

  for k in "$HOME"/.ssh/*.pub; do
    [ -f "$k" ] || continue
    priv="${k%.pub}"
    [ -f "$priv" ] && usables="${usables}${k}"$'\n'
  done

  if [ -z "$usables" ]; then
    aviso "No tienes ninguna llave completa (publica mas privada) en ~/.ssh."
    read -r -p "  Creo una dedicada? [S/n] " r
    case "${r:-s}" in
      [Nn]*) malo "Sin llave no se puede seguir."; exit 1 ;;
      *) ssh-keygen -t ed25519 -f "$HOME/.ssh/hermes_cloud" -N "" -q -C "hermes-cloud"
         LLAVE_PUB="$HOME/.ssh/hermes_cloud.pub"
         ok "llave creada: $LLAVE_PUB"
         return ;;
    esac
  fi

  echo
  echo "  Tus llaves completas:"
  echo
  local i=0
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    i=$((i + 1))
    printf "    %2d) %s\n" "$i" "$(basename "$k")"
  done <<< "$usables"
  echo

  read -r -p "  Elige [1-$i]: " n
  LLAVE_PUB=$(printf '%s\n' "$usables" | grep . | sed -n "${n}p")

  if [ -z "$LLAVE_PUB" ] || [ ! -f "$LLAVE_PUB" ]; then
    malo "Opcion invalida."
    exit 1
  fi
  ok "llave SSH: $LLAVE_PUB"
}

buscar_pem() {
  local candidatos="" d f

  for d in "$RAIZ" "$HOME/Downloads" "$HOME/Descargas"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.pem; do
      [ -f "$f" ] && candidatos="${candidatos}${f}"$'\n'
    done
  done

  candidatos=$(printf '%s' "$candidatos" | grep . || true)
  local cuantos
  cuantos=$(printf '%s\n' "$candidatos" | grep -c . || true)

  if [ "${cuantos:-0}" -eq 1 ]; then
    LLAVE_API="$candidatos"
    ok "encontre la clave privada: $(basename "$LLAVE_API")"
    echo "     ${C_TEN}en $(dirname "$LLAVE_API")${C_OFF}"

  elif [ "${cuantos:-0}" -gt 1 ]; then
    echo "  Encontre varias claves privadas. Cual es la que acabas de bajar?"
    echo
    local i=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      i=$((i + 1))
      printf "    %2d) %s  ${C_TEN}(%s)${C_OFF}\n" "$i" "$(basename "$f")" "$(dirname "$f")"
    done <<< "$candidatos"
    echo
    read -r -p "  Elige [1-$i]: " n
    LLAVE_API=$(printf '%s\n' "$candidatos" | sed -n "${n}p")
    [ -f "${LLAVE_API:-}" ] || { malo "Opcion invalida."; exit 1; }

  else
    aviso "no encontre ningun .pem ni aca ni en Descargas."
    echo "       Puedes arrastrar el archivo a esta ventana y se pega la ruta."
    echo
    read -r -p "  Donde quedo? " LLAVE_API
    LLAVE_API="${LLAVE_API/#\~/$HOME}"
    LLAVE_API="${LLAVE_API%\'}"; LLAVE_API="${LLAVE_API#\'}"   # por si viene con comillas
    [ -f "$LLAVE_API" ] || { malo "No existe ese archivo."; exit 1; }
  fi

  mkdir -p "$HOME/.oci"
  local destino="$HOME/.oci/oci_api_key.pem"
  if [ "$LLAVE_API" != "$destino" ]; then
    cp "$LLAVE_API" "$destino"
    chmod 600 "$destino"
    ok "copiada a ~/.oci/oci_api_key.pem con permisos seguros"
    echo "     ${C_TEN}la original la puedes borrar cuando quieras${C_OFF}"
    LLAVE_API="$destino"
  else
    chmod 600 "$destino"
  fi
}

elegir_llave_ssh() {
  titulo "La llave para entrar a tu maquina"

  LLAVE_PUB=""
  local dedicada="$HOME/.ssh/hermes_cloud"

  if [ -f "$dedicada.pub" ]; then
    LLAVE_PUB="$dedicada.pub"
    ok "llave SSH: $LLAVE_PUB (la de la vez pasada)"
    return
  fi

  echo "    ${C_TIT}1)${C_OFF} Crear una nueva, dedicada a esto  ${C_TEN}(recomendado)${C_OFF}"
  echo "    ${C_TIT}2)${C_OFF} Usar una que ya tengo"
  echo
  read -r -p "  Elige [1-2, por defecto 1]: " opt

  if [ "${opt:-1}" = "2" ]; then
    elegir_llave_existente
  else
    ssh-keygen -t ed25519 -f "$dedicada" -N "" -q -C "hermes-cloud"
    LLAVE_PUB="$dedicada.pub"
    ok "llave creada"
    echo "     publica:  $dedicada.pub   ${C_TEN}(esta va a la maquina)${C_OFF}"
    echo "     privada:  $dedicada       ${C_TEN}(esta se queda aca, no la compartas)${C_OFF}"
  fi
}

revisar_requisitos() {
  titulo "Revisando lo que necesitas"

  if command -v terraform >/dev/null 2>&1; then
    ok "terraform $(terraform version -json 2>/dev/null | sed -n 's/.*"terraform_version": *"\([^"]*\)".*/\1/p' | head -1)"
  else
    aviso "No tienes terraform, y sin el esto no funciona."
    read -r -p "  Lo bajo a ~/.local/bin? No toca nada del sistema. [S/n] " r
    case "${r:-s}" in
      [Nn]*) malo "Instalalo tu: https://developer.hashicorp.com/terraform/install"; exit 1 ;;
      *) instalar_terraform ;;
    esac
  fi

  MI_IP=$(curl -fsS4 --max-time 8 ifconfig.me 2>/dev/null || echo "")

  if printf '%s' "$MI_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    CIDR="$MI_IP/32"
    ok "tu IP publica: $MI_IP (solo tu vas a poder entrar por SSH)"
  else
    CIDR="0.0.0.0/0"
    aviso "No pude averiguar tu IPv4. Dejo el puerto 22 abierto a todos."
    echo "       Cambialo despues en terraform.tfvars, porque con el puerto"
    echo "       abierto vas a tener bots golpeando en un par de horas."
  fi
}

leer_config_oci() {
  local archivo="$HOME/.oci/config"
  [ -f "$archivo" ] || return 1

  TENANCY=$(sed -n 's/^tenancy[[:space:]]*=[[:space:]]*//p' "$archivo" | head -1)
  USUARIO=$(sed -n 's/^user[[:space:]]*=[[:space:]]*//p' "$archivo" | head -1)
  HUELLA=$(sed -n 's/^fingerprint[[:space:]]*=[[:space:]]*//p' "$archivo" | head -1)
  LLAVE_API=$(sed -n 's/^key_file[[:space:]]*=[[:space:]]*//p' "$archivo" | head -1)
  REGION=$(sed -n 's/^region[[:space:]]*=[[:space:]]*//p' "$archivo" | head -1)

  [ -n "$TENANCY" ] && [ -n "$USUARIO" ] && [ -n "$HUELLA" ] && [ -n "$LLAVE_API" ]
}

pedir_credenciales() {
  titulo "Credenciales de Oracle"

  if leer_config_oci; then
    ok "las saque de ~/.oci/config"
    echo "     region:  $REGION"
    echo "     usuario: ${USUARIO:0:22}..."
    echo
    read -r -p "  Uso estas? [S/n] " r
    case "${r:-s}" in [Nn]*) ;; *) return 0 ;; esac
  fi

  cat <<'PASOS'
  No encontre ~/.oci/config, asi que hay que crear la llave que le permite a
  Terraform actuar en tu cuenta. Se hace una sola vez y son 5 pasos:

    1. Entra a la consola de Oracle: https://cloud.oracle.com
    2. Arriba a la derecha, haz clic en el icono de tu perfil y elige la
       opcion con tu cuenta de correo (no dice "Mi perfil", dice tu email)
    3. En las pestañas de arriba, entra a "Tokens y claves"
    4. Baja hasta la seccion "Claves de API" y dale a "Agregar clave de API".
       Deja marcado "Generar par de claves" y descarga la CLAVE PRIVADA.
       Guardala donde te sea comodo: en esta misma carpeta o en Descargas.
       Yo la busco despues, no te preocupes por la ruta.
    5. Dale a "Agregar". Oracle te va a mostrar una "Vista previa del
       archivo de configuracion", un bloque de texto con varias lineas.

  Ese bloque es lo que necesito. NO lo cierres sin copiarlo, porque no
  vuelve a aparecer.

PASOS

  local modo
  while true; do
  echo "  ${C_TIT}1)${C_OFF} Pegar el bloque completo  ${C_TEN}(mas facil)${C_OFF}"
  echo "  ${C_TIT}2)${C_OFF} Escribir los valores uno por uno"
  echo "  ${C_TIT}3)${C_OFF} Volver al menu de maquinas"
  echo
  read -r -p "  Elige [1-3, por defecto 1]: " modo
  echo

  [ "${modo:-1}" = "3" ] && return 1

  if [ "${modo:-1}" = "2" ]; then
    echo "  ${C_TEN}Enter en blanco en el primer campo para volver atras.${C_OFF}"
    echo
    read -r -p "  tenancy_ocid      : " TENANCY
    if [ -z "$TENANCY" ]; then
      echo; salto_atras; continue
    fi
    read -r -p "  user_ocid         : " USUARIO
    read -r -p "  fingerprint       : " HUELLA
    read -r -p "  ruta al .pem      : " LLAVE_API
    read -r -p "  region de origen  : " REGION
  else
    echo "  Pega el bloque y despues deja una linea en blanco."
    echo "  ${C_TEN}Si no pegas nada y das Enter, vuelves atras.${C_OFF}"
    echo

    local bloque="" linea
    while IFS= read -r linea; do
      [ -z "$linea" ] && break
      bloque="${bloque}${linea}"$'\n'
    done

    if [ -z "$bloque" ]; then
      echo; salto_atras; continue
    fi

    TENANCY=$(printf '%s' "$bloque"  | sed -n 's/^[[:space:]]*tenancy[[:space:]]*=[[:space:]]*//p'     | head -1)
    USUARIO=$(printf '%s' "$bloque"  | sed -n 's/^[[:space:]]*user[[:space:]]*=[[:space:]]*//p'        | head -1)
    HUELLA=$(printf '%s' "$bloque"   | sed -n 's/^[[:space:]]*fingerprint[[:space:]]*=[[:space:]]*//p' | head -1)
    LLAVE_API=$(printf '%s' "$bloque"| sed -n 's/^[[:space:]]*key_file[[:space:]]*=[[:space:]]*//p'    | head -1)
    REGION=$(printf '%s' "$bloque"   | sed -n 's/^[[:space:]]*region[[:space:]]*=[[:space:]]*//p'      | head -1)

    if [ -z "$TENANCY" ] || [ -z "$USUARIO" ] || [ -z "$HUELLA" ] || [ -z "$REGION" ]; then
      malo "No pude leer el bloque. Revisa que lo hayas copiado completo."
      echo
      continue
    fi
    ok "bloque leido"

    echo
    buscar_pem

    echo
    read -r -p "  Lo guardo en ~/.oci/config para no repetirlo? [S/n] " r
    case "${r:-s}" in
      [Nn]*) ;;
      *) mkdir -p "$HOME/.oci"
         { echo "[DEFAULT]"
           echo "tenancy=$TENANCY"
           echo "user=$USUARIO"
           echo "fingerprint=$HUELLA"
           echo "key_file=$LLAVE_API"
           echo "region=$REGION"
         } > "$HOME/.oci/config"
         chmod 600 "$HOME/.oci/config"
         ok "guardado en ~/.oci/config" ;;
    esac
  fi

  break
  done
  return 0
}

elegir_perfil() {
  titulo "Que maquina quieres"

  cat <<MENU
  ${C_TIT}1)${C_OFF} Oracle ARM, una maquina grande      2 OCPU / 12 GB
       Es el maximo que Oracle regala encendido todo el mes.
       ${C_TEN}La capacidad es loteria. Puede que no aparezca nunca.${C_OFF}

  ${C_TIT}2)${C_OFF} Oracle ARM, dos maquinas            1 OCPU / 6 GB cada una
       Misma cuota, repartida. Si una se cae, la otra sigue.
       ${C_TEN}Y pedir 1 nucleo encuentra capacidad mas facil que pedir 2.${C_OFF}

  ${C_TIT}3)${C_OFF} Oracle Intel, la chica              1 OCPU / 1 GB
       ${C_TEN}Casi siempre disponible. El plan B cuando la ARM no aparece.${C_OFF}

  ${C_TIT}4)${C_OFF} Google Cloud, la e2-micro           1 GB / CPU compartida
       Sin loteria: te la entregan.
       ${C_TEN}Pero solo 1 GB de trafico de salida al mes, contra 10 TB de Oracle.${C_OFF}

MENU

  read -r -p "  Elige [1-4]: " OPCION
  echo

  case "$OPCION" in
    1) NUBE=oracle; SHAPE="VM.Standard.A1.Flex";    OCPUS=2; MEM=12; CANT=1 ;;
    2) NUBE=oracle; SHAPE="VM.Standard.A1.Flex";    OCPUS=1; MEM=6;  CANT=2 ;;
    3) NUBE=oracle; SHAPE="VM.Standard.E2.1.Micro"; OCPUS=1; MEM=1;  CANT=1 ;;
    4) NUBE=gcp ;;
    *) malo "Opcion invalida."; exit 1 ;;
  esac
}

elegir_nombre() {
  titulo "Como se va a llamar"

  echo "  Ponle un nombre que te diga para que es. Si creas varias, se les"
  echo "  agrega un numero al final."
  echo
  echo "  ${C_TEN}Ejemplos: agente, secretaria, monitor, cerebro${C_OFF}"
  echo

  while true; do
    read -r -p "  Nombre [agente]: " NOMBRE
    NOMBRE="${NOMBRE:-agente}"

    if printf '%s' "$NOMBRE" | grep -qE '^[a-z][a-z0-9-]{1,29}$'; then
      ok "se va a llamar: $NOMBRE"
      break
    fi
    malo "solo minusculas, numeros y guiones, empezando por letra."
  done
}

escribir_tfvars() {
  local destino="$ORACLE/terraform.tfvars"
  local cidr="$CIDR"

  if [ -f "$destino" ]; then
    cp "$destino" "$destino.anterior"
    aviso "ya existia un terraform.tfvars, lo guarde como terraform.tfvars.anterior"
  fi

  cat > "$destino" <<EOF
# Generado por hermes.sh. Editalo a mano cuando quieras.
# Este archivo NO se sube al repositorio.

tenancy_ocid     = "$TENANCY"
user_ocid        = "$USUARIO"
fingerprint      = "$HUELLA"
private_key_path = "$LLAVE_API"
region           = "$REGION"

shape      = "$SHAPE"
ocpus      = $OCPUS
memoria_gb = $MEM
cantidad   = $CANT

nombre   = "$NOMBRE"
disco_gb = 50

ssh_public_key_path = "$LLAVE_PUB"
ssh_origen_cidr     = "$cidr"
swap_gb             = 2
EOF

  titulo "Esto es lo que escribi en terraform.tfvars"
  sed -E 's/^(tenancy_ocid|user_ocid|fingerprint)([[:space:]]*)=.*/\1\2= "...oculto, mira el archivo..."/' "$destino" | sed 's/^/  /'
  echo
  echo "  ${C_TEN}El archivo completo esta en:${C_OFF}"
  echo "  ${C_TEN}$destino${C_OFF}"
}

mostrar_cuota() {
  titulo "Lo que estas pidiendo"

  if [ "$SHAPE" = "VM.Standard.E2.1.Micro" ]; then
    echo "  Maquinas Intel   $CANT   ${C_TEN}(el nivel gratuito cubre 2 en total)${C_OFF}"
    echo "  Disco            $((50 * CANT)) GB ${C_TEN}de 200${C_OFF}"
  else
    local horas=$((OCPUS * CANT * 744))
    local memh=$((MEM * CANT * 744))
    echo "  CPU      $horas ${C_TEN}de 1.500 horas de OCPU al mes${C_OFF}"
    echo "  Memoria  $memh ${C_TEN}de 9.000 horas de GB al mes${C_OFF}"
    echo "  Disco    $((50 * CANT)) GB ${C_TEN}de 200${C_OFF}"
  fi

  echo
  echo "  ${C_TEN}Los limites se reparten entre TODAS tus maquinas, incluidas${C_OFF}"
  echo "  ${C_TEN}las que hayas creado a mano. Eso lo reviso en un momento.${C_OFF}"
  return 0
}

escribir_indicaciones() {
  local dir="$1"
  local nube="$2"
  local destino="$RAIZ/indicaciones_${NOMBRE}_${nube}.txt"

  {
    cat <<'ASCII'
  _   _ _____ ____  __  __ _____ ____
 | | | | ____|  _ \|  \/  | ____/ ___|
 | |_| |  _| | |_) | |\/| |  _| \___ \
 |  _  | |___|  _ <| |  | | |___ ___) |
 |_| |_|_____|_| \_\_|  |_|_____|____/

     I N S T A L L   F R E E   E N   C L O U D
ASCII
    echo
    echo "  ──────────────────────────────────────────────────────"
    echo "   Creado por:  Nicolás Neira García"
    echo "   Para:        skool.com/agentic-engineers"
    echo "                Comunidad de ingenieros"
    echo "                youtube.com/@nicolasneiragarcia"
    echo "  ──────────────────────────────────────────────────────"
    echo
    echo "  Tu maquina quedo creada. Esto es todo lo que necesitas."
    echo

    echo "══════════════════════════════════════════════════════════"
    echo " TU MAQUINA"
    echo "══════════════════════════════════════════════════════════"
    (cd "$dir" && terraform output -json ips 2>/dev/null \
      | sed 's/[{}"]//g; s/,/\n/g; s/^ */   /' | grep .)
    echo
    (cd "$dir" && terraform output -raw unidad 2>/dev/null | sed 's/^/   unidad: /')
    echo

    echo "══════════════════════════════════════════════════════════"
    echo " QUE HACER AHORA"
    echo "══════════════════════════════════════════════════════════"
    (cd "$dir" && terraform output -raw siguiente_paso 2>/dev/null)
    echo

    echo "══════════════════════════════════════════════════════════"
    echo " TU CUOTA GRATUITA"
    echo "══════════════════════════════════════════════════════════"
    (cd "$dir" && terraform output -raw consumo_de_la_cuota 2>/dev/null | sed 's/^/  /')
    echo

    echo "══════════════════════════════════════════════════════════"
    echo " COSAS QUE SE OLVIDAN"
    echo "══════════════════════════════════════════════════════════"
    echo
    echo "  \"Ayer entraba y hoy no me deja\""
    echo
    echo "  El puerto 22 quedo abierto SOLO para tu IP de hoy. Cuando tu"
    echo "  proveedor te la renueve, o te conectes desde otra red, el SSH se"
    echo "  va a quedar colgado sin decirte por que."
    echo
    echo "     ./hermes.sh   ->  opcion 2, \"No puedo entrar, cambio mi IP\""
    echo
    echo "  Eso lo arregla solo. Y funciona AUNQUE no puedas entrar a la"
    echo "  maquina: la regla vive en Oracle, no dentro del servidor."
    echo
    echo "  El panel de Hermes NO esta expuesto a internet, y es a proposito:"
    echo "  administra tus llaves de API. Se llega por el tunel de arriba."
    echo
    echo "  Para borrar todo lo que creaste:"
    echo "     cd $dir && terraform destroy"
    echo "  o usa ./limpiar.sh, que ademas limpia lo local."
    echo
    echo "  Este archivo se regenera cada vez que creas algo."
    echo
  } > "$destino" 2>/dev/null

  ok "te lo deje por escrito en $(basename "$destino")"
}

comprobar_antes_de_crear() {
  local salida
  echo "  ${C_TEN}revisando contra tu cuenta...${C_OFF}"

  salida=$(cd "$ORACLE" && terraform init -input=false >/dev/null 2>&1; \
           cd "$ORACLE" && terraform plan -input=false -no-color 2>&1)

  if printf '%s' "$salida" | grep -q "Resource precondition failed"; then
    echo
    malo "esto no cabe en tu cuota gratuita:"
    echo
    printf '%s' "$salida" \
      | grep -A 12 "Te pasarias" \
      | sed 's/^/     /'
    echo
    return 1
  fi

  return 0
}

ejecutar() {
  titulo "Listo para crear"
  echo "  1) Crear ahora"
  echo "  2) Crear insistiendo, si te dice que no hay capacidad"
  echo "  3) No hacer nada, yo lo corro despues"
  echo "  4) Volver a elegir la maquina"
  echo
  read -r -p "  Elige [1-4]: " QUE
  echo

  [ "$QUE" = "4" ] && return 1

  case "$QUE" in
    1) cd "$ORACLE" && terraform init -input=false && terraform apply -auto-approve \
         && escribir_indicaciones "$ORACLE" oracle ;;
    2) "$RAIZ/scripts/apply-hasta-que-salga.sh" \
         && escribir_indicaciones "$ORACLE" oracle ;;
    *)
      echo "  Cuando quieras:"
      echo "    cd $ORACLE && terraform apply"
      echo "    $RAIZ/scripts/apply-hasta-que-salga.sh"
      ;;
  esac
}

instalar_gcloud() {
  local so arq tmp url destino="$HOME/.local/google-cloud-sdk"

  case "$(uname -s)" in
    Darwin) so=darwin ;;
    Linux)  so=linux ;;
    *) malo "Sistema no soportado. Instalalo desde https://cloud.google.com/sdk/docs/install"; return 1 ;;
  esac

  case "$(uname -m)" in
    arm64|aarch64) arq=arm ;;
    x86_64|amd64)  arq=x86_64 ;;
    *) malo "Arquitectura no soportada. Instalalo a mano."; return 1 ;;
  esac

  url="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${so}-${arq}.tar.gz"

  aviso "el SDK de Google pesa bastante (unos 150 MB). Puede demorar."
  echo "  bajando google-cloud-cli para ${so}/${arq}..."

  tmp=$(mktemp -d)
  if ! curl -fsSL "$url" -o "$tmp/gcloud.tar.gz"; then
    malo "No pude bajarlo. Revisa tu conexion."
    rm -rf "$tmp"; return 1
  fi

  mkdir -p "$HOME/.local"
  rm -rf "$destino"
  tar -xzf "$tmp/gcloud.tar.gz" -C "$HOME/.local" || { malo "No pude descomprimirlo."; rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"

  "$destino/install.sh" --quiet --usage-reporting=false \
      --path-update=false --command-completion=false >/dev/null 2>&1

  export PATH="$destino/bin:$PATH"

  if command -v gcloud >/dev/null 2>&1; then
    ok "gcloud instalado en ~/.local/google-cloud-sdk"
    aviso "agrega esto a tu perfil para tenerlo siempre:"
    echo '       export PATH="$HOME/.local/google-cloud-sdk/bin:$PATH"'
    return 0
  fi

  malo "Quedo bajado pero no aparece en el PATH."
  return 1
}

asegurar_gcloud() {
  if command -v gcloud >/dev/null 2>&1; then
    ok "gcloud encontrado"
    return 0
  fi

  aviso "no tienes el CLI de Google instalado."
  echo "       Lo bajo a ~/.local, sin sudo y sin tocar tu sistema."
  echo
  read -r -p "  Lo instalo? [S/n] " r
  case "${r:-s}" in
    [Nn]*) malo "Sin gcloud no puedo seguir por Google."; return 1 ;;
  esac

  instalar_gcloud
}

asegurar_sesiones_gcloud() {
  local cuenta

  cuenta=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)

  if [ -z "$cuenta" ]; then
    aviso "no hay ninguna cuenta de Google conectada."
    echo "       Se te va a abrir el navegador. Entra con la cuenta donde"
    echo "       quieres la maquina gratis."
    echo
    read -r -p "  Enter para abrir el navegador " _
    gcloud auth login || { malo "No se pudo iniciar sesion."; return 1; }
    cuenta=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
  fi
  ok "conectado como ${cuenta}"

  if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    aviso "falta el permiso para que Terraform actue en tu nombre."
    echo "       Es un segundo login, y no es un error: el de arriba es para"
    echo "       el CLI, este es para las herramientas. Se abre el navegador."
    echo
    read -r -p "  Enter para continuar " _
    gcloud auth application-default login || { malo "No se pudo autorizar."; return 1; }
  fi
  ok "Terraform autorizado"
}

crear_proyecto_gcp() {
  local nuevo salida
  nuevo="hermes-$(date +%y%m%d)-$RANDOM"

  read -r -p "  Nombre del proyecto [$nuevo]: " PROYECTO
  PROYECTO="${PROYECTO:-$nuevo}"

  echo "  creando $PROYECTO..."
  salida=$(gcloud projects create "$PROYECTO" 2>&1)

  if [ $? -eq 0 ]; then
    ok "proyecto $PROYECTO creado"
    return 0
  fi

  case "$salida" in
    *[Tt]erms*|*TERMS*|*"accept"*|*"Terms of Service"*)
      malo "Tu cuenta todavia no esta registrada en Google Cloud."
      echo
      echo "  Tener gmail no alcanza. Hay que registrarse en Cloud una vez:"
      echo "    1. Entra a  https://console.cloud.google.com"
      echo "    2. Acepta los terminos y agrega tu tarjeta"
      echo "    3. Vuelve aca y corre el script de nuevo"
      echo
      echo "  ${C_TEN}Pide tarjeta pero no cobra, igual que Oracle. Sirve prepago.${C_OFF}"
      ;;
    *alreadyExists*|*"already in use"*|*ALREADY_EXISTS*)
      malo "Ese identificador ya lo tiene otra persona."
      echo "       Tiene que ser unico en TODO Google, no solo en tu cuenta."
      echo "       Prueba de nuevo agregandole algo tuyo al final."
      ;;
    *quota*|*Quota*|*limit*)
      malo "Llegaste al limite de proyectos que Google te deja crear."
      echo "       Borra alguno que no uses en https://console.cloud.google.com"
      ;;
    *)
      malo "No se pudo crear el proyecto. Google respondio:"
      printf '%s\n' "$salida" | head -5 | sed 's/^/       /'
      ;;
  esac
  return 1
}

elegir_proyecto_gcp() {
  local lista n sugerido opcion nuevo

  PROYECTO=""

  lista=$(gcloud projects list --format="value(projectId)" 2>/dev/null)
  n=$(printf '%s\n' "$lista" | grep -c . || true)

  if [ "$n" -eq 0 ]; then
    aviso "tu cuenta no tiene ningun PROYECTO todavia. Creo uno."
    echo "       ${C_TEN}Un proyecto es una carpeta dentro de tu cuenta de Google${C_OFF}"
    echo "       ${C_TEN}Cloud. La cuenta ya la tienes; esto es lo de adentro.${C_OFF}"
    crear_proyecto_gcp || return 1
  else
    echo "  Tus proyectos:"
    printf '%s\n' "$lista" | head -10 | nl -w4 -s') ' | sed 's/^/  /'
    echo "     n) crear uno nuevo"
    echo

    sugerido=$(gcloud config get-value project 2>/dev/null | grep -v '^(unset)$' || true)
    if [ -n "$sugerido" ]; then
      read -r -p "  Numero, o Enter para usar [$sugerido]: " opcion
      [ -z "$opcion" ] && PROYECTO="$sugerido"
    else
      read -r -p "  Numero: " opcion
    fi

    if [ -z "${PROYECTO:-}" ]; then
      case "$opcion" in
        [Nn]) crear_proyecto_gcp || return 1 ;;
        ''|*[!0-9]*) malo "Eso no es un numero."; return 1 ;;
        *)
          PROYECTO=$(printf '%s\n' "$lista" | sed -n "${opcion}p")
          [ -n "$PROYECTO" ] || { malo "No hay un proyecto numero $opcion en la lista."; return 1; }
          ;;
      esac
    fi
  fi

  [ -n "${PROYECTO:-}" ] || { malo "Sin proyecto no se puede seguir."; return 1; }
  gcloud config set project "$PROYECTO" >/dev/null 2>&1
  ok "usando el proyecto $PROYECTO"
}

asegurar_facturacion() {
  local activa cuentas

  activa=$(gcloud billing projects describe "$PROYECTO" \
             --format="value(billingEnabled)" 2>/dev/null)

  if [ "$activa" = "True" ]; then
    ok "facturacion activa (no te van a cobrar por la maquina gratis)"
    return 0
  fi

  aviso "el proyecto no tiene facturacion asociada."
  echo "       Google la exige aunque la maquina sea gratis de por vida."
  echo "       Es el mismo trato que Oracle: pide tarjeta, no cobra."
  echo

  cuentas=$(gcloud billing accounts list --format="value(name)" 2>/dev/null | head -5)

  if [ -z "$cuentas" ]; then
    malo "No tienes ninguna cuenta de facturacion creada."
    echo
    echo "  Esto lo tienes que hacer tu, una sola vez:"
    echo "    1. Entra a  https://console.cloud.google.com/billing"
    echo "    2. Crea una cuenta de facturacion con tu tarjeta"
    echo "    3. Vuelve aca y corre el script de nuevo"
    echo
    echo "  ${C_TEN}Si tienes tarjeta prepago, sirve igual que en Oracle.${C_OFF}"
    return 1
  fi

  echo "  Tus cuentas de facturacion:"
  printf '%s\n' "$cuentas" | nl -w4 -s') ' | sed 's/^/  /'
  echo
  read -r -p "  Cual asocio? [1]: " opcion
  opcion="${opcion:-1}"

  local elegida
  elegida=$(printf '%s\n' "$cuentas" | sed -n "${opcion}p")
  [ -n "$elegida" ] || { malo "Esa opcion no existe."; return 1; }

  if gcloud billing projects link "$PROYECTO" --billing-account="$elegida" >/dev/null 2>&1; then
    ok "facturacion asociada"
  else
    malo "No se pudo asociar. Hazlo en https://console.cloud.google.com/billing"
    return 1
  fi
}

asegurar_api_compute() {
  if gcloud services list --enabled --filter="config.name=compute.googleapis.com" \
       --format="value(config.name)" 2>/dev/null | grep -q compute; then
    ok "API de Compute encendida"
    return 0
  fi

  echo "  encendiendo la API de Compute Engine (demora hasta un minuto)..."
  if gcloud services enable compute.googleapis.com --project="$PROYECTO" >/dev/null 2>&1; then
    ok "API de Compute encendida"
  else
    malo "No se pudo encender la API."
    echo "       Suele ser que falta la facturacion. Revisa:"
    echo "       https://console.cloud.google.com/apis/library/compute.googleapis.com"
    return 1
  fi
}

ruta_google() {
  titulo "Google Cloud"

  aviso "Antes de seguir, el limite que decide si esto te sirve:"
  echo "       1 GB de trafico de SALIDA al mes. Oracle te da 10 TB."
  echo "       Para un agente que conversa por mensajeria, sobra de lejos."
  echo "       Si le vas a pedir que navegue o descargue, se te acaba en dias."
  echo
  read -r -p "  Sigo? [S/n] " r
  case "${r:-s}" in [Nn]*) return 0 ;; esac

  titulo "Dejando tu cuenta de Google lista"

  asegurar_gcloud          || return 1
  asegurar_sesiones_gcloud || return 1
  elegir_proyecto_gcp      || return 1
  asegurar_facturacion     || return 1
  asegurar_api_compute     || return 1

  echo
  echo "  Zonas del nivel siempre gratis:"
  echo "    1) us-central1-a   Iowa"
  echo "    2) us-west1-b      Oregon"
  echo "    3) us-east1-b      Carolina del Sur"
  echo
  read -r -p "  Elige [1-3, por defecto 1]: " z
  case "${z:-1}" in
    2) REGION_GCP="us-west1";   ZONA="us-west1-b" ;;
    3) REGION_GCP="us-east1";   ZONA="us-east1-b" ;;
    *) REGION_GCP="us-central1"; ZONA="us-central1-a" ;;
  esac

  cat > "$GCP/terraform.tfvars" <<EOF
# Generado por hermes.sh
proyecto = "$PROYECTO"
region   = "$REGION_GCP"
zona     = "$ZONA"

nombre   = "$NOMBRE"
disco_gb = 30

ssh_public_key_path = "$LLAVE_PUB"
ssh_origen_cidr     = "$CIDR"
swap_gb             = 2
EOF

  titulo "Esto es lo que escribi"
  sed 's/^/  /' "$GCP/terraform.tfvars"

  echo
  read -r -p "  Creo la maquina ahora? [S/n] " r
  case "${r:-s}" in
    [Nn]*) echo "  Cuando quieras: cd $GCP && terraform apply" ;;
    *) cd "$GCP" && terraform init -input=false && terraform apply -auto-approve \
         && escribir_indicaciones "$GCP" google ;;
  esac
}

confirmar_cuenta_nube() {
  local r

  if [ "$NUBE" = "gcp" ]; then
    read -r -p "  Ya tienes cuenta en Google Cloud? [S/n] " r
    case "${r:-s}" in [Nn]*) ;; *) return 0 ;; esac

    titulo "Crear tu cuenta de Google Cloud"
    cat <<'PASOS'
  Tener gmail NO alcanza. Hay que registrarse en Cloud una vez:

    1. Entra a  https://console.cloud.google.com
    2. Acepta los terminos y condiciones
    3. Te va a pedir una tarjeta. Pide para verificar, no para cobrar.
       Si tienes una prepago, usa esa.
    4. Listo. El proyecto y lo demas lo creo yo desde aqui.

  Dos limites que conviene saber ANTES, no despues:

    - La maquina gratis solo existe en tres regiones de Estados Unidos:
      Iowa, Oregon y Carolina del Sur. Desde Sudamerica vas a notar la
      latencia, aunque para un agente que conversa da lo mismo.
    - 1 GB de trafico de SALIDA al mes. Oracle da 10 TB. Si tu agente va
      a navegar o descargar archivos, este no es tu camino.

PASOS

  else
    read -r -p "  Ya tienes cuenta en Oracle Cloud? [S/n] " r
    case "${r:-s}" in [Nn]*) ;; *) return 0 ;; esac

    titulo "Crear tu cuenta de Oracle Cloud"
    cat <<'PASOS'
    1. Busca en Google "Free Tier Oracle Cloud" y entra al primer resultado
    2. Dale a "Comenzar gratis"
    3. Te va a pedir nombre, correo y una tarjeta de verificacion.
       Cobra un monto pequeño y lo devuelve. Si tienes prepago, usa esa.
    4. Verifica tu correo y ya estas dentro.

  Y ahora lo mas importante de todo este script:

PASOS

    aviso "LA REGION SE ELIGE AL REGISTRARTE Y NO SE PUEDE CAMBIAR NUNCA."
    cat <<'PASOS'
       El nivel gratuito existe SOLO en la region que escojas ahora. Si
       despues te suscribes a otra region para conseguir maquina, esa te
       la cobran.

       Elige una region grande. Las regiones chicas tienen un solo dominio
       de disponibilidad, y la maquina ARM gratis casi nunca aparece ahi.
       Santiago de Chile es una de esas: por eso en el video nunca sale.

       Si tu prioridad es conseguir la ARM, mira que region grande te queda
       cerca antes de darle a registrar. Si te da lo mismo y te conformas
       con las dos maquinas chicas, cualquiera sirve: esas siempre estan.

PASOS
  fi

  echo "  ${C_TEN}Cuando termines de registrarte, vuelve aca.${C_OFF}"
  echo
  read -r -p "  Enter para seguir, o Ctrl+C para salir " _
}

main() {
  revisar_requisitos

  while true; do
    elegir_perfil
    confirmar_cuenta_nube
    elegir_nombre

    if [ "$NUBE" = "gcp" ]; then
      elegir_llave_ssh
      ruta_google
      exit 0
    fi

    pedir_credenciales || { echo; continue; }

    elegir_llave_ssh
    escribir_tfvars

    mostrar_cuota || exit 1

    if ! comprobar_antes_de_crear; then
      echo "  ${C_TEN}Elige otra opcion, o borra lo que no uses.${C_OFF}"
      echo
      pausa
      continue
    fi

    ejecutar && break
    echo
  done
}

flujo_abrir_ip() {
  titulo "Volver a abrirte la puerta"

  local tfvars="$ORACLE/terraform.tfvars"
  if [ ! -f "$tfvars" ]; then
    malo "No hay terraform.tfvars. Primero crea una maquina."
    return 1
  fi

  local mi_ip actual
  mi_ip=$(curl -fsS4 --max-time 10 ifconfig.me 2>/dev/null || echo "")
  if ! printf '%s' "$mi_ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    malo "No pude averiguar tu IP publica. Revisa tu conexion."
    return 1
  fi

  actual=$(grep -E '^ssh_origen_cidr' "$tfvars" | sed -E 's/.*"([^"]*)".*/\1/')

  echo "  La regla dice ahora : ${actual:-(ninguna)}"
  echo "  Tu IP de hoy es     : $mi_ip"
  echo

  if [ "$actual" = "$mi_ip/32" ]; then
    ok "ya calza, asi que el problema es otro:"
    echo
    echo "       - la maquina esta apagada o terminada"
    echo "       - estas usando otra llave SSH"
    echo "       - te equivocaste de IP de la maquina"
    echo
    echo "  ${C_TEN}Mira tu archivo indicaciones_*.txt${C_OFF}"
    echo
    return 0
  fi

  aviso "no calzan, por eso no te deja entrar."
  echo
  read -r -p "  Actualizo la regla a $mi_ip/32 y aplico? [S/n] " r
  case "${r:-s}" in [Nn]*) echo "  Sin cambios."; return 0 ;; esac

  cp "$tfvars" "$tfvars.anterior"
  sed -i '' -E "s|^ssh_origen_cidr.*|ssh_origen_cidr     = \"$mi_ip/32\"|" "$tfvars" 2>/dev/null \
    || sed -i -E "s|^ssh_origen_cidr.*|ssh_origen_cidr     = \"$mi_ip/32\"|" "$tfvars"

  echo
  ok "regla actualizada, aplicando..."
  echo
  (cd "$ORACLE" && terraform apply -auto-approve) || return 1

  echo
  ok "listo, prueba de nuevo el SSH"
  echo "  ${C_TEN}El comando exacto esta en tu indicaciones_*.txt${C_OFF}"
  echo
}

flujo_ver() {
  titulo "Tus maquinas"

  local hay=0 f
  for f in "$RAIZ"/indicaciones_*.txt; do
    [ -f "$f" ] || continue
    hay=1
    echo "  ${C_TIT}$(basename "$f")${C_OFF}"
    sed -n '/TU MAQUINA/,/QUE HACER AHORA/p' "$f" | grep -E ':[0-9]|unidad:' | sed 's/^/  /'
    echo
  done

  if [ "$hay" -eq 0 ]; then
    aviso "todavia no has creado ninguna maquina con esto."
    echo
    return
  fi

  echo "  ${C_TEN}Los comandos completos estan dentro de cada archivo.${C_OFF}"
  echo
}

menu_principal() {
  while true; do
    banner
    echo "   ${C_TIT}1)${C_OFF} Crear una maquina"
    echo "   ${C_TIT}2)${C_OFF} No puedo entrar, cambio mi IP"
    echo "   ${C_TIT}3)${C_OFF} Ver las indicaciones de mis maquinas"
    echo "   ${C_TIT}4)${C_OFF} Salir"
    echo
    read -r -p "  Elige [1-4, por defecto 1]: " QUIERO

    case "${QUIERO:-1}" in
      2) flujo_abrir_ip; pausa ;;
      3) flujo_ver;      pausa ;;
      4) echo; echo "  Hasta la proxima."; echo; exit 0 ;;
      *) main "$@"; exit 0 ;;
    esac
  done
}

menu_principal "$@"
