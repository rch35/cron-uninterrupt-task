#!/bin/bash

# ============================================================================
# Google Cloud Deployment Script for Cron Job
# ============================================================================
# This script automates the deployment of a containerized cron job to GCP:
# - Creates Artifact Registry repository if needed
# - Builds and pushes Docker image
# - Creates/updates Cloud Run Job
# - Sets up Cloud Scheduler to run every hour
# ============================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Configuration Variables (can be overridden via environment variables)
# ============================================================================

PROJECT_ID="${GCP_PROJECT_ID:-}"
REGION="${GCP_REGION:-us-central1}"
REPOSITORY_NAME="${ARTIFACT_REGISTRY_REPO:-cron-jobs}"
IMAGE_NAME="${IMAGE_NAME:-cron-uninterrupt-task}"
JOB_NAME="${CLOUD_RUN_JOB_NAME:-cron-uninterrupt-task}"
SCHEDULER_NAME="${SCHEDULER_NAME:-cron-uninterrupt-task-hourly}"
API_ENDPOINT="${API_ENDPOINT:-https://cloud.blackbox.ai/api/cron/resume-stalled}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-}"

# Cloud Run Job Configuration
MEMORY="${MEMORY:-512Mi}"
CPU="${CPU:-1}"
TIMEOUT="${TIMEOUT:-300s}"
MAX_RETRIES="${MAX_RETRIES:-3}"

# Cloud Scheduler Configuration
SCHEDULE="${SCHEDULE:-0 * * * *}"  # Every hour at minute 0
TIMEZONE="${TIMEZONE:-America/Los_Angeles}"

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# ============================================================================
# Validation Functions
# ============================================================================

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    print_success "gcloud CLI is installed"
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install it from: https://docs.docker.com/get-docker/"
        exit 1
    fi
    print_success "Docker is installed"
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        print_error "Not authenticated with gcloud. Please run: gcloud auth login"
        exit 1
    fi
    print_success "Authenticated with gcloud"
}

get_project_id() {
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [ -z "$PROJECT_ID" ]; then
            print_error "No GCP project set. Please run: gcloud config set project YOUR_PROJECT_ID"
            exit 1
        fi
        print_info "Using project: $PROJECT_ID"
    else
        print_info "Using specified project: $PROJECT_ID"
    fi
}

