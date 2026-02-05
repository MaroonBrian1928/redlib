FROM rust:1.83-alpine AS builder

WORKDIR /app
RUN apk add --no-cache build-base sccache mold

ENV SCCACHE_DIR=/root/.cache/sccache
ENV RUSTFLAGS="-C link-arg=-fuse-ld=mold"
ENV CARGO_INCREMENTAL=0
ENV CARGO_PROFILE_RELEASE_DEBUG=1

ARG CARGO_PROFILE=release
ARG USE_SCCACHE=1

ARG GIT_HASH
ENV GIT_HASH=${GIT_HASH}
ARG CARGO_BUILD_TARGET

COPY Cargo.toml Cargo.lock build.rs ./
RUN mkdir src && echo "fn main() { panic!(\"warm build cache\") }" > src/main.rs

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/app/target \
    --mount=type=cache,target=/root/.cache/sccache \
    target="${CARGO_BUILD_TARGET:-}"; \
    target="${target#\"}"; target="${target%\"}"; \
    if [ "$USE_SCCACHE" = "1" ]; then export RUSTC_WRAPPER=sccache; export CARGO_INCREMENTAL=0; else unset RUSTC_WRAPPER; export CARGO_INCREMENTAL=1; fi; \
    if [ -z "$target" ] || [ "$target" = "''" ]; then \
        if [ "$CARGO_PROFILE" = "dev" ]; then \
            cargo build --locked; \
        else \
            cargo build --release --locked; \
        fi; \
    else \
        if [ "$CARGO_PROFILE" = "dev" ]; then \
            cargo build --locked --target "$target"; \
        else \
            cargo build --release --locked --target "$target"; \
        fi; \
    fi

RUN if [ "$USE_SCCACHE" = "1" ]; then which sccache && sccache --show-stats || true; else true; fi

RUN rm ./src/main.rs && rmdir ./src

COPY src ./src
COPY static ./static
COPY templates ./templates

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/app/target \
    --mount=type=cache,target=/root/.cache/sccache \
    target="${CARGO_BUILD_TARGET:-}"; \
    target="${target#\"}"; target="${target%\"}"; \
    if [ "$USE_SCCACHE" = "1" ]; then export RUSTC_WRAPPER=sccache; export CARGO_INCREMENTAL=0; else unset RUSTC_WRAPPER; export CARGO_INCREMENTAL=1; fi; \
    if [ -z "$target" ] || [ "$target" = "''" ]; then \
        if [ "$CARGO_PROFILE" = "dev" ]; then \
            cargo build --locked; \
            cp /app/target/debug/redlib /app/redlib; \
        else \
            cargo build --release --locked; \
            cp /app/target/release/redlib /app/redlib; \
        fi; \
    else \
        if [ "$CARGO_PROFILE" = "dev" ]; then \
            cargo build --locked --target "$target"; \
            cp "/app/target/$target/debug/redlib" /app/redlib; \
        else \
            cargo build --release --locked --target "$target"; \
            cp "/app/target/$target/release/redlib" /app/redlib; \
        fi; \
    fi

RUN if [ "$USE_SCCACHE" = "1" ]; then which sccache && sccache --show-stats || true; else true; fi

FROM alpine:3

RUN apk add --no-cache ca-certificates curl
WORKDIR /app
COPY --from=builder /app/redlib /usr/local/bin/redlib
COPY --from=builder /app/static /app/static
COPY --from=builder /app/templates /app/templates

RUN adduser --home /nonexistent --no-create-home --disabled-password redlib
USER redlib

# Tell Docker to expose port 8080
EXPOSE 8080

# Run a healthcheck every minute to make sure redlib is functional
HEALTHCHECK --interval=1m --timeout=3s CMD wget --spider -q http://localhost:8080/settings || exit 1

CMD ["redlib"]
