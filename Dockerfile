FROM rust:slim AS builder

RUN apt update && apt install -y --no-install-recommends \
    curl pkg-config libssl-dev

ARG PANDOC_VERSION=3.8.2.1
ARG PLATFORM=linux-amd64
RUN curl -L "https://github.com/jgm/pandoc/releases/download/${PANDOC_VERSION}/pandoc-${PANDOC_VERSION}-${PLATFORM}.tar.gz" | tar -xz

ENV CARGO_TARGET_DIR=/target
RUN cargo install typst-cli

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
RUN /root/.local/bin/uv tool install typ2docx --verbose

FROM oven/bun:canary-slim

WORKDIR /app

COPY server.js /app/server.js
COPY index.html /app/index.html

COPY --from=builder /usr/local/cargo/bin/typst /usr/local/bin/typst
COPY --from=builder /pandoc-*/bin/pandoc /usr/local/bin/pandoc
COPY --from=builder /root/.local/share/uv/ /root/.local/share/uv/
COPY --from=builder /root/.local/bin/typ2docx /usr/local/bin/typ2docx

CMD ["bun", "server.js"]
