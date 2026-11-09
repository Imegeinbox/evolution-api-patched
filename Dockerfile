# syntax=docker/dockerfile:1.7
FROM node:24-alpine AS builder

RUN apk update && \
    apk add --no-cache git ffmpeg wget curl bash openssl

LABEL maintainer="imprimindoideias" \
      description="evolution-api 2.3.7 oficial, com dois ajustes locais: fix do PR evolution-foundation/evolution-api#2763 (guarda de mídia que descartava documentos com legenda) e remoção do vazamento de chaves de sessão nos logs (libsignal-node console.info/warn)." \
      source="https://github.com/evolution-foundation/evolution-api/pull/2763"

WORKDIR /evolution

# Código-fonte oficial, na mesma tag que já roda em produção (2.3.7)
RUN git clone --depth 1 --branch 2.3.7 https://github.com/evolution-foundation/evolution-api.git . \
    && rm -rf .git

RUN npm ci --silent

# --- Patch 1: bug do PR #2763 (media guard em getBase64FromMediaMessage) ---
# A checagem original usa `'messageContextInfo' in msg.message`, que é
# verdadeira mesmo quando a chave não existe de fato (protobuf.js declara
# o campo no prototype de toda mensagem). Isso faz a função descartar
# documentos/mídias legítimas com legenda antes de chegarem ao webhook.
RUN python3 - <<'PYEOF'
path = "src/api/integrations/channel/whatsapp/whatsapp.baileys.service.ts"
old = "      if ('messageContextInfo' in msg.message && Object.keys(msg.message).length === 1) {\n"
new = (
    "      if (\n"
    "        Object.keys(msg.message).length === 1 &&\n"
    "        Object.prototype.hasOwnProperty.call(msg.message, 'messageContextInfo')\n"
    "      ) {\n"
)
with open(path) as f:
    content = f.read()
assert content.count(old) == 1, f"patch 1: esperava 1 ocorrência, achei {content.count(old)}"
content = content.replace(old, new)
with open(path, "w") as f:
    f.write(content)
print("patch 1 aplicado (media guard)")
PYEOF

# --- Patch 2: libsignal-node (dependência do Baileys) imprime o objeto de
# sessão inteiro em console.info/warn ao fechar/abrir/remover sessões —
# incluindo privKey e rootKey da sessão Signal em texto puro no log.
RUN test -f node_modules/libsignal/src/session_record.js \
    && python3 - <<'PYEOF'
path = "node_modules/libsignal/src/session_record.js"
replacements = [
    ('console.warn("Session already closed", session);',
     'console.warn("Session already closed");'),
    ('console.info("Closing session:", session);',
     'console.info("Closing session");'),
    ('console.info("Opening session:", session);',
     'console.info("Opening session");'),
    ('console.info("Removing old closed session:", oldestSession);',
     'console.info("Removing old closed session");'),
]
with open(path) as f:
    content = f.read()
for old, new in replacements:
    count = content.count(old)
    assert count == 1, f"patch 2: esperava 1 ocorrência de {old!r}, achei {count}"
    content = content.replace(old, new)
with open(path, "w") as f:
    f.write(content)
print("patch 2 aplicado (libsignal, 4 ocorrencias)")
PYEOF

RUN chmod +x ./Docker/scripts/* && dos2unix ./Docker/scripts/* 2>/dev/null || true

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
