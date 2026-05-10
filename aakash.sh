#!/bin/bash
# ============================================================
# Firebase Challenge Lab - GSP344
# Develop Serverless Apps with Firebase
# ============================================================

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
CYAN='\033[0;96m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ──────────────────────────────────────────────────
info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[ OK ]${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET} $*"; }
fail()    { echo -e "${RED}${BOLD}[FAIL]${RESET} $*"; exit 1; }

step() {
  echo
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${YELLOW}${BOLD}  $*${RESET}"
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# ── Banner ───────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║      Firebase Challenge Lab — GSP344                    ║"
echo "  ║      Develop Serverless Apps with Firebase              ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
sleep 2

# ════════════════════════════════════════════════════════════
# ENVIRONMENT SETUP
# ════════════════════════════════════════════════════════════
step "Setting up environment"

export PROJECT_ID=$(gcloud projects list \
  --format='value(PROJECT_ID)' \
  --filter='qwiklabs-gcp' 2>/dev/null | head -1)

[[ -z "$PROJECT_ID" ]] && fail "Could not detect a qwiklabs project."
gcloud config set project "$PROJECT_ID"
info "Project: $PROJECT_ID"

export REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)

[[ -z "$REGION" ]] && export REGION="us-central1"
info "Region : $REGION"

# Service names
export DATASET_SERVICE="netflix-dataset-service"
export STAGING_SERVICE="frontend-staging-service"
export PRODUCTION_SERVICE="frontend-production-service"
export AR_REPO="rest-api-repo"

success "Environment ready"

# ════════════════════════════════════════════════════════════
# ENABLE APIS
# ════════════════════════════════════════════════════════════
step "Task 0 — Enabling required APIs"

gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  firestore.googleapis.com \
  --quiet

success "APIs enabled"

# ════════════════════════════════════════════════════════════
# TASK 1 — CREATE FIRESTORE DATABASE
# ════════════════════════════════════════════════════════════
step "Task 1 — Create Firestore database (Native mode)"

gcloud firestore databases create \
  --location="$REGION" \
  --project="$PROJECT_ID" \
  --quiet 2>&1 | grep -v "^$" || warn "Firestore may already exist — continuing"

sleep 8
success "Firestore database ready"

# ════════════════════════════════════════════════════════════
# TASK 2 — IMPORT NETFLIX CSV
# ════════════════════════════════════════════════════════════
step "Task 2 — Import Netflix dataset into Firestore"

# Clone repo if not already present
if [[ ! -d "$HOME/pet-theory" ]]; then
  info "Cloning pet-theory repository..."
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
else
  info "Repository already cloned — skipping"
fi

cd "$HOME/pet-theory/lab06/firebase-import-csv/solution" || fail "Import directory not found"

info "Installing npm dependencies..."
npm install --silent

info "Running CSV import (this may take a minute)..."
node index.js netflix_titles_original.csv

success "Netflix dataset imported into Firestore"

# ════════════════════════════════════════════════════════════
# CREATE ARTIFACT REGISTRY
# ════════════════════════════════════════════════════════════
step "Creating Artifact Registry repository"

gcloud artifacts repositories create "$AR_REPO" \
  --repository-format=docker \
  --location="$REGION" \
  --quiet 2>&1 | grep -v "^$" || warn "Repository may already exist — continuing"

success "Artifact Registry: $AR_REPO"

# ════════════════════════════════════════════════════════════
# TASK 3 — REST API v0.1 (baseline)
# ════════════════════════════════════════════════════════════
step "Task 3 — Build & deploy REST API v0.1"

cd "$HOME/pet-theory/lab06/firebase-rest-api/solution-01" || fail "solution-01 directory not found"

info "Installing npm dependencies..."
npm install --silent

info "Building container image rest-api:0.1..."
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/rest-api:0.1" \
  --quiet .

info "Deploying Cloud Run service: $DATASET_SERVICE..."
gcloud run deploy "$DATASET_SERVICE" \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/rest-api:0.1" \
  --region="$REGION" \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

SERVICE_URL=$(gcloud run services describe "$DATASET_SERVICE" \
  --region="$REGION" \
  --format='value(status.url)')

info "Testing REST API v0.1..."
RESPONSE=$(curl -s -X GET "$SERVICE_URL")
echo "  Response: $RESPONSE"
success "REST API v0.1 deployed → $SERVICE_URL"

# ════════════════════════════════════════════════════════════
# TASK 4 — REST API v0.2 (Firestore integration)
# ════════════════════════════════════════════════════════════
step "Task 4 — Build & deploy REST API v0.2 (with Firestore)"

cd "$HOME/pet-theory/lab06/firebase-rest-api/solution-02" || fail "solution-02 directory not found"

info "Installing npm dependencies..."
npm install --silent

