interface Env {
	BACKEND: Fetcher;
}

// Forward POST requests to the Container Worker via service binding.
// All other requests fall through to Pages static asset serving.
export const onRequest: PagesFunction<Env> = async (context) => {
	if (context.request.method === "POST") {
		return context.env.BACKEND.fetch(context.request);
	}
	return context.next();
};
