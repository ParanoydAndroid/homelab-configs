FROM python:3.12-alpine

RUN apk add --no-cache tzdata ca-certificates && \
    pip install --no-cache-dir fanficfare

WORKDIR /import

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
