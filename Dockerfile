FROM ghcr.io/foundry-rs/foundry:latest
USER root
WORKDIR /app
COPY . .
RUN mkdir -p out cache && chmod -R 777 out cache
ENTRYPOINT ["forge", "test", "-vvv"]
