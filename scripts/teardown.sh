#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  teardown.sh — Eliminar toda la infraestructura de VivaEventos del cluster
#
#  USO:
#    ./scripts/teardown.sh              # Elimina todo (mantiene PVCs)
#    ./scripts/teardown.sh --full       # Elimina todo incluyendo datos (PVCs)
#    ./scripts/teardown.sh --only user-service   # Solo ese servicio
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="$ROOT_DIR/k8s"

FULL_WIPE=false
ONLY_SERVICES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full)   FULL_WIPE=true; shift ;;
    --only)   shift; while [[ $# -gt 0 && "$1" != --* ]]; do ONLY_SERVICES+=("$1"); shift; done ;;
    *)        echo -e "${RED}Opción desconocida: $1${NC}"; exit 1 ;;
  esac
done

log_step() { echo -e "\n${BLUE}▶ $1${NC}"; }
log_ok()   { echo -e "  ${GREEN}✔ $1${NC}"; }
log_warn() { echo -e "  ${YELLOW}⚠ $1${NC}"; }

ALL_SERVICES=(user-service event-service order-service payment-service
              notification-service ticket-service dashboard-service)

SERVICES_TO_REMOVE=("${ONLY_SERVICES[@]:-${ALL_SERVICES[@]}}")

echo ""
echo -e "${RED}╔══════════════════════════════════════════╗${NC}"
echo -e "${RED}║   VivaEventos — Teardown K8s             ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════╝${NC}"
echo ""

if [[ "$FULL_WIPE" == true ]]; then
  log_warn "Modo --full: se eliminarán los PVCs y se perderán los datos de las BBDDs."
fi

read -rp "  ¿Estás seguro? (escribe 'si' para continuar): " CONFIRM
[[ "$CONFIRM" != "si" ]] && { echo "Cancelado."; exit 0; }

if [[ ${#ONLY_SERVICES[@]} -eq 0 ]]; then
  log_step "Eliminando Traefik..."
  kubectl delete -f "$K8S_DIR/traefik/ingress.yaml" --ignore-not-found
  kubectl delete -f "$K8S_DIR/traefik/traefik.yaml" --ignore-not-found
  log_ok "Traefik eliminado"
fi

log_step "Eliminando microservicios..."
for svc in "${SERVICES_TO_REMOVE[@]}"; do
  manifest="$K8S_DIR/services/$svc/$svc.yaml"
  if [[ -f "$manifest" ]]; then
    kubectl delete -f "$manifest" --ignore-not-found
    log_ok "$svc eliminado"
  fi
done

if [[ ${#ONLY_SERVICES[@]} -eq 0 ]]; then
  log_step "Eliminando infraestructura compartida (RabbitMQ)..."
  kubectl delete -f "$K8S_DIR/shared/rabbitmq/rabbitmq.yaml" --ignore-not-found
  log_ok "RabbitMQ eliminado"
fi

if [[ "$FULL_WIPE" == true ]]; then
  log_step "Eliminando PVCs (datos de BBDDs)..."
  kubectl delete pvc --all -n vivaeventos --ignore-not-found
  log_ok "PVCs eliminados"

  log_step "Eliminando secretos..."
  kubectl delete -f "$K8S_DIR/secrets/secrets.yaml" --ignore-not-found
  log_ok "Secretos eliminados"

  log_step "Eliminando namespace..."
  kubectl delete -f "$K8S_DIR/namespace/namespace.yaml" --ignore-not-found
  log_ok "Namespace eliminado"
fi

echo ""
echo -e "${GREEN}✅ Teardown completado.${NC}"
[[ "$FULL_WIPE" == false ]] && log_warn "Los PVCs (datos) se mantuvieron. Usa --full para eliminarlos."
