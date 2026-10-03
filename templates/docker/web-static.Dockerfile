# Talay statik web imajı (React/Vite/Expo Web). nginx config'i talay-web chart'ı mount eder.
FROM node:24.21.0-alpine3.24 AS build
WORKDIR /app
RUN corepack enable
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
# Expo Web: RUN npx expo export --platform web  (çıktı: dist)
RUN pnpm build

FROM nginxinc/nginx-unprivileged:1.31.6-alpine3.24
USER root
RUN apk upgrade --no-cache
COPY --from=build /app/dist /usr/share/nginx/html
USER 101
EXPOSE 8080
