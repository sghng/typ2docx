#!/usr/bin/env bun
Bun.serve({
  port: 10000,
  async fetch(req) {
    switch (req.method) {
      case "POST": {
        const { project, entry } = await req.json();
        if (!project)
          return new Response("Missing 'project' field", { status: 400 });
        const dir = (await Bun.$`mktemp -d`.text()).trim();
        await Bun.write(`${dir}/project.zip`, Buffer.from(project, "base64"));
        await Bun.$`unzip -q ${dir}/project.zip -d ${dir}`.quiet();
        const { stdout, stderr, exitCode } =
          await Bun.$`typ2docx ${dir}/${entry ?? ""} -e pdfservices -- --root ${dir}`
            .env(process.env)
            .quiet()
            .nothrow();
        return exitCode
          ? new Response(`Conversion failed:\n${stderr}`, { status: 500 })
          : new Response(stdout, {
              headers: {
                "Content-Type":
                  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "Content-Disposition": "attachment; filename=output.docx",
              },
            });
      }
      case "GET":
        return new Response(Bun.file("index.html"));
      default:
        return new Response(null, { status: 405 });
    }
  },
});

console.log(`Server is running on http://localhost:3000`);
