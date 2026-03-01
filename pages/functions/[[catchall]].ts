interface Env {
	BACKEND: Fetcher;
}

// Intercept POST requests and forward them to the Container Worker via service
// binding. GET requests are handled by Pages' static asset serving (index.html).
export const onRequest: PagesFunction<Env> = async (context) => {
	if (context.request.method === "POST") {
		return context.env.BACKEND.fetch(context.request);
	}
	return new Response("Method not allowed", { status: 405 });
};
