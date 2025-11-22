FROM alpine:latest

WORKDIR /app

COPY server.js /app/server.js
COPY index.html /app/index.html

RUN apk add --no-cache curl bash unzip pandoc-cli gcc musl-dev gcompat
RUN curl -fsSL https://bun.com/install | bash
# RUN curl -LsSf https://astral.sh/uv/install.sh | sh
# RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
ENV PATH="/root/.local/bin:/root/.cargo/bin:/root/.bun/bin:$PATH"
# RUN uv tool install typ2docx --python-platform x86_64-unknown-linux-gnu --verbose

CMD ["bun", "/app/server.js"]
