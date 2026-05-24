package main

import (
	"fmt"
	"net"
	"sync"
	"time"
)

func checkTCP(ip string) {
	address := net.JoinHostPort(ip, "22")

	conn, err := net.DialTimeout("tcp", address, 3*time.Second)
	if err != nil {
		fmt.Println(ip + " is not accessible")
		return
	}
	defer conn.Close()

	fmt.Println(ip + " is accessible")
}

func main() {
	ips := []string{
		"172.22.85.98",
		"172.22.85.96",
	}

	const maxWorkers = 3

	jobs := make(chan string)

	var wg sync.WaitGroup

	for range maxWorkers {
		// Old form
		// wg.Add(1)
		// go func() {
		// 	defer wg.Done()

		// 	for url := range jobs {
		// 		checkUrl(url)
		// 	}
		// }()

		// New form
		wg.Go(func() {
			for ip := range jobs {
				checkTCP(ip)
			}
		})
	}

	for _, ip := range ips {
		jobs <- ip
	}

	close(jobs)

	wg.Wait()
}
