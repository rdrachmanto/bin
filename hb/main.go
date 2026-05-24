package main

import (
	"fmt"
	"net"
	"os"
	"sync"
	"time"
	"encoding/json"
)

type ToCheck struct {
    Name string    `json:"name"`
    Address string `json:"address"`
}

func checkTCP(tc ToCheck) {
	address := net.JoinHostPort(tc.Address, "22")

	conn, err := net.DialTimeout("tcp", address, 3*time.Second)
	if err != nil {
		fmt.Printf("- %s\t\t[%s]\t\tis not accessible\n", tc.Name, tc.Address)
		return
	}
	defer conn.Close()

	fmt.Printf("- %s\t\t[%s]\t\tis accessible\n", tc.Name, tc.Address)
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

	var wg sync.WaitGroup

	for range maxWorkers {
		wg.Go(func() {
			for tc := range jobs {
				checkTCP(tc)
			}
		})
	}

	for _, tc := range tcs {
		jobs <- tc
	}

	close(jobs)

	wg.Wait()
}
