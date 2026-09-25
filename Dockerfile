# ================================
# Stage 1 - Build React application
# ================================
FROM node:22-alpine AS builder

WORKDIR /app

COPY package*.json ./

RUN npm ci

COPY . .

RUN npm run build


# ================================
# Stage 2 - Production runtime
# ================================
FROM alpine:3.22

RUN apk add --no-cache nginx \
    && addgroup -S appgroup \
    && adduser -S appuser -G appgroup \
    && mkdir -p \
    /usr/share/nginx/html \
    /tmp/client_temp \
    /tmp/proxy_temp \
    /tmp/fastcgi_temp \
    /tmp/uwsgi_temp \
    /tmp/scgi_temp \
    && chown -R appuser:appgroup \
    /usr/share/nginx/html \
    /tmp/client_temp \
    /tmp/proxy_temp \
    /tmp/fastcgi_temp \
    /tmp/uwsgi_temp \
    /tmp/scgi_temp

COPY nginx.conf /etc/nginx/nginx.conf

COPY --from=builder --chown=appuser:appgroup \
    /app/dist /usr/share/nginx/html

EXPOSE 3000

HEALTHCHECK --interval=30s \
    --timeout=5s \
    --start-period=10s \
    --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:3999/health || exit 1

USER appuser

CMD ["nginx", "-g", "daemon off;"]