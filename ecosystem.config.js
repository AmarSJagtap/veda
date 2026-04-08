/**
 * PM2 Ecosystem Configuration
 * Run: pm2 start ecosystem.config.js
 */
module.exports = {
  apps: [
    {
      name: 'voice-bot-widget',
      script: 'server/index.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '512M',
      env: {
        NODE_ENV: 'production',
        PORT: 3800,
      },
    },
  ],
};
