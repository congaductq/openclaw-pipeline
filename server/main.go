package main

import (
	"log"
	"net/http"
	"os"

	"openclaw-server/handler"
	"openclaw-server/webhook"
)

func main() {
	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = "4000"
	}

	frontendURL := os.Getenv("FRONTEND_URL")
	if frontendURL == "" {
		frontendURL = "http://localhost:3000"
	}

	pipelineDir := os.Getenv("PIPELINE_DIR")
	if pipelineDir == "" {
		pipelineDir = "/app/pipeline"
	}

	notifier := webhook.NewNotifier(frontendURL)
	h := handler.New(pipelineDir, notifier)

	mux := http.NewServeMux()

	// API endpoints
	mux.HandleFunc("POST /launch", h.Launch)
	mux.HandleFunc("POST /approve", h.Approve)
	mux.HandleFunc("GET /status", h.Status)
	mux.HandleFunc("GET /health", h.Health)

	// Webhook receiver: Docker/scripts POST here, server forwards to frontend
	mux.HandleFunc("POST /webhook/event", h.WebhookEvent)

	// Swagger UI
	mux.HandleFunc("GET /swagger", h.SwaggerUI)
	mux.HandleFunc("GET /swagger.json", h.SwaggerJSON)

	wrapped := corsMiddleware(mux)

	log.Printf("OpenClaw Pipeline Server starting on :%s", port)
	log.Printf("Frontend webhook target: %s", frontendURL)
	log.Printf("Pipeline directory: %s", pipelineDir)
	log.Fatal(http.ListenAndServe(":"+port, wrapped))
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
