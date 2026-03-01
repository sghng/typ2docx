import { env } from "cloudflare:workers";
import { Container, getRandom } from "@cloudflare/containers";

export class Typ2DocxContainer extends Container {
	defaultPort = 10000;
	// Sleep immediately after the request completes (minimum 1s — smallest
	// valid time expression accepted by the SDK).
	sleepAfter = "1s";
	envVars = {
		PDF_SERVICES_CLIENT_ID: env.PDF_SERVICES_CLIENT_ID as string,
		PDF_SERVICES_CLIENT_SECRET: env.PDF_SERVICES_CLIENT_SECRET as string,
	};

	// Explicitly start the container before proxying. Without this, super.fetch()
	// uses an 8s instance-get timeout — too short for Firecracker cold starts.
	override async fetch(request: Request): Promise<Response> {
		await this.startAndWaitForPorts(this.defaultPort, {
			instanceGetTimeoutMS: 120_000,
			portReadyTimeoutMS: 60_000,
		});
		return super.fetch(request);
	}
}

interface Env {
	TYP2DOCX_CONTAINER: DurableObjectNamespace;
	PDF_SERVICES_CLIENT_ID: string;
	PDF_SERVICES_CLIENT_SECRET: string;
}

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		const container = await getRandom(env.TYP2DOCX_CONTAINER, 1);
		return container.fetch(request);
	},
};
