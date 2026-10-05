FROM haskell:9.6.6-slim AS build

WORKDIR /src
COPY cabal.project werewolf-server.cabal ./
RUN cabal update && cabal build --only-dependencies
COPY app ./app
COPY src ./src
COPY test ./test
RUN cabal build all \
    && cabal test all \
    && mkdir -p /out \
    && cp "$(cabal list-bin exe:werewolf-server)" /out/werewolf-server

FROM debian:bookworm-slim AS runtime
RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 app
COPY --from=build /out/werewolf-server /usr/local/bin/werewolf-server
USER app
ENV APP_PORT=8080
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1:${APP_PORT}/health || exit 1
CMD ["werewolf-server"]
