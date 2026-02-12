package handler

import (
	"encoding/json"
	"log"
	"net/http"

	"openclaw-server/runner"
	"openclaw-server/webhook"
)

type Handler struct {
	pipeline *runner.Pipeline
	notifier *webhook.Notifier
}

func New(pipelineDir string, notifier *webhook.Notifier) *Handler {
	return &Handler{
		pipeline: runner.New(pipelineDir, notifier),
		notifier: notifier,
	}
}

// POST /launch
func (h *Handler) Launch(w http.ResponseWriter, r *http.Request) {
	var params runner.LaunchParams
	if err := json.NewDecoder(r.Body).Decode(&params); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	if params.Name == "" {
		params.Name = "main"
	}

	if params.ClaudeCodeOAuthToken == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "claude_code_oauth_token is required"})
		return
	}

	// Resolve unique name (auto-increment if instance already exists)
	params.Name = h.pipeline.ResolveName(params.Name)

	if h.pipeline.IsRunning(params.Name) {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "deployment already running for " + params.Name})
		return
	}

	// Launch asynchronously — progress events come from scripts via POST /webhook/event
	go h.pipeline.Launch(params)

	writeJSON(w, http.StatusAccepted, map[string]string{
		"status":  "accepted",
		"name":    params.Name,
		"message": "ec2-full-setup started. Progress will be sent via webhook.",
	})
}

// POST /approve
func (h *Handler) Approve(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		body.Name = "main"
	}
	if body.Name == "" {
		body.Name = "main"
	}

	if err := h.pipeline.Approve(body.Name); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"status":  "ok",
		"name":    body.Name,
		"message": "device approved",
	})
}

// POST /webhook/event — receives events from Docker/scripts, forwards to frontend
func (h *Handler) WebhookEvent(w http.ResponseWriter, r *http.Request) {
	var event webhook.Event
	if err := json.NewDecoder(r.Body).Decode(&event); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	if event.Name == "" {
		event.Name = "main"
	}

	log.Printf("[event/%s] %s: %s", event.Name, event.Type, event.Message)

	// Log cloudflare URL prominently
	if event.Type == webhook.EventCloudflareReady {
		log.Printf("========================================")
		log.Printf("  CLOUDFLARE URL [%s]: %s", event.Name, event.Message)
		log.Printf("========================================")
	}

	// Forward to frontend
	h.notifier.Forward(event)

	// Auto-trigger approve when pairing_required is detected
	if event.Type == webhook.EventPairingRequired {
		go h.pipeline.Approve(event.Name)
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "forwarded"})
}

// GET /status
func (h *Handler) Status(w http.ResponseWriter, r *http.Request) {
	names := h.pipeline.RunningNames()
	writeJSON(w, http.StatusOK, map[string]any{
		"running_deployments": names,
		"count":               len(names),
	})
}

// GET /health
func (h *Handler) Health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
