package core

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
)

func CompileAll(cfg *Config) error {
	fmt.Println("📦 正在编译二进制规则集 (SRS/MRS)...")

	needSRS, needMRS := false, false
	for _, cat := range cfg.Categories {
		out := ResolveClients(cfg.Global, cat)
		if out.Singbox.SRS {
			needSRS = true
		}
		if out.Mihomo.MRS {
			needMRS = true
		}
	}

	hasSingbox := checkCommand("sing-box") && needSRS
	hasMihomo := checkCommand("mihomo") && needMRS

	if !hasSingbox && needSRS {
		return fmt.Errorf("已启用 SRS 输出，但未检测到 sing-box")
	}
	if !hasMihomo && needMRS {
		return fmt.Errorf("已启用 MRS 输出，但未检测到 mihomo")
	}

	var wg sync.WaitGroup
	sem := make(chan struct{}, 4)
	var compileErrors []error
	var errorMu sync.Mutex
	recordError := func(err error) {
		errorMu.Lock()
		compileErrors = append(compileErrors, err)
		errorMu.Unlock()
	}

	if hasSingbox {
		files, err := filepath.Glob("process" + "/srs_*.json")
		if err != nil {
			return fmt.Errorf("查找 SRS 输入: %w", err)
		}
		if len(files) == 0 {
			return fmt.Errorf("已启用 SRS 输出，但没有生成 SRS 输入")
		}

		for _, file := range files {
			wg.Add(1)

			go func(f string) {
				defer wg.Done()
				sem <- struct{}{}
				defer func() { <-sem }()

				baseName := strings.TrimPrefix(filepath.Base(f), "srs_")
				outName := strings.TrimSuffix(baseName, ".json") + ".srs"
				outDir := "publish/singbox"

				if strings.HasPrefix(baseName, "cnip_") {
					outDir = "publish/cnip"
					outName = strings.TrimPrefix(outName, "cnip_")
				}

				outPath := filepath.Join(outDir, outName)

				output, err := exec.Command(GetExecPath("sing-box"), "rule-set", "compile", f, "-o", outPath).CombinedOutput()
				if err != nil {
					recordError(fmt.Errorf("sing-box 编译 %s: %w: %s", f, err, strings.TrimSpace(string(output))))
					return
				}
				if info, err := os.Stat(outPath); err != nil || info.Size() == 0 {
					recordError(fmt.Errorf("sing-box 未生成有效文件 %s", outPath))
				}
			}(file)
		}
	}

	if hasMihomo {
		domFiles, err := filepath.Glob("process" + "/*_mihomo_domain.txt")
		if err != nil {
			return fmt.Errorf("查找 MRS 域名输入: %w", err)
		}
		for _, file := range domFiles {
			wg.Add(1)

			go func(f string) {
				defer wg.Done()
				sem <- struct{}{}
				defer func() { <-sem }()

				catName := strings.TrimSuffix(filepath.Base(f), "_mihomo_domain.txt")
				outFile := fmt.Sprintf("%s/%s.mrs", "publish/mihomo", catName)
				output, err := exec.Command(GetExecPath("mihomo"), "convert-ruleset", "domain", "text", f, outFile).CombinedOutput()
				if err != nil {
					recordError(fmt.Errorf("mihomo 编译域名规则 %s: %w: %s", f, err, strings.TrimSpace(string(output))))
					return
				}
				if info, err := os.Stat(outFile); err != nil || info.Size() == 0 {
					recordError(fmt.Errorf("mihomo 未生成有效文件 %s", outFile))
				}
			}(file)
		}

		ipFiles, err := filepath.Glob("process" + "/*_mihomo_ip.txt")
		if err != nil {
			return fmt.Errorf("查找 MRS IP 输入: %w", err)
		}
		if len(domFiles)+len(ipFiles) == 0 {
			return fmt.Errorf("已启用 MRS 输出，但没有生成 MRS 输入")
		}
		for _, file := range ipFiles {
			wg.Add(1)

			go func(f string) {
				defer wg.Done()
				sem <- struct{}{}
				defer func() { <-sem }()

				catName := strings.TrimSuffix(filepath.Base(f), "_mihomo_ip.txt")
				outDir := "publish/mihomo"
				outFile := ""
				if strings.HasPrefix(catName, "cnip_") {
					outDir = "publish/cnip"
					outFile = fmt.Sprintf("%s/%s.mrs", outDir, strings.TrimPrefix(catName, "cnip_"))
				} else {
					outFile = fmt.Sprintf("%s/%s_ip.mrs", outDir, catName)
				}
				output, err := exec.Command(GetExecPath("mihomo"), "convert-ruleset", "ipcidr", "text", f, outFile).CombinedOutput()
				if err != nil {
					recordError(fmt.Errorf("mihomo 编译 IP 规则 %s: %w: %s", f, err, strings.TrimSpace(string(output))))
					return
				}
				if info, err := os.Stat(outFile); err != nil || info.Size() == 0 {
					recordError(fmt.Errorf("mihomo 未生成有效文件 %s", outFile))
				}
			}(file)
		}
	}
	wg.Wait()
	return errors.Join(compileErrors...)
}

func GetExecPath(name string) string {
	exeName := name
	if runtime.GOOS == "windows" {
		exeName += ".exe"
	}
	if _, err := os.Stat(exeName); err == nil {
		if absPath, err := filepath.Abs(exeName); err == nil {
			return absPath
		}
		return "./" + exeName
	}
	if path, err := exec.LookPath(exeName); err == nil {
		return path
	}
	return name
}

func checkCommand(name string) bool {
	exeName := name
	if runtime.GOOS == "windows" {
		exeName += ".exe"
	}
	if _, err := os.Stat(exeName); err == nil {
		return true
	}
	_, err := exec.LookPath(exeName)
	return err == nil
}
