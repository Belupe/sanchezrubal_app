# =====================================================================
#  media-scrub — imagen del worker que limpia metadatos de vídeo [2L-12]
# =====================================================================
#  Alpine + ffmpeg + jq + el cliente mc de MinIO. Pequeño y sin estado.
FROM alpine:3.20

# ffmpeg (re-mux), jq (parseo de eventos), bash/coreutils (mktemp, ${x,,}).
RUN apk add --no-cache ffmpeg jq bash coreutils ca-certificates wget \
 && wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc \
 && chmod +x /usr/local/bin/mc \
 && adduser -D -u 1000 scrub

COPY scrub.sh /usr/local/bin/scrub.sh
RUN chmod +x /usr/local/bin/scrub.sh

USER scrub
ENTRYPOINT ["/usr/local/bin/scrub.sh"]
