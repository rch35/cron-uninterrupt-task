const cron = require('node-cron');
const axios = require('axios');

// Placeholder API endpoint - replace with your actual endpoint
const API_ENDPOINT = process.env.API_ENDPOINT || 'https://cloud.blackbox.ai/api/cron/resume-stalled';
/**
 * Calls the API with the appropriate frequency parameter
 */
async function callAPI() {
  try {
    const now = new Date();
    const currentHour = now.getHours();
    const frequency = getFrequency(currentHour);
    
    console.log(`[${now.toISOString()}] Current hour: ${currentHour}, Frequency: ${frequency}`);
    
    const response = await axios.get(API_ENDPOINT, {
      timeout: 30000
    });
    
    console.log(`[${now.toISOString()}] API call successful:`, response.status);
    console.log('Response data:', response.data);
  } catch (error) {
    console.error(`[${new Date().toISOString()}] API call failed:`, error.message);
    if (error.response) {
      console.error('Response status:', error.response.status);
      console.error('Response data:', error.response.data);
    }
  }
}

// Call immediately on startup for testing
console.log('Cron job scheduler started');
console.log('Job will run at the start of every hour (0 * * * *)');
console.log('Running initial API call...');
callAPI();

// Keep the process running
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully');
  process.exit(0);
});
