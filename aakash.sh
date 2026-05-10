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

export SERVICE_URL=$(gcloud run services describe "$DATASET_SERVICE" \
  --region="$REGION" \
  --format='value(status.url)' 2>/dev/null)

[[ -z "$SERVICE_URL" ]] && fail "Could not fetch SERVICE_URL. Make sure Tasks 1-4 completed."
[[ ! -d "$FRONTEND_DIR" ]] && fail "Directory not found: $FRONTEND_DIR"

info "Project    : $PROJECT_ID"
info "Region     : $REGION"
info "SERVICE_URL: $SERVICE_URL"

# ════════════════════════════════════════════════════════════
# TASK 5 — STAGING FRONTEND (uses local demo data)
# ════════════════════════════════════════════════════════════
step "Task 5 — Deploy Staging Frontend"

info "Restoring original app.js for staging (demo data)..."
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

info "app.js first 4 lines:"
head -4 "$APP_JS"

# Delete stale image so fresh one is built
info "Removing stale staging image if exists..."
gcloud artifacts docker images delete \
  "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/frontend-staging:0.1" \
  --quiet 2>/dev/null || true

cd "$FRONTEND_DIR" || fail "Cannot cd to $FRONTEND_DIR"

info "Building frontend-staging:0.1..."
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/frontend-staging:0.1" \
  --quiet .

info "Deploying $STAGING_SERVICE..."
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
# TASK 6 — PRODUCTION FRONTEND (calls live REST API)
# ════════════════════════════════════════════════════════════
step "Task 6 — Deploy Production Frontend"

info "Writing production app.js with live API URL..."

# Write file using python3 to avoid ALL heredoc/quoting issues
python3 -c "
service_url = '${SERVICE_URL}'
app_js_path = '${APP_JS}'

content = (
    '// Title: GSP344 Challenge Lab\n'
    '// Author: Rich Rose\n'
    '\n'
    'const REST_API_SERVICE = \"' + service_url + '/2020\"\n'
    '//const REST_API_SERVICE = \"data/netflix.json\"\n'
    '\n'
    'function setTileData(items){\n'
    '  const dynamicView = items.map((item) => {\n'
    '    return \`<tr>\n'
    '        <td>\${item.title}</td>\n'
    '        <td>\${item.type}</td>\n'
    '        <td>\${item.rating}</td>\n'
    '        <td>\${item.director}</td>\n'
    '        <td>\${item.duration}</td>\n'
    '        <td>\${item.date_added}</td>\n'
    '      </tr>\`;\n'
    '  });\n'
    '  let header = \`<div class=\"table-wrapper\">\n'
    '    <table>\n'
    '      <thead>\n'
    '      <tr>\n'
    '        <th>Title</th>\n'
    '        <th>Type</th>\n'
    '        <th>Rating</th>\n'
    '        <th>Director</th>\n'
    '        <th>Duration</th>\n'
    '        <th>Date</th>\n'
    '      </thead><tbody>\`;\n'
    '  let footer = \`</tbody></table>\n'
    '\t\t</div>\`\n'
    '  return (header + dynamicView.join(\"\") + footer);\n'
    '}\n'
    '\n'
    'async function fetchLocalData(file) {\n'
    '  try {\n'
    '    const response = await(fetch(file));\n'
    '    const local = await response.json();\n'
    '    return local;\n'
    '  }\n'
    '  catch (error) {\n'
    '    console.log(\`Fetch: \${error}\`);\n'
    '  }\n'
    '}\n'
    '\n'
    'async function getPageInfo(){\n'
    '  const info = await fetchLocalData(REST_API_SERVICE)\n'
    '  htmlContent = document.querySelector(\"#info\");\n'
    '  htmlContent.innerHTML = setTileData(info.content);\n'
    '}\n'
    '\n'
    'window.addEventListener(\"load\", () => {\n'
    '  getPageInfo();\n'
    '});\n'
)

with open(app_js_path, 'w') as f:
    f.write(content)

print('app.js written OK')
"

info "app.js first 4 lines:"
head -4 "$APP_JS"

grep -q "$SERVICE_URL" "$APP_JS" || fail "SERVICE_URL not found in app.js — aborting."
success "app.js verified — REST_API_SERVICE points to live API"

# Delete stale image
info "Removing stale production image if exists..."
gcloud artifacts docker images delete \
  "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/frontend-production:0.1" \
  --quiet 2>/dev/null || true

cd "$FRONTEND_DIR" || fail "Cannot cd to $FRONTEND_DIR"

info "Building frontend-production:0.1..."
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/frontend-production:0.1" \
  --quiet .

info "Deploying $PRODUCTION_SERVICE..."
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