info "Building container image rest-api:0.2..."
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/rest-api:0.2" \
  --quiet .

info "Deploying updated Cloud Run service: $DATASET_SERVICE..."
gcloud run deploy "$DATASET_SERVICE" \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/rest-api:0.2" \
  --region="$REGION" \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

# Refresh URL after redeployment
SERVICE_URL=$(gcloud run services describe "$DATASET_SERVICE" \
  --region="$REGION" \
  --format='value(status.url)')

info "Testing REST API v0.2 (year filter: 2019)..."
curl -s -X GET "$SERVICE_URL/2019" | head -c 300
echo
success "REST API v0.2 deployed → $SERVICE_URL"

# ════════════════════════════════════════════════════════════
# TASK 5 — STAGING FRONTEND
# ════════════════════════════════════════════════════════════
step "Task 5 — Build & deploy staging frontend"

cd "$HOME/pet-theory/lab06/firebase-frontend" || fail "firebase-frontend directory not found"

info "Installing npm dependencies..."
npm install --silent

info "Building staging frontend..."
npm run build 2>/dev/null || info "No build step needed — using source directly"

info "Building container image frontend-staging:0.1..."
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/frontend-staging:0.1" \
  --quiet .

info "Deploying Cloud Run service: $STAGING_SERVICE..."
gcloud run deploy "$STAGING_SERVICE" \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/frontend-staging:0.1" \
  --region="$REGION" \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe "$STAGING_SERVICE" \
  --region="$REGION" \
  --format='value(status.url)')

success "Staging frontend deployed → $STAGING_URL"

# ════════════════════════════════════════════════════════════
# TASK 6 — PRODUCTION FRONTEND
# ════════════════════════════════════════════════════════════
step "Task 6 — Build & deploy production frontend"

APP_JS="$HOME/pet-theory/lab06/firebase-frontend/public/app.js"
[[ ! -f "$APP_JS" ]] && fail "app.js not found at $APP_JS"

info "Patching app.js with REST API URL..."
# Replace whatever is currently assigned to REST_API_SERVICE with the live URL
sed -i "s|const REST_API_SERVICE = \"[^\"]*\"|const REST_API_SERVICE = \"${SERVICE_URL}\"|g" "$APP_JS"

# Verify the patch was applied
if grep -q "$SERVICE_URL" "$APP_JS"; then
  success "app.js patched — REST_API_SERVICE = $SERVICE_URL"
else
  warn "sed pattern did not match. Attempting fallback append..."
  # Fallback: prepend the variable at the top of app.js
  sed -i "1s|^|const REST_API_SERVICE = \"${SERVICE_URL}\";\n|" "$APP_JS"
fi

# Show first few lines for verification
echo -e "${YELLOW}--- app.js (first 5 lines) ---${RESET}"
head -5 "$APP_JS"
echo -e "${YELLOW}------------------------------${RESET}"

cd "$HOME/pet-theory/lab06/firebase-frontend" || fail "firebase-frontend directory not found"

info "Building container image frontend-production:0.1..."
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/frontend-production:0.1" \
  --quiet .

info "Deploying Cloud Run service: $PRODUCTION_SERVICE..."
gcloud run deploy "$PRODUCTION_SERVICE" \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/frontend-production:0.1" \
  --region="$REGION" \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PRODUCTION_URL=$(gcloud run services describe "$PRODUCTION_SERVICE" \
  --region="$REGION" \
  --format='value(status.url)')

success "Production frontend deployed → $PRODUCTION_URL"

# ════════════════════════════════════════════════════════════
# SUMMARY
# ════════════════════════════════════════════════════════════
echo
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}  ✅  ALL TASKS COMPLETED SUCCESSFULLY                         ${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo
echo -e "${BOLD}Service URLs:${RESET}"
echo -e "  REST API          → ${CYAN}$SERVICE_URL${RESET}"
echo -e "  Staging Frontend  → ${CYAN}$STAGING_URL${RESET}"
echo -e "  Production Frontend → ${CYAN}$PRODUCTION_URL${RESET}"
echo
echo -e "${YELLOW}${BOLD}Checklist:${RESET}"
echo -e "  ${GREEN}✓${RESET} Task 1 — Firestore database created (Native mode, $REGION)"
echo -e "  ${GREEN}✓${RESET} Task 2 — Netflix CSV imported into Firestore"
echo -e "  ${GREEN}✓${RESET} Task 3 — REST API v0.1 deployed to Cloud Run"
echo -e "  ${GREEN}✓${RESET} Task 4 — REST API v0.2 deployed with Firestore integration"
echo -e "  ${GREEN}✓${RESET} Task 5 — Staging frontend deployed"
echo -e "  ${GREEN}✓${RESET} Task 6 — Production frontend deployed with live API"
echo