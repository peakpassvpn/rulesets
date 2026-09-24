package core

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGenerateReportUsesSingleTableWithSixClientLinks(t *testing.T) {
	tempDir := t.TempDir()
	withWorkingDirectory(t, tempDir)
	t.Setenv("GITHUB_REPOSITORY", "peakpassvpn/rulesets")

	files := []string{
		"mihomo/sample.yaml",
		"singbox/sample.srs",
		"surge/sample.list",
		"loon/sample.list",
		"shadowrocket/sample.list",
		"quantumultx/sample.list",
	}
	for _, name := range files {
		fullPath := filepath.Join("publish", name)
		if err := os.MkdirAll(filepath.Dir(fullPath), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(fullPath, []byte("rule\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	cfg := &Config{
		Global: GlobalConfig{
			Singbox:      SingboxOutput{Enable: true, SingleFile: true, SRS: true},
			Mihomo:       MihomoOutput{Enable: true, SingleFile: true, YAML: true},
			Surge:        AppleOutput{Enable: true, SingleFile: true},
			Loon:         AppleOutput{Enable: true, SingleFile: true},
			Shadowrocket: AppleOutput{Enable: true, SingleFile: true},
			QuantumultX:  AppleOutput{Enable: true, SingleFile: true},
		},
		Categories: []Category{{Name: "sample"}},
	}
	results := map[string]*ProcessedResult{
		"sample": {RawCount: 6, FinalCount: 4},
	}

	GenerateReport(results, cfg)

	data, err := os.ReadFile("publish/README.md")
	if err != nil {
		t.Fatal(err)
	}
	report := string(data)
	if got := strings.Count(report, "\n| :--- |"); got != 1 {
		t.Fatalf("expected one markdown table, got %d\n%s", got, report)
	}
	for _, want := range []string{
		"客&#8288;户&#8288;端&#8288;文&#8288;件",
		"[Clash](https://github.com/peakpassvpn/rulesets/raw/publish/mihomo/sample.yaml)",
		"[sing&#8209;box](https://github.com/peakpassvpn/rulesets/raw/publish/singbox/sample.srs)",
		"[Surge](https://github.com/peakpassvpn/rulesets/raw/publish/surge/sample.list)",
		"[Loon](https://github.com/peakpassvpn/rulesets/raw/publish/loon/sample.list)",
		"[Shadowrocket](https://github.com/peakpassvpn/rulesets/raw/publish/shadowrocket/sample.list)",
		"[Quantumult X](https://github.com/peakpassvpn/rulesets/raw/publish/quantumultx/sample.list)",
	} {
		if !strings.Contains(report, want) {
			t.Errorf("report does not contain %q", want)
		}
	}
	for _, unwanted := range []string{
		"Sing-Box & Mihomo",
		"Loon / Surge / Quantumultx / Shadowrocket",
	} {
		if strings.Contains(report, unwanted) {
			t.Errorf("report still contains obsolete section %q", unwanted)
		}
	}
}
