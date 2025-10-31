FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application files
COPY . .

# Set environment variables (can be overridden at runtime)
ENV NODE_ENV=production
ENV API_ENDPOINT=https://cloud.blackbox.ai/api/cron/execute

# Run the application
CMD ["node", "index.js"]
