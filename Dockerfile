FROM rust:alpine AS typ2docx
RUN apk add pkgconfig openssl-dev gcompat
COPY pyproject.toml /
# TODO: Alpine 3.22 on x86_64 doesn't have latest uv
RUN wget -qO- https://astral.sh/uv/install.sh | sh
RUN /root/.local/bin/uv tool install typ2docx --python-platform x86_64-manylinux_2_40 --verbose

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
CMD ["./server.ts"]
