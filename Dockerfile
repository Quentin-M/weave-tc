FROM alpine:3.7
RUN   apk add --no-cache iproute2
ADD . .
ENTRYPOINT ./weave-tc.sh
