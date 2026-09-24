package core

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func withWorkingDirectory(t *testing.T, path string) {
	t.Helper()
	previous, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(path); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.Chdir(previous); err != nil {
			t.Errorf("restore working directory: %v", err)
		}
	})
}

func srsConfig() *Config {
	return &Config{Categories: []Category{{
		Name:    "test",
		Singbox: &CatSingboxOutput{SRS: boolPointer(true)},
	}}}
}

func boolPointer(value bool) *bool {
	return &value
}

func TestCompileAllRequiresSingBox(t *testing.T) {
	tempDir := t.TempDir()
	withWorkingDirectory(t, tempDir)
	t.Setenv("PATH", tempDir)

	err := CompileAll(srsConfig())
	if err == nil || !strings.Contains(err.Error(), "未检测到 sing-box") {
		t.Fatalf("expected missing sing-box error, got %v", err)
	}
}

func TestCompileAllReturnsCompilerFailure(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell fixture is POSIX-only")
	}

	tempDir := t.TempDir()
	withWorkingDirectory(t, tempDir)
	if err := os.MkdirAll("process", 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile("process/srs_test.json", []byte(`{"version":5,"rules":[]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	compiler := filepath.Join(tempDir, "sing-box")
	if err := os.WriteFile(compiler, []byte("#!/bin/sh\necho fixture failure >&2\nexit 1\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", tempDir)

	err := CompileAll(srsConfig())
	if err == nil || !strings.Contains(err.Error(), "fixture failure") {
		t.Fatalf("expected compiler failure, got %v", err)
	}
}
