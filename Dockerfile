FROM rust:slim AS typ2docx
RUN apt update && apt install -y --no-install-recommends curl
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
RUN /root/.local/bin/uv tool install typ2docx --verbose

FROM rust:slim AS typst
RUN apt update && apt install -y --no-install-recommends pkg-config libssl-dev
RUN cargo install typst-cli

FROM alpine/curl AS pandoc
ARG VERSION=3.8.2.1
ARG PLATFORM=linux-amd64
ARG REPO=https://github.com/jgm/pandoc
ARG FILE=pandoc-${VERSION}-${PLATFORM}.tar.gz
RUN curl -L "${REPO}/releases/download/${VERSION}/${FILE}" | tar -xz

FROM oven/bun:canary-slim
WORKDIR /app
COPY server.js /app/server.js
COPY index.html /app/index.html
RUN apt update && apt install -y --no-install-recommends unzip rsync zip
COPY --from=typst /usr/local/cargo/bin/typst /usr/local/bin/typst
COPY --from=pandoc /pandoc-*/bin/pandoc /usr/local/bin/pandoc
COPY --from=typ2docx /root/.local/share/uv/ /root/.local/share/uv/
COPY --from=typ2docx /root/.local/bin/typ2docx /usr/local/bin/typ2docx
CMD ["bun", "server.js"]
