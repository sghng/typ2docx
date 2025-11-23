#!/usr/bin/env bun
import { rm, mkdtemp, writeFile } from "fs/promises";

const port = 10000;
Bun.serve({
	port,
	async fetch(req) {
		switch (req.method) {
			case "POST": {
				const { project, entry = "main.typ" } = await req.json();
				if (!project)
					return new Response("Missing 'project' field", {
						status: 400,
					});
				const dir = await mkdtemp("/tmp/typ2docx-");
				await writeFile(
					`${dir}/project.zip`,
					Buffer.from(project, "base64"),
				);
				await Bun.$`cd ${dir} && unzip -o project.zip && rm project.zip`
					.quiet()
					.nothrow();
				const { stdout, stderr, exitCode } =
					await Bun.$`cd ${dir} && typ2docx ${entry} -e pdfservices -- --root .`
						.env(process.env)
						.quiet()
						.nothrow();
				await rm(dir, { recursive: true, force: true });
				return exitCode
					? new Response(stderr, { status: 500 })
					: new Response(stdout, {
							headers: {
								"Content-Type":
									"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
								"Content-Disposition":
									"attachment; filename=output.docx",
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

console.log(`Server is running on http://localhost:${port}`);
