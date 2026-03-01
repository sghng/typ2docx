import { env } from "cloudflare:workers";
import { Container, getRandom } from "@cloudflare/containers";

// Container class — extends DurableObject under the hood (platform requirement).
// No sleepAfter: container shuts down as soon as it goes idle.
export class Typ2DocxContainer extends Container {
	defaultPort = 10000;
	envVars = {
		PDF_SERVICES_CLIENT_ID: env.PDF_SERVICES_CLIENT_ID as string,
		PDF_SERVICES_CLIENT_SECRET: env.PDF_SERVICES_CLIENT_SECRET as string,
	};

	// Start the container (if not already running) and wait for the port to be
	// ready before proxying the request. Without this, fetch() throws
	// "container is not running, consider calling start()" when the container
	// is cold or waking from sleep.
	//
	// Cloudflare Firecracker VMs take longer than the default 8s timeout to
	// obtain an instance. Use generous timeouts: 120s to get an instance,
	// 60s for the app to start listening on the port.
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
		// Single instance (max_instances=1, low traffic). getRandom with n=1
		// always resolves to the same instance, waking it if asleep.
		const container = await getRandom(env.TYP2DOCX_CONTAINER, 1);
		return container.fetch(request);
	},
};
