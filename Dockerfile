FROM alpine:latest

WORKDIR /app

COPY server.js /app/server.js
COPY index.html /app/index.html

RUN apk add --no-cache curl bash unzip pandoc-cli
RUN curl -fsSL https://bun.com/install | bash
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
RUN uv tool install typ2docx -p 3.14t

CMD ["bun", "/app/server.js"]
