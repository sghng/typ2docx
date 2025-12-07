FROM rust:alpine AS typ2docx
RUN apk add pkgconfig openssl-dev uv gcompat
COPY pyproject.toml /
RUN uv tool install typ2docx==0.8.0 --no-binary-package saxonche --verbose
RUN /root/.local/share/uv/tools/typ2docx/bin/pip install \
    --platform manylinux_2_17_x86_64 \
    --only-binary=:all: \
    saxonche

FROM alpine:edge AS typst
RUN apk add typst

FROM pandoc/minimal AS pandoc

FROM oven/bun:alpine
RUN apk add ca-certificates gcompat unzip rsync zip
COPY --from=pandoc /usr/local/bin/pandoc /usr/local/bin/
COPY --from=typst /usr/bin/typst /usr/local/bin/
COPY --from=typ2docx /root/.local/bin/typ2docx /usr/local/bin/
COPY --from=typ2docx /root/.local/share/uv/ /root/.local/share/uv/
COPY server.ts /
COPY index.html /
CMD ["bun", "server.ts"]
