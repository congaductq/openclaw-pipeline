package runner

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"

	"openclaw-server/webhook"
)

type LaunchParams struct {
	Name                 string `json:"name"`
	Token                string `json:"token"`
	ClaudeCodeOAuthToken string `json:"claude_code_oauth_token"`
	Cloudflare           bool   `json:"cloudflare"`
}

type LaunchResult struct {
	Name  string `json:"name"`
	Error string `json:"error,omitempty"`
}

type Pipeline struct {
	dir      string
	notifier *webhook.Notifier

	mu      sync.Mutex
	running map[string]*exec.Cmd
}

func New(dir string, notifier *webhook.Notifier) *Pipeline {
	return &Pipeline{
		dir:      dir,
		notifier: notifier,
		running:  make(map[string]*exec.Cmd),
	}
}

func (p *Pipeline) IsRunning(name string) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	_, ok := p.running[name]
	return ok
}

func (p *Pipeline) RunningNames() []string {
	p.mu.Lock()
	defer p.mu.Unlock()
	names := make([]string, 0, len(p.running))
	for name := range p.running {
		names = append(names, name)
	}
	return names
}

// ResolveName checks for existing terraform state files and auto-increments
// the name if one already exists (e.g. ducdv -> ducdv1 -> ducdv2).
func (p *Pipeline) ResolveName(name string) string {
	stateFile := filepath.Join(p.dir, "terraform", "ec2", fmt.Sprintf("terraform-%s.tfstate", name))
	if _, err := os.Stat(stateFile); os.IsNotExist(err) {
		return name
	}

	for i := 1; i <= 100; i++ {
		candidate := fmt.Sprintf("%s%d", name, i)
		stateFile = filepath.Join(p.dir, "terraform", "ec2", fmt.Sprintf("terraform-%s.tfstate", candidate))
		if _, err := os.Stat(stateFile); os.IsNotExist(err) {
			return candidate
		}
	}
	return name
}

// ansiRegex strips ANSI escape codes (colors, cursor movement, etc.)
var ansiRegex = regexp.MustCompile(`\x1b\[[0-9;]*[a-zA-Z]`)

// filterOutput removes noisy output: ANSI codes and docker pull/extract progress.
func filterOutput(raw string) string {
	raw = ansiRegex.ReplaceAllString(raw, "")

	var filtered []string
	for _, line := range strings.Split(raw, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}

		// Skip docker pull/extract progress noise
		if strings.Contains(trimmed, "Downloading") || strings.Contains(trimmed, "Extracting") ||
			strings.Contains(trimmed, "Waiting") || strings.Contains(trimmed, "Verifying") ||
			strings.Contains(trimmed, "Pull complete") || strings.Contains(trimmed, "Already exists") ||
			strings.Contains(trimmed, "Download complete") || strings.Contains(trimmed, "Pulling from") ||
			strings.Contains(trimmed, "Pulling fs layer") || strings.Contains(trimmed, "Digest:") {
			continue
		}

		filtered = append(filtered, line)
	}
	return strings.Join(filtered, "\n")
}

// Launch runs `make ec2-full-setup` asynchronously.
// The Go server only tracks start/end. Detailed progress comes from
// Docker container posting to POST /webhook/event.
func (p *Pipeline) Launch(params LaunchParams) {
	name := params.Name
	if name == "" {
		name = "main"
	}

	p.mu.Lock()
	if _, ok := p.running[name]; ok {
		p.mu.Unlock()
		p.notifier.Send(name, webhook.EventFailed, "deployment already running for "+name, nil)
		return
	}
	p.mu.Unlock()

	p.notifier.Send(name, webhook.EventLaunching, "starting ec2-full-setup for "+name, params)

	cloudflare := "false"
	if params.Cloudflare {
		cloudflare = "true"
	}

	args := []string{
		"make", "ec2-full-setup",
		fmt.Sprintf("NAME=%s", name),
		fmt.Sprintf("CLOUDFLARE=%s", cloudflare),
	}
	if params.ClaudeCodeOAuthToken != "" {
		args = append(args, fmt.Sprintf("CLAUDE_CODE_OAUTH_TOKEN=%s", params.ClaudeCodeOAuthToken))
	}
	if params.Token != "" {
		args = append(args, fmt.Sprintf("TOKEN=%s", params.Token))
	}

	cmd := exec.Command(args[0], args[1:]...)
	cmd.Dir = p.dir
	cmd.Env = append(cmd.Environ(),
		fmt.Sprintf("CLAUDE_CODE_OAUTH_TOKEN=%s", params.ClaudeCodeOAuthToken),
	)
	if params.Token != "" {
		cmd.Env = append(cmd.Env, fmt.Sprintf("OPENCLAW_GATEWAY_TOKEN=%s", params.Token))
	}

	p.mu.Lock()
	p.running[name] = cmd
	p.mu.Unlock()

	go func() {
		defer func() {
			p.mu.Lock()
			delete(p.running, name)
			p.mu.Unlock()
		}()

		output, err := cmd.CombinedOutput()
		outStr := filterOutput(string(output))

		if err != nil {
			log.Printf("[launch/%s] failed: %v\n%s", name, err, outStr)
			p.notifier.Send(name, webhook.EventFailed, "ec2-full-setup failed: "+err.Error(), LaunchResult{
				Name:  name,
				Error: outStr,
			})
			return
		}

		log.Printf("[launch/%s] completed successfully\n%s", name, outStr)
		p.notifier.Send(name, webhook.EventCompleted, "deployment complete for "+name, LaunchResult{Name: name})
	}()
}

// Approve triggers device approval for a deployment.
func (p *Pipeline) Approve(name string) error {
	if name == "" {
		name = "main"
	}

	p.notifier.Send(name, webhook.EventApproveTriggered, "triggering device approval for "+name, nil)

	cmd := exec.Command("make", "ec2-approve", fmt.Sprintf("NAME=%s", name))
	cmd.Dir = p.dir

	output, err := cmd.CombinedOutput()
	outStr := string(output)
	log.Printf("[approve/%s] %s", name, outStr)

	if err != nil {
		p.notifier.Send(name, webhook.EventApproveFailed, "approval failed: "+outStr, nil)
		return fmt.Errorf("approve failed: %w", err)
	}

	p.notifier.Send(name, webhook.EventApproveSuccess, "device approved for "+name, map[string]string{"output": outStr})
	return nil
}
