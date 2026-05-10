#!/bin/bash
# ============================================================
# Firebase Challenge Lab — Task 5 & 6 (Complete Fix)
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

# ── Environment ──────────────────────────────────────────────
export PROJECT_ID=$(gcloud config get-value project)
export REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)
[[ -z "$REGION" ]] && export REGION="us-central1"

export AR_REPO="rest-api-repo"
export DATASET_SERVICE="netflix-dataset-service"
export STAGING_SERVICE="frontend-staging-service"
export PRODUCTION_SERVICE="frontend-production-service"
export FRONTEND_DIR="$HOME/pet-theory/lab06/firebase-frontend"
export APP_JS="$FRONTEND_DIR/public/app.js"

# Get the live REST API URL from already-deployed service
export SERVICE_URL=$(gcloud run services describe "$DATASET_SERVICE" \
  --region="$REGION" \
  --format='value(status.url)' 2>/dev/null)

[[ -z "$SERVICE_URL" ]] && fail "Could not fetch SERVICE_URL. Make sure Tasks 1-4 completed."
[[ ! -d "$FRONTEND_DIR" ]] && fail "Directory not found: $FRONTEND_DIR"

info "Project    : $PROJECT_ID"
info "Region     : $REGION"
info "SERVICE_URL: $SERVICE_URL"

# ════════════════════════════════════════════════════════════
# TASK 5 — STAGING FRONTEND
# Must use original app.js with demo data (data/netflix.json)
# ════════════════════════════════════════════════════════════
step "Task 5 — Deploy Staging Frontend (demo data)"

info "Writing staging app.js (demo dataset)..."
cat > "$APP_JS" << 'STAGINGJS'
// Title: GSP344 Challenge Lab
// Author: Rich Rose

const REST_API_SERVICE = "data/netflix.json"
//const REST_API_SERVICE = "https://XXXX-SERVICE.run.app/2020" 

function setTileData(items){
  const dynamicView = items.map((item) => {
    return `<tr>
        <td>${item.title}</td>
        <td>${item.type}</td>
        <td>${item.rating}</td>
        <td>${item.director}</td>
        <td>${item.duration}</td>
        <td>${item.date_added}</td>
      </tr>`;
  });
  let header = `<div class="table-wrapper">
    <table>
      <thead>
      <tr>
        <th>Title</th>
        <th>Type</th>
        <th>Rating</th>
        <th>Director</th>
        <th>Duration</th>
        <th>Date</th>
      </thead><tbody>`;
  let footer = `</tbody></table>
		</div>`
  return (header + dynamicView.join("") + footer);  
}

async function fetchLocalData(file) {
  try {
    const response = await(fetch(file));
    const local = await response.json();
    return local;
  }
  catch (error) {
    console.log(`Fetch: ${error}`);
  }
}

async function getPageInfo(){
  const info = await fetchLocalData(REST_API_SERVICE)
  htmlContent = document.querySelector('#info');
  htmlContent.innerHTML = setTileData(info.content);
}

window.addEventListener('load', () => {
  getPageInfo();
});
STAGINGJS

success "app.js written for staging"

cd "$FRONTEND_DIR" || fail "Cannot cd to $FRONTEND_DIR"

info "Building frontend-staging:0.1 via Cloud Build..."
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

success "Task 5 done → $STAGING_URL"

# ════════════════════════════════════════════════════════════
# TASK 6 — PRODUCTION FRONTEND
# Update REST_API_SERVICE to live API URL with year appended
# The original commented line shows: SERVICE_URL/2020
# ════════════════════════════════════════════════════════════
step "Task 6 — Update app.js and Deploy Production Frontend"

info "Writing production app.js (live Firestore API)..."

# Use printf to avoid heredoc variable expansion issues
printf '%s\n' \
'// Title: GSP344 Challenge Lab' \
'// Author: Rich Rose' \
'' \
"const REST_API_SERVICE = \"${SERVICE_URL}/2020\"" \
'//const REST_API_SERVICE = "data/netflix.json"' \
'' \
'function setTileData(items){' \
'  const dynamicView = items.map((item) => {' \
'    return `<tr>' \
'        <td>${item.title}</td>' \
'        <td>${item.type}</td>' \
'        <td>${item.rating}</td>' \
'        <td>${item.director}</td>' \
'        <td>${item.duration}</td>' \
'        <td>${item.date_added}</td>' \
'      </tr>`;' \
'  });' \
'  let header = `<div class="table-wrapper">' \
'    <table>' \
'      <thead>' \
'      <tr>' \
'        <th>Title</th>' \
'        <th>Type</th>' \
'        <th>Rating</th>' \
'        <th>Director</th>' \
'        <th>Duration</th>' \
'        <th>Date</th>' \
'      </thead><tbody>`;' \
'  let footer = `</tbody></table>' \
'		</div>`' \
'  return (header + dynamicView.join("") + footer);' \
'}' \
'' \
'async function fetchLocalData(file) {' \
'  try {' \
'    const response = await(fetch(file));' \
'    const local = await response.json();' \
'    return local;' \
'  }' \
'  catch (error) {' \
'    console.log(`Fetch: ${error}`);' \
'  }' \
'}' \
'' \
'async function getPageInfo(){' \
'  const info = await fetchLocalData(REST_API_SERVICE)' \
'  htmlContent = document.querySelector(`#info`);' \
'  htmlContent.innerHTML = setTileData(info.content);' \
'}' \
'' \
'window.addEventListener(`load`, () => {' \
'  getPageInfo();' \
'});' \
> "$APP_JS"

info "First 5 lines of production app.js:"
echo -e "${YELLOW}"
head -5 "$APP_JS"
echo -e "${RESET}"

grep -q "$SERVICE_URL" "$APP_JS" || fail "SERVICE_URL not written to app.js correctly."
success "app.js verified — REST_API_SERVICE = ${SERVICE_URL}/2020"

cd "$FRONTEND_DIR" || fail "Cannot cd to $FRONTEND_DIR"

info "Building frontend-production:0.1 via Cloud Build..."
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

success "Task 6 done → $PRODUCTION_URL"

# ════════════════════════════════════════════════════════════
# SUMMARY
# ════════════════════════════════════════════════════════════
echo
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}  ✅  TASKS 5 & 6 COMPLETED SUCCESSFULLY                       ${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo
echo -e "${BOLD}Service URLs:${RESET}"
echo -e "  REST API            → ${CYAN}$SERVICE_URL${RESET}"
echo -e "  Staging  Frontend   → ${CYAN}$STAGING_URL${RESET}"
echo -e "  Production Frontend → ${CYAN}$PRODUCTION_URL${RESET}"
echo