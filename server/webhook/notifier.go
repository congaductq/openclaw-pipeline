package webhook

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"time"
)

type EventType string

const (
	// Events sent by Go server itself (make command lifecycle)
	EventLaunching      EventType = "launching"
	EventCompleted      EventType = "completed"
	EventFailed         EventType = "failed"
	EventApproveTriggered EventType = "approve_triggered"
	EventApproveSuccess EventType = "approve_success"
	EventApproveFailed  EventType = "approve_failed"

	// Events sent by Docker container (log monitoring)
	EventCreatingKey     EventType = "creating_key"
	EventCreatingConfig  EventType = "creating_config"
	EventCreatingEC2     EventType = "creating_ec2"
	EventDeployingApp    EventType = "deploying_app"
	EventPullingImage    EventType = "pulling_image"
	EventStartingApp     EventType = "starting_app"
	EventHealthCheck     EventType = "health_check"
	EventCloudflare      EventType = "setting_up_cloudflare"
	EventAutoApprove     EventType = "auto_approving"
	EventPairingRequired  EventType = "pairing_required"
	EventCloudflareReady  EventType = "cloudflare_ready"
)

type Event struct {
	Type      EventType `json:"type"`
	Name      string    `json:"name"`
	Message   string    `json:"message"`
	Timestamp string    `json:"timestamp"`
	Data      any       `json:"data,omitempty"`
}

type Notifier struct {
	frontendURL string
	client      *http.Client
}

func NewNotifier(frontendURL string) *Notifier {
	return &Notifier{
		frontendURL: frontendURL,
		client: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

// Send creates a new event and forwards it to the frontend.
func (n *Notifier) Send(name string, eventType EventType, message string, data any) {
	event := Event{
		Type:      eventType,
		Name:      name,
		Message:   message,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Data:      data,
	}
	n.Forward(event)
}

// Forward sends an existing event (e.g. received from Docker) to the frontend.
func (n *Notifier) Forward(event Event) {
	if event.Timestamp == "" {
		event.Timestamp = time.Now().UTC().Format(time.RFC3339)
	}

	body, err := json.Marshal(event)
	if err != nil {
		log.Printf("[webhook] marshal error: %v", err)
		return
	}

	log.Printf("[webhook] %s/%s: %s | payload: %s", event.Name, event.Type, event.Message, string(body))

	url := n.frontendURL + "/api/webhook/pipeline"
	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		log.Printf("[webhook] request error: %v", err)
		return
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := n.client.Do(req)
	if err != nil {
		log.Printf("[webhook] -> %s failed (frontend may be offline): %v", url, err)
		return
	}
	defer resp.Body.Close()

	log.Printf("[webhook] -> frontend %d", resp.StatusCode)
}
