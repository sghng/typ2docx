FROM debian:stable-slim AS builder

RUN apt update && apt install -y --no-install-recommends \
    ca-certificates curl build-essential pkg-config libssl-dev

ARG PANDOC_VERSION=3.8.2.1
RUN curl -L "https://github.com/jgm/pandoc/releases/download/${PANDOC_VERSION}/pandoc-${PANDOC_VERSION}-linux-amd64.tar.gz" | tar -xz

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal -y
ENV PATH=/root/.cargo/bin:$PATH
ENV CARGO_TARGET_DIR=/target
RUN cargo install typst-cli

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH=/root/.local/bin:$PATH
RUN uv tool install typ2docx --verbose

FROM debian:stable-slim

WORKDIR /app

COPY server.js /app/server.js
COPY index.html /app/index.html

COPY --from=builder /root/.cargo/bin/typst /usr/local/bin/typst
COPY --from=builder /pandoc-*/bin/pandoc /usr/local/bin/pandoc
COPY --from=builder /root/.local/share/uv/ /root/.local/share/uv/
COPY --from=builder /root/.local/bin/typ2docx /usr/local/bin/typ2docx

RUN apt update && apt install -y --no-install-recommends unzip rsync
RUN curl -fsSL https://bun.com/install | bash
ENV PATH=/root/.bun/bin:$PATH

CMD ["bun", "/app/server.js"]
