FROM alpine:latest

WORKDIR /app

COPY server.js /app/server.js
COPY index.html /app/index.html

RUN apk add --no-cache curl bash unzip pandoc-cli gcc musl-dev
RUN curl -fsSL https://bun.com/install | bash
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
ENV PATH="/root/.local/bin:/root/.cargo/bin:$PATH"
RUN uv tool install typ2docx --platform manylinux_2_24_x86_64

CMD ["bun", "/app/server.js"]
