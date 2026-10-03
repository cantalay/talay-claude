# Talay Node API/worker imajı. pnpm varsayıldı; npm için: npm ci / npm run build / npm prune --omit=dev
FROM node:24.21.0-alpine3.24 AS build
WORKDIR /app
RUN corepack enable
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build && pnpm prune --prod

# distroless: shell yok, non-root (65532), read-only rootfs uyumlu
FROM gcr.io/distroless/nodejs24-debian13:nonroot AS runtime
ENV NODE_ENV=production PORT=8080
WORKDIR /app
COPY --from=build --chown=65532:65532 /app/node_modules ./node_modules
COPY --from=build --chown=65532:65532 /app/dist ./dist
COPY --from=build --chown=65532:65532 /app/package.json ./package.json
# Migration'lar runtime'da okunuyorsa:
COPY --from=build --chown=65532:65532 /app/db ./db
USER 65532:65532
EXPOSE 8080
# @opentelemetry/auto-instrumentations-node chart'ın NODE_OPTIONS'ı ile yüklenir (production dependency olmalı).
CMD ["dist/main.js"]
