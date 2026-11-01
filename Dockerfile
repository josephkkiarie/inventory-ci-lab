FROM alpine:3.21

RUN apk add --no-cache bash socat \
    && addgroup -S -g 10001 appgroup \
    && adduser -S -D -H -u 10001 -G appgroup appuser

WORKDIR /service
COPY app/ /service/app/
RUN chmod 0555 /service/app/server.sh /service/app/router.sh

USER appuser
EXPOSE 5000
CMD ["socat", "-T", "10", "TCP-LISTEN:5000,bind=0.0.0.0,reuseaddr,fork", "EXEC:/service/app/server.sh"]
