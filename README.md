# vivaeventos-infra

Repositorio central de infraestructura para el proyecto **VivaEventos**. Contiene todos los manifests de Kubernetes para levantar los 7 microservicios, la infraestructura compartida y el API Gateway con **un solo comando**.

---

## 📋 Requisitos previos

Instala las siguientes herramientas antes de comenzar:

| Herramienta | Instalación |
|-------------|-------------|
| Docker | https://docs.docker.com/get-docker/ |
| Minikube | https://minikube.sigs.k8s.io/docs/start/ |
| kubectl | https://kubernetes.io/docs/tasks/tools/ |

---

## 🚀 Guía de despliegue paso a paso

### Paso 1 — Clonar el repositorio

```bash
git clone https://github.com/tu-org/vivaeventos-infra.git
cd vivaeventos-infra
```

### Paso 2 — Iniciar Minikube

```bash
minikube start --driver=docker --memory=3900 --cpus=2
```

Verifica que esté corriendo:
```bash
kubectl get nodes
# Debe aparecer un nodo con STATUS: Ready
```

### Paso 3 — Obtener la IP del cluster

```bash
minikube ip
# Anota esta IP, la necesitarás en el siguiente paso
# Ejemplo: 192.168.49.2
```

### Paso 4 — Crear el archivo de secretos

```bash
cp k8s/secrets/secrets.template.yaml k8s/secrets/secrets.yaml
```

⚠️ **Este archivo NUNCA se sube a Git.** Ya está en el `.gitignore`.

Ahora completa los valores en `secrets.yaml`. Para cada valor necesitas codificarlo en base64:

```bash
echo -n "mi_valor" | base64
```

#### Secretos que debes completar:

**RabbitMQ** (puedes usar `guest` para desarrollo):
```bash
echo -n "guest" | base64   # → Z3Vlc3Q=
```

**JWT Secret** (usa el mismo de los repos de los servicios):
```bash
echo -n "aVerySecretKeyThatIsAtLeast256BitsLongAndShouldBeStoredSecurely" | base64
```

**Bases de datos** (usa `postgres` y `1234` para desarrollo):
```bash
echo -n "postgres" | base64   # usuario
echo -n "1234" | base64       # password
```

**URLs de Stripe** (reemplaza `TU_MINIKUBE_IP` con el resultado del Paso 3):
```bash
MINIKUBE_IP=$(minikube ip)

echo -n "http://$MINIKUBE_IP/api/payments/api/v1/payments/callback/success?session_id={CHECKOUT_SESSION_ID}" | base64

echo -n "http://$MINIKUBE_IP/api/payments/api/v1/payments/callback/cancel" | base64

echo -n "http://$MINIKUBE_IP/pago.html?session_id={CHECKOUT_SESSION_ID}" | base64

echo -n "http://$MINIKUBE_IP/pago.html?cancelled=true" | base64
```

**Stripe keys** (pídelas al equipo — son las keys de test del dashboard de Stripe):
```bash
echo -n "sk_test_..." | base64
echo -n "pk_test_..." | base64
```

**Email/SMTP** (para el notification-service — pídelas al equipo):
```bash
echo -n "smtp.gmail.com" | base64
echo -n "587" | base64
echo -n "tu_email@gmail.com" | base64
echo -n "tu_app_password" | base64
```

### Paso 5 — Dar permisos a los scripts

```bash
chmod +x scripts/deploy.sh scripts/teardown.sh
```

### Paso 6 — ¡Desplegar todo!

```bash
./scripts/deploy.sh
```

El script levanta todo en orden: namespace → secrets → RabbitMQ → Traefik → 7 microservicios + frontend.

### Paso 7 — Habilitar el Ingress de Minikube

```bash
minikube addons enable ingress
```

Espera 1 minuto y aplica el clase del ingress:
```bash
kubectl patch ingress vivaeventos-frontend-ingress -n vivaeventos -p '{"spec":{"ingressClassName":"nginx"}}'
kubectl patch ingress vivaeventos-api-ingress -n vivaeventos -p '{"spec":{"ingressClassName":"nginx"}}'
```


### Paso 8 — Abrir la aplicación

```bash
# Obtén la IP
minikube ip

# Abre en el navegador:
http://<MINIKUBE_IP>
```

---

## 🔄 Comandos útiles del día a día

```bash
# Ver estado de todos los pods
kubectl get pods -n vivaeventos

# Ver logs de un servicio
kubectl logs deployment/user-service -n vivaeventos -f

# Reiniciar un servicio (después de actualizar la imagen)
kubectl rollout restart deployment/user-service -n vivaeventos

# Bajar todo (mantiene los datos)
./scripts/teardown.sh

# Bajar todo incluyendo datos de las BDs
./scripts/teardown.sh --full
```

---

## 🗂️ Estructura del repositorio

```
vivaeventos-infra/
├── k8s/
│   ├── namespace/
│   │   └── namespace.yaml
│   ├── traefik/
│   │   ├── traefik.yaml
│   │   └── ingress.yaml
│   ├── shared/
│   │   └── rabbitmq/
│   │       └── rabbitmq.yaml
│   ├── services/
│   │   ├── user-service/
│   │   ├── event-service/
│   │   ├── order-service/
│   │   ├── payment-service/
│   │   ├── notification-service/
│   │   ├── ticket-service/
│   │   ├── dashboard-service/
│   │   └── frontend/
│   └── secrets/
│       └── secrets.template.yaml   # Plantilla — nunca subir secrets.yaml
├── scripts/
│   ├── deploy.sh                   # 🚀 Deploy completo
│   └── teardown.sh                 # Eliminar infraestructura
└── README.md
```

---

## 🌐 Microservicios y rutas

| Servicio | Puerto | Ruta API Gateway |
|---------|--------|-----------------|
| frontend | 80 | `/` |
| user-service | 8080 | `/api/users/**` |
| event-service | 8082 | `/api/events/**` |
| order-service | 8083 | `/api/orders/**` |
| payment-service | 8084 | `/api/payments/**` |
| notification-service | 8085 | `/api/notifications/**` |
| ticket-service | 8086 | `/api/tickets/**` |
| dashboard-service | 8087 | `/api/dashboard/**` |

---

## 🔑 Roles de usuario

Para crear usuarios con distintos roles desde Postman:

**POST** `http://<MINIKUBE_IP>/api/users/auth/register`
```json
{
  "name": "Gerente",
  "email": "gerente@test.com",
  "password": "1234",
  "role": "GERENTE"
}
```

Roles disponibles: `CLIENTE`, `GERENTE`, `ORGANIZADOR`

Luego hacer login en **POST** `http://<MINIKUBE_IP>/api/users/auth/login` para obtener el JWT token.
Tambien puede iniciar sesion desde el front con el email y password que ya le pasó a postman

---

## ⚠️ Notas importantes

- El archivo `k8s/secrets/secrets.yaml` **nunca** se sube a Git
- Las URLs de Stripe dependen de tu IP de Minikube — cada desarrollador debe generarlas con su propia IP
- Los datos de las BDs se pierden si haces `minikube stop` y `minikube delete` — usa `seed-data.sql` para restaurarlos
- Si reinicias Minikube, puede cambiar la IP — regenera las URLs de Stripe y actualiza el secret
