package core

import (
	"os"
	"strings"
	"testing"
)

func TestExportFilesWritesTargetClientDialects(t *testing.T) {
	tempDir := t.TempDir()
	withWorkingDirectory(t, tempDir)

	config := &Config{Global: GlobalConfig{
		Singbox:      SingboxOutput{Enable: true, SingleFile: true, JSON: true},
		Mihomo:       MihomoOutput{Enable: true, SingleFile: true, YAML: true},
		Surge:        AppleOutput{Enable: true, SingleFile: true},
		Loon:         AppleOutput{Enable: true, SingleFile: true},
		Shadowrocket: AppleOutput{Enable: true, SingleFile: true},
		QuantumultX:  AppleOutput{Enable: true, SingleFile: true},
	}}
	result := &ProcessedResult{
		DomRules: map[string][]string{
			"DOMAIN":         {"exact.example"},
			"DOMAIN-SUFFIX":  {"suffix.example"},
			"DOMAIN-KEYWORD": {"keyword"},
			"DOMAIN-REGEX":   {`^regex\\.example$`},
		},
		IPRules: map[string][]string{
			"IP-CIDR":  {"192.0.2.0/24"},
			"IP-CIDR6": {"2001:db8::/32"},
		},
		ExactCounts: make(map[string]int),
	}

	ExportFiles(Category{Name: "sample"}, result, config, false)

	assertContains := func(path string, expected ...string) {
		t.Helper()
		content, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		for _, item := range expected {
			if !strings.Contains(string(content), item) {
				t.Errorf("%s does not contain %q", path, item)
			}
		}
	}

	assertContains("publish/mihomo/sample.yaml", "DOMAIN,exact.example", "DOMAIN-REGEX,^regex\\\\.example$", "IP-CIDR6,2001:db8::/32")
	assertContains("publish/surge/sample.list", "DOMAIN-SUFFIX,suffix.example", "IP-CIDR,192.0.2.0/24,no-resolve")
	assertContains("publish/loon/sample.list", "DOMAIN-KEYWORD,keyword", "IP-CIDR6,2001:db8::/32,no-resolve")
	assertContains("publish/shadowrocket/sample.list", "DOMAIN,exact.example", "IP-CIDR,192.0.2.0/24,no-resolve")
	assertContains("publish/quantumultx/sample.list", "host-suffix,suffix.example,sample", "ip6-cidr,2001:db8::/32,sample")
	assertContains("publish/singbox/sample.json", `"domain_suffix"`, `"ip_cidr"`)
}
