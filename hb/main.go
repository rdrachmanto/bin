package main

import (
	"encoding/json"
	"fmt"
	"github.com/rodaine/table"
	"net"
	"net/http"
	"os"
	"sync"
	"time"
)

type ToCheck struct {
	Name    string `json:"name"`
	Address string `json:"address"`
}

func checkAddr(tc ToCheck) [3]string {
	ip := net.ParseIP(tc.Address)
	if ip == nil {
		resp, err := http.Get(tc.Address)
		if err != nil {
			return [3]string{tc.Name, tc.Address, "No"}
		}
		defer resp.Body.Close()
	} else {
		address := net.JoinHostPort(tc.Address, "22")
		conn, err := net.DialTimeout("tcp", address, 3*time.Second)
		if err != nil {
			return [3]string{tc.Name, tc.Address, "No"}
		}
		defer conn.Close()
	}
	return [3]string{tc.Name, tc.Address, "Yes"}
}

func readConfig(path string) ([]ToCheck, error) {
	cfg, err := os.UserConfigDir()
	if err != nil {
		return nil, err
	}

	if path == "" {
		path = cfg + "/hb/config.json"
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var tcs []ToCheck

	err = json.Unmarshal([]byte(raw), &tcs)
	if err != nil {
		return nil, err
	}

	fmt.Printf("\nReading from: %s\n\n", path)

	return tcs, nil
}

func main() {
	path := ""
	if len(os.Args) > 1 {
		path = os.Args[1]
	}

	tcs, err := readConfig(path)
	if err != nil {
		fmt.Println(fmt.Errorf("Failed to get or process config file: %w", err))
		return
	}

	const maxWorkers = 3

	jobs := make(chan ToCheck)

	// Buffered results channel
	// So we don't need another goroutine to send, wait for jobs to finish and to close the channels
	// while main goroutine is busy consuming the results channel
	results := make(chan [3]string, len(tcs))

	var wg sync.WaitGroup

	// 3 worker goroutines to check addresses specified from the config!
	for range maxWorkers {
		wg.Go(func() {
			for tc := range jobs {
				result := checkAddr(tc)
				results <- result
			}
		})
	}

	for _, tc := range tcs {
		jobs <- tc
	}

	close(jobs)
	wg.Wait()
	close(results)

	tbl := table.New("Name", "Address", "Reachable")
	for r := range results {
		tbl.AddRow(r[0], r[1], r[2])
	}

	tbl.Print()
}