enable_required_apis() {
    print_header "Enabling Required APIs"
    
    local apis=(
        "artifactregistry.googleapis.com"
        "run.googleapis.com"
        "cloudscheduler.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        print_info "Enabling $api..."
        gcloud services enable "$api" --project="$PROJECT_ID" 2>/dev/null || true
    done
    
    print_success "Required APIs enabled"
    sleep 2  # Wait for APIs to propagate
}

# ============================================================================
# Artifact Registry Functions
# ============================================================================

setup_artifact_registry() {
    print_header "Setting up Artifact Registry"
    
    # Check if repository exists
    if gcloud artifacts repositories describe "$REPOSITORY_NAME" \
        --location="$REGION" \
        --project="$PROJECT_ID" &>/dev/null; then
        print_success "Artifact Registry repository '$REPOSITORY_NAME' already exists"
    else
        print_info "Creating Artifact Registry repository '$REPOSITORY_NAME'..."
        gcloud artifacts repositories create "$REPOSITORY_NAME" \
            --repository-format=docker \
            --location="$REGION" \
            --description="Docker repository for cron jobs" \
            --project="$PROJECT_ID"
        print_success "Artifact Registry repository created"
    fi
    
    # Configure Docker authentication
    print_info "Configuring Docker authentication..."
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
    print_success "Docker authentication configured"
}

# ============================================================================
# Docker Functions
# ============================================================================

build_and_push_image() {
    {
        print_header "Building and Pushing Docker Image"
        
        local image_tag="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}/${IMAGE_NAME}:latest"
        local image_tag_timestamp="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}/${IMAGE_NAME}:$(date +%Y%m%d-%H%M%S)"
        
        print_info "Building Docker image for linux/amd64 platform..."
        if docker build --platform linux/amd64 -t "$image_tag" -t "$image_tag_timestamp" . ; then
            print_success "Docker image built successfully"
        else
            print_error "Failed to build Docker image"
            exit 1
        fi
        
        print_info "Pushing image with tag 'latest' to Artifact Registry..."
        if docker push "$image_tag" ; then
            print_success "Image with tag 'latest' pushed successfully"
        else
            print_error "Failed to push image with tag 'latest'"
            exit 1
        fi
        
        print_info "Pushing image with timestamp tag to Artifact Registry..."
        if docker push "$image_tag_timestamp" ; then
            print_success "Image with timestamp tag pushed successfully"
        else
            print_error "Failed to push image with timestamp tag"
            exit 1
        fi
    } >&2
    
    echo "$image_tag"
}

# ============================================================================
# Cloud Run Job Functions
# ============================================================================

deploy_cloud_run_job() {
    local image_url=$1
    print_header "Deploying Cloud Run Job"
    
    print_info "Creating/updating Cloud Run Job '$JOB_NAME' in region '$REGION'..."
    
    # Build the command with all parameters
    if [ -n "$SERVICE_ACCOUNT" ]; then
        gcloud run jobs deploy "$JOB_NAME" \
            --image="$image_url" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --set-env-vars="API_ENDPOINT=$API_ENDPOINT" \
            --service-account="$SERVICE_ACCOUNT"
            # disable initial cpu and memory configurations by script
            # --memory="$MEMORY" \
            # --cpu="$CPU" \
            # --max-retries="$MAX_RETRIES" \
            # --task-timeout="$TIMEOUT" \            
    else
        gcloud run jobs deploy "$JOB_NAME" \
            --image="$image_url" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --set-env-vars="API_ENDPOINT=$API_ENDPOINT"
            # disable initial cpu and memory configurations by script
            # --memory="$MEMORY" \
            # --cpu="$CPU" \
            # --max-retries="$MAX_RETRIES" \
            # --task-timeout="$TIMEOUT" \
    fi
    
    print_success "Cloud Run Job deployed successfully"
}

# ============================================================================
# Cloud Scheduler Functions
# ============================================================================

setup_cloud_scheduler() {
    print_header "Setting up Cloud Scheduler"
    
    # Check if App Engine app exists (required for Cloud Scheduler in some regions)
    if ! gcloud app describe --project="$PROJECT_ID" &>/dev/null; then
        print_warning "App Engine app not found. Cloud Scheduler requires an App Engine app."
        print_info "Creating App Engine app in region $REGION..."
        gcloud app create --region="$REGION" --project="$PROJECT_ID" 2>/dev/null || true
    fi
    
    # Get the Cloud Run Job URI
    local job_uri="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${JOB_NAME}:run"
    
    # Check if scheduler job exists
    if gcloud scheduler jobs describe "$SCHEDULER_NAME" \
        --location="$REGION" \
        --project="$PROJECT_ID" &>/dev/null; then
        print_info "Updating existing Cloud Scheduler job..."
        gcloud scheduler jobs update http "$SCHEDULER_NAME" \
            --location="$REGION" \
            --project="$PROJECT_ID" \
            --schedule="$SCHEDULE" \
            --uri="$job_uri" \
            --http-method=POST \
            --oauth-service-account-email="${SERVICE_ACCOUNT:-${PROJECT_ID}@appspot.gserviceaccount.com}" \
            --time-zone="$TIMEZONE"
        print_success "Cloud Scheduler job updated"
    else
        print_info "Creating Cloud Scheduler job..."
        gcloud scheduler jobs create http "$SCHEDULER_NAME" \
            --location="$REGION" \
            --project="$PROJECT_ID" \
            --schedule="$SCHEDULE" \
            --uri="$job_uri" \
            --http-method=POST \
            --oauth-service-account-email="${SERVICE_ACCOUNT:-${PROJECT_ID}@appspot.gserviceaccount.com}" \
            --time-zone="$TIMEZONE" \
            --description="Hourly trigger for $JOB_NAME"
        print_success "Cloud Scheduler job created"
    fi
}

# ============================================================================
# Main Deployment Flow
# ============================================================================

print_deployment_summary() {
    print_header "Deployment Summary"
    echo -e "${GREEN}Deployment completed successfully!${NC}\n"
    echo -e "📦 ${BLUE}Project:${NC} $PROJECT_ID"
    echo -e "🌍 ${BLUE}Region:${NC} $REGION"
    echo -e "📁 ${BLUE}Artifact Registry:${NC} $REPOSITORY_NAME"
    echo -e "🐳 ${BLUE}Image:${NC} $IMAGE_NAME"
    echo -e "⚙️  ${BLUE}Cloud Run Job:${NC} $JOB_NAME"
    echo -e "⏰ ${BLUE}Scheduler:${NC} $SCHEDULER_NAME"
    echo -e "📅 ${BLUE}Schedule:${NC} $SCHEDULE ($TIMEZONE)"
    echo -e "🔗 ${BLUE}API Endpoint:${NC} $API_ENDPOINT"
    echo ""
    echo -e "${YELLOW}Useful Commands:${NC}"
    echo -e "  View job details:    ${BLUE}gcloud run jobs describe $JOB_NAME --region=$REGION${NC}"
    echo -e "  Execute job now:     ${BLUE}gcloud run jobs execute $JOB_NAME --region=$REGION${NC}"
    echo -e "  View job logs:       ${BLUE}gcloud logging read \"resource.type=cloud_run_job AND resource.labels.job_name=$JOB_NAME\" --limit=50 --format=json${NC}"
    echo -e "  View scheduler:      ${BLUE}gcloud scheduler jobs describe $SCHEDULER_NAME --location=$REGION${NC}"
    echo -e "  Trigger scheduler:   ${BLUE}gcloud scheduler jobs run $SCHEDULER_NAME --location=$REGION${NC}"
    echo ""
}

main() {
    print_header "Starting Deployment Process"
    
    # Run all deployment steps
    check_prerequisites
    get_project_id
    enable_required_apis
    setup_artifact_registry
    
    local image_url
    image_url=$(build_and_push_image)
    
    deploy_cloud_run_job "$image_url"
    setup_cloud_scheduler
    
    print_deployment_summary
}

# ============================================================================
# Script Entry Point
# ============================================================================

# Show usage if --help is passed
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    cat << EOF
Usage: ./deploy.sh [OPTIONS]

Deploys a containerized cron job to Google Cloud Platform.

Environment Variables (optional):
  GCP_PROJECT_ID              GCP project ID (default: current gcloud project)
  GCP_REGION                  GCP region (default: us-central1)
  ARTIFACT_REGISTRY_REPO      Artifact Registry repository name (default: cron-jobs)
  IMAGE_NAME                  Docker image name (default: cron-uninterrupt-task)
  CLOUD_RUN_JOB_NAME          Cloud Run Job name (default: cron-uninterrupt-task)
  SCHEDULER_NAME              Cloud Scheduler job name (default: cron-uninterrupt-task-hourly)
  API_ENDPOINT                API endpoint URL (default: https://cloud.blackbox.ai/api/cron/resume-stalled)
  SERVICE_ACCOUNT             Service account email (optional)
  MEMORY                      Memory allocation (default: 512Mi)
  CPU                         CPU allocation (default: 1)
  TIMEOUT                     Job timeout (default: 300s)
  MAX_RETRIES                 Max retry attempts (default: 3)
  SCHEDULE                    Cron schedule (default: 0 * * * *)
  TIMEZONE                    Timezone (default: America/Los_Angeles)

Examples:
  # Deploy with defaults
  ./deploy.sh

  # Deploy to specific project and region
  GCP_PROJECT_ID=my-project GCP_REGION=us-east1 ./deploy.sh

  # Deploy with custom API endpoint
  API_ENDPOINT=https://api.example.com/cron ./deploy.sh

  # Deploy with custom schedule (every 30 minutes)
  SCHEDULE="*/30 * * * *" ./deploy.sh

EOF
    exit 0
fi

# Run main deployment
main
