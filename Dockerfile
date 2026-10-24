FROM haskell:9.6.6-slim AS build

WORKDIR /src
COPY cabal.project werewolf-server.cabal ./
RUN cabal user-config init --force \
    && sed -i 's|url: http://hackage.haskell.org/|url: https://hackage.haskell.org/|' /root/.config/cabal/config \
    && sed -i -E 's|^[[:space:]]*(--[[:space:]]*)?secure:.*|  secure: False|' /root/.config/cabal/config \
    && cabal update \
    && cabal build --only-dependencies --enable-tests
COPY app ./app
COPY src ./src
COPY test ./test
RUN cabal build all --enable-tests \
    && cabal test all --enable-tests --test-show-details=direct \
    && mkdir -p /out \
    && cp "$(cabal list-bin exe:werewolf-server)" /out/werewolf-server \
    && cp "$(cabal list-bin exe:analytics-worker)" /out/analytics-worker

FROM debian:bookworm-slim AS runtime
RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates curl netcat-openbsd \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 app
WORKDIR /app
COPY --from=build /out/werewolf-server /usr/local/bin/werewolf-server
COPY --from=build /out/analytics-worker /usr/local/bin/analytics-worker
COPY web ./web
USER app
ENV APP_PORT=8080
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1:${APP_PORT}/health || exit 1
CMD ["werewolf-server"]
