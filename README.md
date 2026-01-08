# Cron Self Code - Hourly API Caller

A Node.js application that calls an API endpoint every hour with a frequency parameter based on the current hour's divisibility.

## Frequency Logic

The application determines the frequency parameter based on which number the current hour is divisible by (in priority order):

- **24x**: Hour is divisible by 24 (midnight only - hour 0)
- **12x**: Hour is divisible by 12 (hours 0, 12)
- **6x**: Hour is divisible by 6 (hours 0, 6, 12, 18)
- **4x**: Hour is divisible by 4 (hours 0, 4, 8, 12, 16, 20)
- **3x**: Hour is divisible by 3 (hours 0, 3, 6, 9, 12, 15, 18, 21)
- **2x**: Hour is divisible by 2 (all even hours)
- **1x**: All other hours (odd hours not divisible by 3)

## Local Development

### Prerequisites
- Node.js 18 or higher
- npm

### Setup

1. Install dependencies:
```bash
npm install
```

2. Set your API endpoint (optional):
```bash
export API_ENDPOINT=https://your-api.com/endpoint
```

3. Run the application:
```bash
npm start
```

## Docker Deployment

### Build Docker Image

```bash
docker build -t cron-self-code .
```

### Run Docker Container

```bash
docker run -e API_ENDPOINT=https://your-api.com/endpoint cron-self-code
```

## Deployment Options

### Option 1: Deploy to Google Cloud (Recommended)

This project includes an automated deployment script for Google Cloud Platform that sets up:
- Artifact Registry for Docker images
- Cloud Run Job for executing the cron task
- Cloud Scheduler for hourly triggers

**Quick Start:**

#### Using npm scripts (Recommended):
```bash
# Deploy with default settings
npm run deploy

```

#### Using the script directly:
```bash
# Make the script executable (first time only)
chmod +x deploy.sh

# Deploy with defaults
./deploy.sh

# Or deploy with custom configuration
GCP_PROJECT_ID=my-project API_ENDPOINT=https://api.example.com/cron ./deploy.sh
```

#### Using environment variables from .env file:
1. Copy `.env.example` to `.env`
2. Update the values in `.env` with your configuration
3. Run: `npm run deploy`

**See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed deployment instructions and configuration options.**

### Option 2: Deploy to Render

#### Steps:

1. **Create a new Web Service** on Render
2. **Connect your Git repository**
3. **Configure the service:**
   - **Environment**: Docker
   - **Build Command**: (leave empty, Dockerfile will be used)
   - **Start Command**: (leave empty, CMD in Dockerfile will be used)

4. **Add Environment Variable:**
   - Key: `API_ENDPOINT`
   - Value: Your actual API endpoint URL

5. **Deploy**

#### Important Notes for Render:

- Render will automatically detect the Dockerfile and build the image
- The application runs continuously and executes the API call every hour
- Make sure to set the `API_ENDPOINT` environment variable in Render's dashboard
- The service will call the API immediately on startup and then every hour at minute 0

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `API_ENDPOINT` | The API endpoint to call | `https://api.example.com/endpoint` |

## Cron Schedule

The application uses the cron pattern `0 * * * *` which means:
- Runs at minute 0 of every hour
- Examples: 00:00, 01:00, 02:00, etc.

## API Call Format

The application makes a GET request to the configured endpoint with a query parameter:

```
GET {API_ENDPOINT}?frequency={frequency}
```

Example:
```
GET https://api.example.com/endpoint?frequency=6x
```

## Logs

The application logs:
- Startup message
- Each cron job trigger
- Current hour and calculated frequency
- API response status and data
- Any errors that occur

## Deployment Management

### Google Cloud Commands

After deploying to Google Cloud, you can manage your deployment with these commands:

```bash
# Execute the job immediately
gcloud run jobs execute cron-uninterrupt-task --region=us-central1

# View job logs
gcloud logging read "resource.type=cloud_run_job AND resource.labels.job_name=cron-uninterrupt-task" --limit=50

# View scheduler status
gcloud scheduler jobs describe cron-uninterrupt-task-hourly --location=us-central1

# Trigger scheduler manually
gcloud scheduler jobs run cron-uninterrupt-task-hourly --location=us-central1
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for more management commands and troubleshooting tips.

## Graceful Shutdown

The application handles SIGTERM and SIGINT signals for graceful shutdown, which is important for container orchestration platforms like Render and Cloud Run.
