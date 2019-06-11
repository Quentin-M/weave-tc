FROM alpine:3.9
RUN apk add --no-cache iproute2
ENV DNSMASQ_PORT=53
ENV NET_OVERLAY_IF=weave
COPY weave-tc.sh .
ENTRYPOINT ./weave-tc.sh
