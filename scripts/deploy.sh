#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  deploy.sh — VivaEventos: levantar toda la infraestructura con un solo comando
#
#  USO:
#    ./scripts/deploy.sh              # Deploy completo
#    ./scripts/deploy.sh --only user-service ticket-service   # Solo algunos servicios
#    ./scripts/deploy.sh --skip-gateway                       # Sin Traefik
#
#  REQUISITOS:
#    - kubectl instalado y configurado apuntando al cluster correcto
#    - Haber creado el archivo k8s/secrets/secrets.yaml (a partir del template)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="$ROOT_DIR/k8s"

# ── Opciones ──────────────────────────────────────────────────────────────────
SKIP_GATEWAY=false
ONLY_SERVICES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-gateway)
      SKIP_GATEWAY=true
      shift
      ;;
    --only)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        ONLY_SERVICES+=("$1")
        shift
      done
      ;;
    *)
      echo -e "${RED}Opción desconocida: $1${NC}"
      exit 1
      ;;
  esac
done

ALL_SERVICES=(
  user-service
  event-service
  order-service
  payment-service
  notification-service
  ticket-service
  dashboard-service
  frontend
)

# Si se pasó --only, usar solo esos servicios
if [[ ${#ONLY_SERVICES[@]} -gt 0 ]]; then
  SERVICES_TO_DEPLOY=("${ONLY_SERVICES[@]}")
else
  SERVICES_TO_DEPLOY=("${ALL_SERVICES[@]}")
fi

# ── Funciones ─────────────────────────────────────────────────────────────────
log_step() { echo -e "\n${BLUE}▶ $1${NC}"; }
log_ok()   { echo -e "  ${GREEN}✔ $1${NC}"; }
log_warn() { echo -e "  ${YELLOW}⚠ $1${NC}"; }
log_err()  { echo -e "  ${RED}✖ $1${NC}"; }

check_prerequisites() {
  log_step "Verificando prerequisitos..."

  if ! command -v kubectl &>/dev/null; then
    log_err "kubectl no encontrado. Instálalo: https://kubernetes.io/docs/tasks/tools/"
    exit 1
  fi
  log_ok "kubectl: $(kubectl version --client --short 2>/dev/null | head -1)"

  if ! kubectl cluster-info &>/dev/null; then
    log_err "No hay conexión al cluster. Verifica tu kubeconfig."
    exit 1
  fi
  log_ok "Cluster: $(kubectl config current-context)"

  local SECRETS_FILE="$K8S_DIR/secrets/secrets.yaml"
  if [[ ! -f "$SECRETS_FILE" ]]; then
    log_err "No se encontró $SECRETS_FILE"
    echo ""
    echo "  Crea el archivo copiando la plantilla y completando los valores:"
    echo "  cp k8s/secrets/secrets.template.yaml k8s/secrets/secrets.yaml"
    echo "  # Edita secrets.yaml con tus valores en base64"
    echo "  # ⚠️  Asegúrate de que secrets.yaml esté en .gitignore"
    exit 1
  fi
  log_ok "Archivo de secretos encontrado"
}

apply_namespace() {
  log_step "Creando namespace vivaeventos..."
  kubectl apply -f "$K8S_DIR/namespace/namespace.yaml"
  log_ok "Namespace listo"
}

apply_secrets() {
  log_step "Aplicando secretos..."
  kubectl apply -f "$K8S_DIR/secrets/secrets.yaml"
  log_ok "Secretos aplicados"
}

apply_shared_infrastructure() {
  log_step "Levantando infraestructura compartida (RabbitMQ)..."
  kubectl apply -f "$K8S_DIR/shared/rabbitmq/rabbitmq.yaml"

  echo -n "  Esperando que RabbitMQ esté listo"
  kubectl rollout status deployment/rabbitmq -n vivaeventos --timeout=120s | \
    while IFS= read -r line; do echo -n "."; done
  echo ""
  log_ok "RabbitMQ listo"
}

apply_gateway() {
  if [[ "$SKIP_GATEWAY" == true ]]; then
    log_warn "Saltando API Gateway (--skip-gateway)"
    return
  fi

  log_step "Instalando Traefik (API Gateway)..."
  kubectl apply -f "$K8S_DIR/traefik/traefik.yaml"
  kubectl apply -f "$K8S_DIR/traefik/ingress.yaml"

  kubectl rollout status deployment/traefik -n vivaeventos --timeout=90s | \
    while IFS= read -r line; do echo -n "."; done
  echo ""
  log_ok "Traefik listo"
}

apply_services() {
  log_step "Desplegando microservicios: ${SERVICES_TO_DEPLOY[*]}"

  for svc in "${SERVICES_TO_DEPLOY[@]}"; do
    local manifest="$K8S_DIR/services/$svc/$svc.yaml"
    if [[ -f "$manifest" ]]; then
      echo -n "  Desplegando $svc..."
      kubectl apply -f "$manifest"
      echo -e " ${GREEN}✔${NC}"
    else
      log_warn "No se encontró manifest para $svc en $manifest"
    fi
  done

  log_step "Esperando que los pods estén Running..."
  for svc in "${SERVICES_TO_DEPLOY[@]}"; do
    echo -n "  $svc "
    kubectl rollout status deployment/"$svc" -n vivaeventos --timeout=180s 2>/dev/null | \
      while IFS= read -r line; do echo -n "."; done || \
      log_warn "$svc tardó demasiado (puede que aún esté arrancando)"
    echo ""
  done
}

print_summary() {
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  ✅  VivaEventos desplegado correctamente${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
  echo ""
  echo "  Pods en el namespace vivaeventos:"
  kubectl get pods -n vivaeventos --no-headers | \
    awk '{status=$3; icon="✔"; if(status!="Running") icon="⚠"; printf "    %s %-40s %s\n", icon, $1, status}'

  echo ""
  echo "  Servicios expuestos:"
  kubectl get svc -n vivaeventos --no-headers | \
    awk '{printf "    %-35s %s\n", $1, $5}'

  if [[ "$SKIP_GATEWAY" == false ]]; then
    echo ""
    local NODE_IP
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || \
              kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || \
              echo "localhost")
    local TRAEFIK_PORT
    TRAEFIK_PORT=$(kubectl get svc traefik -n vivaeventos -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}' 2>/dev/null || echo "80")

    echo "  API Gateway (Traefik):"
    echo "    http://$NODE_IP:$TRAEFIK_PORT/api/<servicio>/..."
    echo ""
    echo "  Dashboard Traefik:"
    local DASH_PORT
    DASH_PORT=$(kubectl get svc traefik -n vivaeventos -o jsonpath='{.spec.ports[?(@.name=="dashboard")].nodePort}' 2>/dev/null || echo "9000")
    echo "    http://$NODE_IP:$DASH_PORT/dashboard/"
  fi
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     VivaEventos — Deploy K8s              ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════╝${NC}"

check_prerequisites
apply_namespace
apply_secrets
apply_shared_infrastructure
apply_gateway
apply_services
print_summary
