FROM alpine:3.7
RUN   apk add --no-cache iproute2
ENV DNSMASQ_PORT=5353
ADD . .
ENTRYPOINT ./weave-tc.sh
