package core

import (
	"fmt"
	"net/url"
	"os"
	"path"
	"strings"
)

func extractUpstreamName(rawURL string) string {
	u, err := url.Parse(rawURL)
	if err != nil {
		return rawURL
	}
	host := u.Host
	if colonIdx := strings.IndexByte(host, ':'); colonIdx != -1 {
		host = host[:colonIdx]
	}
	host = strings.TrimPrefix(host, "www.")
	fileName := path.Base(u.Path)
	if extIdx := strings.LastIndexByte(fileName, '.'); extIdx != -1 {
		fileName = fileName[:extIdx]
	}
	if host == "raw.githubusercontent.com" || host == "github.com" {
		parts := strings.Split(strings.TrimPrefix(u.Path, "/"), "/")
		if len(parts) >= 1 {
			return parts[0] + "/" + fileName
		}
	}
	return host + "/" + fileName
}

func buildClientDownloads(repository, targetName string, clients ResolvedClientConfig) string {
	type clientFile struct {
		label   string
		relPath string
		enabled bool
	}

	files := []clientFile{
		{label: "Clash", relPath: fmt.Sprintf("mihomo/%s.yaml", targetName), enabled: clients.Mihomo.Enable && clients.Mihomo.YAML},
		{label: "sing&#8209;box", relPath: fmt.Sprintf("singbox/%s.srs", targetName), enabled: clients.Singbox.Enable && clients.Singbox.SRS},
		{label: "Surge", relPath: fmt.Sprintf("surge/%s.list", targetName), enabled: clients.Surge.Enable},
		{label: "Loon", relPath: fmt.Sprintf("loon/%s.list", targetName), enabled: clients.Loon.Enable},
		{label: "Shadowrocket", relPath: fmt.Sprintf("shadowrocket/%s.list", targetName), enabled: clients.Shadowrocket.Enable},
		{label: "Quantumult X", relPath: fmt.Sprintf("quantumultx/%s.list", targetName), enabled: clients.QuantumultX.Enable},
	}

	links := make([]string, 0, len(files))
	for _, file := range files {
		if !file.enabled {
			continue
		}
		if _, err := os.Stat(path.Join("publish", file.relPath)); err != nil {
			continue
		}
		url := fmt.Sprintf("https://github.com/%s/raw/publish/%s", repository, file.relPath)
		links = append(links, fmt.Sprintf("[%s](%s)", file.label, url))
	}
	if len(links) == 0 {
		return "-"
	}
	return strings.Join(links, " · ")
}

func GenerateReport(results map[string]*ProcessedResult, cfg *Config) {
	const startTag = `<!-- REPORT_START -->`
	const endTag = `<!-- REPORT_END -->`
	var sb strings.Builder
	repository := os.Getenv("GITHUB_REPOSITORY")

	total := 0
	for _, cat := range cfg.Categories {
		if r, ok := results[cat.Name]; ok {
			total += r.FinalCount
			if cat.PublishWhite {
				total += r.WhiteCount
			}
		}
	}

	sb.WriteString(startTag + "\n")
	sb.WriteString(fmt.Sprintf("**当前规则总数** : **%d** \n\n", total))
	sb.WriteString("### 自动统计\n")
	sb.WriteString("| 规&#8288;则&#8288;名&#8288;称 | 最&#8288;终&#8288;数&#8288;量 | 原&#8288;始&#8288;总&#8288;数 | 增&#8288;加 | 去&#8288;除 | 去&#8288;重&#8288;率 | 上&#8288;游&#8288;明&#8288;细&nbsp;(&#8288;来&#8288;源/数&#8288;量&#8288;) | 客&#8288;户&#8288;端&#8288;文&#8288;件 |\n")
	sb.WriteString("| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |\n")

	for _, cat := range cfg.Categories {
		r, ok := results[cat.Name]
		if !ok {
			continue
		}

		baseTotal := r.RawCount + r.AddCount - r.RmCount
		rate := 0.0
		if baseTotal > 0 {
			rate = (1.0 - float64(r.FinalCount)/float64(baseTotal)) * 100
			if rate < 0 {
				rate = 0
			}
		}

		displayName := strings.ReplaceAll(cat.Name, "-", "&#8209;")
		var upDetails []string
		for _, up := range cat.Upstreams {
			if count, exists := r.UpstreamStats[up.URL]; exists && count > 0 {
				extractedName := extractUpstreamName(up.URL)
				upDetails = append(upDetails, fmt.Sprintf("[%s](%s)(%d)", extractedName, up.URL, count))
			}
		}
		for _, mergeCatName := range cat.MergeFrom {
			for _, c := range cfg.Categories {
				if c.Name == mergeCatName {
					for _, up := range c.Upstreams {
						if count, exists := r.UpstreamStats[up.URL]; exists && count > 0 {
							extractedName := extractUpstreamName(up.URL)
							upDetails = append(upDetails, fmt.Sprintf("[%s](%s)(%d)", extractedName, up.URL, count))
						}
					}
				}
			}
		}
		upStr := strings.Join(upDetails, "<br>")
		if upStr == "" {
			upStr = "-"
		}

		downloads := buildClientDownloads(repository, cat.Name, ResolveClients(cfg.Global, cat))
		sb.WriteString(fmt.Sprintf("| **%s** | %d | %d | %d | %d | %.1f%% | **%s** | %s |\n", displayName, r.FinalCount, r.RawCount, r.AddCount, r.RmCount, rate, upStr, downloads))

		if cat.PublishWhite {
			whiteName := cat.Name + "_white"
			displayNameWhite := strings.ReplaceAll(whiteName, "-", "&#8209;")

			if r.WhiteCount > 0 {
				var whiteUpDetails []string
				for _, up := range cat.Upstreams {
					if wCount, exists := r.WhiteUpstreamStats[up.URL]; exists && wCount > 0 {
						extractedName := extractUpstreamName(up.URL)
						whiteUpDetails = append(whiteUpDetails, fmt.Sprintf("[%s](%s)(%d)", extractedName, up.URL, wCount))
					}
				}
				whiteUpStr := strings.Join(whiteUpDetails, "<br>")
				if whiteUpStr == "" {
					whiteUpStr = "-"
				}
				downloads := buildClientDownloads(repository, whiteName, ResolveClients(cfg.Global, cat))
				sb.WriteString(fmt.Sprintf("| **%s** | %d | %d | 0 | 0 | 0.0%% | **%s** | %s |\n", displayNameWhite, r.WhiteCount, r.WhiteCount, whiteUpStr, downloads))
			}
		}
	}
	sb.WriteString("\n")

	sb.WriteString("\n" + endTag + "\n")
	reportTitle := "# 📦 DIY-Ruleset 自动编译报告\n\n**该页面由 GitHub Actions 每日自动生成**\n\n"

	os.MkdirAll("publish", 0755)
	_ = os.WriteFile("publish/README.md", []byte(reportTitle+sb.String()), 0644)
}
