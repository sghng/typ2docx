FROM rust:slim AS typ2docx
RUN apt update && apt install -y --no-install-recommends \
    curl pkg-config libssl-dev
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
COPY pyproject.toml /
RUN /root/.local/bin/uv tool install typ2docx --verbose

# align with oven/bun:slim
FROM rust:slim-bookworm AS typst
RUN apt update && apt install -y --no-install-recommends pkg-config libssl-dev
COPY Cargo.toml /
RUN cargo install typst-cli

FROM alpine/curl AS pandoc
ARG PLATFORM=linux-amd64
ARG REPO=https://github.com/jgm/pandoc
ARG VERSION=3.8.3
ARG FILE=pandoc-${VERSION}-${PLATFORM}.tar.gz
RUN curl -LsSF "${REPO}/releases/download/${VERSION}/${FILE}" | tar -xz

FROM oven/bun:slim
RUN apt update && \
    apt install -y --no-install-recommends ca-certificates unzip rsync zip && \
    rm -rf /var/lib/apt/lists/
COPY --from=pandoc /pandoc-*/bin/pandoc /usr/local/bin/
COPY --from=typst /usr/local/cargo/bin/typst /usr/local/bin/
COPY --from=typ2docx /root/.local/bin/typ2docx /usr/local/bin/
COPY --from=typ2docx /root/.local/share/uv/ /root/.local/share/uv/
COPY server.ts /
COPY index.html /
CMD ["bun", "server.ts"]
