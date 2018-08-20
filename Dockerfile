FROM alpine:3.7
RUN apk add --no-cache iproute2
ENV DNSMASQ_PORT=53
ENV NET_OVERLAY_IF=weave
ADD . .
ENTRYPOINT ./weave-tc.sh
