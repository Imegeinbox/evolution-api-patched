# syntax=docker/dockerfile:1.7
FROM node:24-alpine AS builder

RUN apk update && \
    apk add --no-cache git ffmpeg wget curl bash openssl

LABEL maintainer="imprimindoideias" \
      description="evolution-api 2.3.7 oficial, com dois ajustes locais: fix do PR evolution-foundation/evolution-api#2763 (guarda de midia que descartava documentos com legenda) e remocao do vazamento de chaves de sessao nos logs (libsignal-node console.info/warn)." \
      source="https://github.com/evolution-foundation/evolution-api/pull/2763"

WORKDIR /evolution

# Codigo-fonte oficial, na mesma tag que ja roda em producao (2.3.7)
RUN git clone --depth 1 --branch 2.3.7 https://github.com/evolution-foundation/evolution-api.git . \
    && rm -rf .git

RUN npm ci --silent

# --- Patch 1: bug do PR #2763 (media guard em getBase64FromMediaMessage) ---
RUN sed -i "s#if ('messageContextInfo' in msg.message && Object.keys(msg.message).length === 1) {#if (Object.keys(msg.message).length === 1 \&\& Object.prototype.hasOwnProperty.call(msg.message, 'messageContextInfo')) {#" src/api/integrations/channel/whatsapp/whatsapp.baileys.service.ts \
    && grep -q "Object.prototype.hasOwnProperty.call(msg.message, 'messageContextInfo')" src/api/integrations/channel/whatsapp/whatsapp.baileys.service.ts \
    && echo "patch 1 OK"

# --- Patch 2: libsignal-node imprime a sessao inteira (com chaves privadas) em console.info/warn ---
RUN sed -i \
    -e 's#console\.warn("Session already closed", session);#console.warn("Session already closed");#' \
    -e 's#console\.info("Closing session:", session);#console.info("Closing session");#' \
    -e 's#console\.info("Opening session:", session);#console.info("Opening session");#' \
    -e 's#console\.info("Removing old closed session:", oldestSession);#console.info("Removing old closed session");#' \
    node_modules/libsignal/src/session_record.js \
    && ! grep -q "Closing session:\", session" node_modules/libsignal/src/session_record.js \
    && echo "patch 2 OK"

RUN chmod +x ./Docker/scripts/* 2>/dev/null; dos2unix ./Docker/scripts/* 2>/dev/null || true

RUN ./Docker/scripts/generate_database.sh

RUN npm run build

FROM node:24-alpine AS final

RUN apk update && \
    apk add tzdata ffmpeg bash openssl

ENV TZ=America/Sao_Paulo
ENV DOCKER_ENV=true

WORKDIR /evolution

COPY --from=builder /evolution/package.json ./package.json
COPY --from=builder /evolution/package-lock.json ./package-lock.json
COPY --from=builder /evolution/node_modules ./node_modules
COPY --from=builder /evolution/dist ./dist
COPY --from=builder /evolution/prisma ./prisma
COPY --from=builder /evolution/manager ./manager
COPY --from=builder /evolution/public ./public
COPY --from=builder /evolution/.env ./.env
COPY --from=builder /evolution/Docker ./Docker
COPY --from=builder /evolution/runWithProvider.js ./runWithProvider.js
COPY --from=builder /evolution/tsup.config.ts ./tsup.config.ts

EXPOSE 8080

ENTRYPOINT ["/bin/bash", "-c", ". ./Docker/scripts/deploy_database.sh && npm run start:prod" ]
