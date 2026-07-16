FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
  unzip \
  git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev || npm install --omit=dev

COPY . .

RUN mkdir -p /data

EXPOSE 3000

ENV CUSTOMWARE_PATH=/data
ENV HOST=0.0.0.0
ENV PORT=3000

CMD ["node", "space", "serve"]
