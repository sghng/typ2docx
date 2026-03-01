interface Env {
	BACKEND: Fetcher;
}

// Intercept POST requests and forward them to the Container Worker via service
// binding. All other requests fall through to Pages static asset serving
// (index.html for GET /, etc.).
export const onRequest: PagesFunction<Env> = async (context) => {
	if (context.request.method === "POST") {
		return context.env.BACKEND.fetch(context.request);
	}
	return context.next();
};
