#!/bin/bash
# ============================================================
# Firebase Challenge Lab — Task 5 & 6 Fix
# ============================================================

RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
CYAN='\033[0;96m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[ OK ]${RESET} $*"; }
fail()    { echo -e "${RED}${BOLD}[FAIL]${RESET} $*"; exit 1; }

step() {
  echo
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${YELLOW}${BOLD}  $*${RESET}"
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# ── Resolve project & region ─────────────────────────────────
export PROJECT_ID=$(gcloud config get-value project)
export REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)
[[ -z "$REGION" ]] && export REGION="us-central1"

export AR_REPO="rest-api-repo"
export DATASET_SERVICE="netflix-dataset-service"
export STAGING_SERVICE="frontend-staging-service"
export PRODUCTION_SERVICE="frontend-production-service"

# ── Get the live REST API URL from already-deployed service ──
export SERVICE_URL=$(gcloud run services describe "$DATASET_SERVICE" \
  --region="$REGION" \
  --format='value(status.url)' 2>/dev/null)

[[ -z "$SERVICE_URL" ]] && fail "Could not fetch SERVICE_URL from $DATASET_SERVICE. Make sure Tasks 1-4 completed successfully."

info "Project    : $PROJECT_ID"
info "Region     : $REGION"
info "SERVICE_URL: $SERVICE_URL"

# ════════════════════════════════════════════════════════════
# TASK 5 — STAGING FRONTEND
# ════════════════════════════════════════════════════════════
step "Task 5 — Deploy Staging Frontend"

cd "$HOME/pet-theory/lab06/firebase-frontend" || fail "Directory not found: firebase-frontend"

info "Building container image frontend-staging:0.1 via Cloud Build..."
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
step "Task 6 — Update app.js and Deploy Production Frontend"

APP_JS="$HOME/pet-theory/lab06/firebase-frontend/public/app.js"
[[ ! -f "$APP_JS" ]] && fail "app.js not found at $APP_JS"

info "Current app.js content (before patch):"
echo -e "${YELLOW}"
cat "$APP_JS"
echo -e "${RESET}"

# The lab requires the year to be appended to SERVICE_URL
# app.js calls the REST API as: SERVICE_URL + "/" + selectedYear
# We must set REST_API_SERVICE to the base URL (year is appended by app.js at runtime)

info "Patching app.js — setting REST_API_SERVICE to: $SERVICE_URL"

# Strategy: find the line containing REST_API_SERVICE and replace the whole line
if grep -q "REST_API_SERVICE" "$APP_JS"; then
  # Replace the entire assignment line regardless of current value
  sed -i "s|.*REST_API_SERVICE.*|const REST_API_SERVICE = \"${SERVICE_URL}\";|g" "$APP_JS"
  success "Replaced existing REST_API_SERVICE line"
else
  # Variable doesn't exist yet — insert at top of file
  sed -i "1s|^|const REST_API_SERVICE = \"${SERVICE_URL}\";\n|" "$APP_JS"
  success "Inserted REST_API_SERVICE at top of app.js"
fi

info "Updated app.js content (after patch):"
echo -e "${YELLOW}"
cat "$APP_JS"
echo -e "${RESET}"

# Confirm the URL is actually in the file
if ! grep -q "$SERVICE_URL" "$APP_JS"; then
  fail "Patch verification failed — SERVICE_URL not found in app.js"
fi

# ── Build production image from firebase-frontend (contains patched public/app.js) ──
cd "$HOME/pet-theory/lab06/firebase-frontend" || fail "Directory not found: firebase-frontend"

info "Building container image frontend-production:0.1 via Cloud Build..."
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
echo -e "${GREEN}${BOLD}  ✅  TASKS 5 & 6 COMPLETED                                    ${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo
echo -e "${BOLD}Deployed Services:${RESET}"
echo -e "  REST API (v0.2)       → ${CYAN}$SERVICE_URL${RESET}"
echo -e "  Staging  Frontend     → ${CYAN}$STAGING_URL${RESET}"
echo -e "  Production Frontend   → ${CYAN}$PRODUCTION_URL${RESET}"
echo
echo -e "${YELLOW}${BOLD}Verify Task 6 is working:${RESET}"
echo -e "  Open → ${CYAN}$PRODUCTION_URL${RESET}"
echo -e "  You should see Netflix titles filtered by release year from Firestore."
echo
