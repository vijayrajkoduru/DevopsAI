FROM node:20-alpine AS base

WORKDIR /app

RUN apk add --no-cache \
    curl \
    tini

COPY package*.json ./

FROM base AS dependencies
RUN npm ci --only=production && \
    npm cache clean --force

FROM base AS build
RUN npm ci
COPY . .
RUN npm run build 2>/dev/null || echo "No build step defined"

FROM base AS runtime

ENV NODE_ENV=production \
    PORT=3000 \
    AWS_REGION=us-east-1

COPY --from=dependencies /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist 2>/dev/null || true
COPY --from=build /app/src ./src 2>/dev/null || true
COPY --from=build /app/*.js ./ 2>/dev/null || true

RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup && \
    chown -R appuser:appgroup /app

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "src/index.js"]