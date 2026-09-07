FROM node:22-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY . .

EXPOSE 4200
# --poll keeps the file watcher working across the Docker bind mount.
CMD ["npm", "start"]
