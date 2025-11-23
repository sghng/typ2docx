#!/usr/bin/env bun
import { mkdtemp, rm } from "fs/promises";
import AdmZip from "adm-zip";

const port = 10000;
Bun.serve({
	port,
	async fetch(req) {
		switch (req.method) {
			case "POST": {
				const { project, entry } = await req.json();
				if (!project)
					return new Response("Missing 'project' field", {
						status: 400,
					});
				const zip = new AdmZip(Buffer.from(project, "base64"));
				const dir = await mkdtemp("");
				try {
					await Promise.all(
						zip
							.getEntries()
							.filter((e) => !e.isDirectory)
							.map((e) =>
								Bun.write(
									`${dir}/${e.entryName.split("/").pop()}`,
									e.getData(),
								),
							),
					);
					const { stdout, stderr, exitCode } =
						await Bun.$`cd ${dir} && typ2docx ${entry || "main.typ"} -e pdfservices`
							.env(process.env)
							.quiet()
							.nothrow();
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
				} finally {
					rm(dir, { recursive: true });
				}
			}
			case "GET":
				return new Response(Bun.file("index.html"));
			default:
				return new Response(null, { status: 405 });
		}
	},
});

console.log(`Server is running on http://localhost:${port}`);
