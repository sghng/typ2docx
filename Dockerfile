FROM debian:stable-slim

WORKDIR /app

COPY server.js /app/server.js
COPY index.html /app/index.html

RUN apt update && apt install -y curl unzip pandoc typst rsync
RUN curl -fsSL https://bun.com/install | bash
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH=/root/.local/bin:/root/.bun/bin:$PATH
RUN uv tool install typ2docx --verbose -n

CMD ["bun", "/app/server.js"]
