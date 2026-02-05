FROM rust:1.83-alpine AS builder

WORKDIR /app
RUN apk add --no-cache build-base

ARG GIT_HASH
ENV GIT_HASH=${GIT_HASH}
ARG CARGO_BUILD_TARGET

COPY Cargo.toml Cargo.lock build.rs ./
COPY src ./src
COPY static ./static
COPY templates ./templates

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/app/target \
    target="${CARGO_BUILD_TARGET:-}"; \
    target="${target#\"}"; target="${target%\"}"; \
    if [ -z "$target" ] || [ "$target" = "''" ]; then \
        cargo build --release --locked; \
        cp /app/target/release/redlib /app/redlib; \
    else \
        cargo build --release --locked --target "$target"; \
        cp "/app/target/$target/release/redlib" /app/redlib; \
    fi

FROM alpine:3.19

RUN apk add --no-cache ca-certificates curl
COPY --from=builder /app/redlib /usr/local/bin/redlib

RUN adduser --home /nonexistent --no-create-home --disabled-password redlib
USER redlib

# Tell Docker to expose port 8080
EXPOSE 8080

# Run a healthcheck every minute to make sure redlib is functional
HEALTHCHECK --interval=1m --timeout=3s CMD wget --spider -q http://localhost:8080/settings || exit 1

CMD ["redlib"]
