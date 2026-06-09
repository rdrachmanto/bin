(import spork/argparse :prefix "")
(use spork/sh)
(use spork/sh-dsl)

(defn get-cpu
  []
  (def cpu-info ($<_ cat /proc/cpuinfo))
  
  (def cpu-filter
    ~{:value (capture (any (if-not "\n" 1)))
      :line  (* "model name" :s+ ":" :s+ :value)
      :main  (* (any (if-not :line 1)) :line)})
  (def core-filter
    ~{:value (capture (any (if-not "\n" 1)))
      :line  (* "cpu cores" :s+ ":" :s+ :value)
      :main  (* (any (if-not :line 1)) :line)})
  (def thread-filter
    ~{:value (capture (any (if-not "\n" 1)))
      :line  (* "siblings" :s+ ":" :s+ :value)
      :main  (* (any (if-not :line 1)) :line)})
  
  {:cpu-name       (get (peg/match cpu-filter cpu-info) 0)
   :cpu-cores-ct   (get (peg/match core-filter cpu-info) 0)
   :cpu-threads-ct (get (peg/match thread-filter cpu-info) 0)})

(defn get-mem
  []
  (def mem-info ($<_ cat /proc/meminfo))
  
  (def mem-total-filter
    ~{:line (* "MemTotal:" :s+ (capture :d+) :s+ "kB\n")
      :main (* (any (if-not :line 1)) :line)})
  (def mem-avail-filter
    ~{:line (* "MemAvailable:" :s+ (capture :d+) :s+ "kB\n")
      :main (* (any (if-not :line 1)) :line)})
  (def swap-total-filter
    ~{:line (* "SwapTotal:" :s+ (capture :d+) :s+ "kB\n")
      :main (* (any (if-not :line 1)) :line)})
  (def swap-free-filter
    ~{:line (* "SwapFree:" :s+ (capture :d+) :s+ "kB\n")
      :main (* (any (if-not :line 1)) :line)})

  (def mem-total
    (-> (get (peg/match mem-total-filter mem-info) 0)
        (scan-number)
        (/ 1_000_000)))
  (def mem-avail
    (-> (get (peg/match mem-avail-filter mem-info) 0)
        (scan-number)
        (/ 1_000_000)))
  (def swap-total
    (-> (get (peg/match swap-total-filter mem-info) 0)
        (scan-number)
        (/ 1_000_000)))
  (def swap-free
    (-> (get (peg/match swap-free-filter mem-info) 0)
        (scan-number)
        (/ 1_000_000)))
  (def mem-used (- mem-total mem-avail))
  (def swap-used (- swap-total swap-free))
  
  {:mem-total  mem-total
   :mem-avail  mem-avail
   :mem-used   mem-used
   :swap-total swap-total
   :swap-free  swap-free
   :swap-used  swap-used})

(defn get-hardware-family
  []
  ($<_ cat /sys/devices/virtual/dmi/id/product_family))

(defn get-disk-usage
  []
  # Filesystem Size Used Avail Use% Mounted
  (def du
    (->> ($<_ df -h)
         (peg/replace-all ~(some " ") " ")
         (peg/replace-all ~(some "G") "")
         (peg/replace-all ~(some "%") "")
         (string/split "\n")
         (filter (fn [s] (or (string/find "/dev/nvme" s) (string/find "/dev/sda" s))))
         (filter (fn [s] (not (string/find "/boot" s))))
         (map (fn [s] (string/split " " s))))))

(defn get-hardware-model
  []
  ($<_ cat /sys/devices/virtual/dmi/id/product_name))

(defn get-os-release
  []
  (def p
    ~{:value (capture (any (if-not "\"" 1)))
      :line  (* "PRETTY_NAME" "=" "\"" :value "\"")
      :main  (* (any (if-not :line 1)) :line)})
  (get (peg/match p ($<_ cat /etc/os-release)) 0))

(defn get-init
  []
  ($<_ ps -p 1 -o comm=))

(defn get-arch
  []
  ($<_ uname -m))

(defn get-firmware-info
  []
  {:bios-version ($<_ cat /sys/devices/virtual/dmi/id/bios_version)
   :bios-date    ($<_ cat /sys/devices/virtual/dmi/id/bios_date)
   })

(defn get-netinfo
  []
  (def ips
    (->> ($<_ ip -o -4 addr show | awk "{print $2, $4}")
         (string/split "\n")))
  {:gateway ($<_ ip route | awk "/default/ {print $3}")
   :ips     ips
   :dns     ($<_ grep -oE `\b([0-9]{1,3}\.){3}[0-9]{1,3}\b` /etc/resolv.conf)})

(defn get-shell  []
  (def [stdout-r stdout-w] (os/pipe))
  (def pid (os/getpid))
  (os/execute
    ["sh" "-c" "ps -p $(ps -o ppid= -p $1) -o comm=" "sh" (string pid)]
    :p
    {:out stdout-w})
  (string/replace "\n" "" (:read stdout-r math/int32-max)))

(defn get-uptime
  []
  (def uptime ($<_ cat /proc/uptime))
  (let [uptime-s              (get (string/split " " (string uptime)) 0)
        uptime-h              (math/trunc (/ (scan-number uptime-s) 3600))
        uptime-remaining-mins (math/trunc (/ (% (scan-number uptime-s) 3600) 60))]
    {:hours uptime-h :minutes uptime-remaining-mins}))

(defn get-kernel
  []
  (->> (string ($<_ uname -s) ($<_ uname -r))
       (string/replace-all "\n" " ")))

(defn get-battery-info
  []
  (def battery-info
    (->> ($<_ upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep -E "energy|cycle")
         (peg/replace-all ~(some " ") " ")
         (peg/replace-all ~(+ (some "Wh") (some ":") (some "W")) "")
         (string/split "\n")
         (map (fn [s]
                (->> s
                     (string/trim)
                     (string/split " "))))
         (from-pairs))))

(defn colorize [to-color]
  (string "\e[94m" to-color "\e[0m"))

(defn strings-rjust [lsos]
  (def longest (max ;(map length lsos)))
  (->> lsos
       (map (fn [s] (string/format (string "%" longest "s") s)))))

(defn process-probes
  [probes]
  (def titles @[])
  (each p probes (array/push titles (p 0)))

  (def rjust-titles (strings-rjust titles))
  (loop [[i p] :pairs probes]
    (put p 0 (rjust-titles i))
    (print (colorize (p 0)) (p 1))))

(defn probe
  []
  (let [host    (get-hardware-family)
        os-name (get-os-release)
        kernel  (get-kernel)
        uptime  (get-uptime)
        shell   (get-shell)
        cpu     (get-cpu)
        mem     (get-mem)
        disks   (get-disk-usage)]
    # A bit ugly but will do...
    (def probes @[@["Host: "   host]
                  @["OS: "     os-name]
                  @["Kernel: " kernel]
                  @["Shell: "  shell]
                  @["Uptime: " (string (uptime :hours) "h " (uptime :minutes) "m")]
                  @["CPU: "    (cpu :cpu-name)]
                  @["Memory: " (string (string/format "%.1f" (mem :mem-used)) " GB / "
                                       (string/format "%.1f" (mem :mem-total)) " GB")]
                  @["Swap: "   (string (string/format "%.1f" (mem :swap-used)) " GB / "
                                       (string/format "%.1f" (mem :swap-total)) " GB")]])
    # Let's pretend this is like (add-to-list) in elisp...
    (loop [[i du] :pairs disks]
      (array/push probes @[(string "Disk " (+ i 1) ": ")
                           (string (du 2) " GB / " (du 1) " GB [" (array/peek du) "]")]))

    (process-probes probes)))

(defn long-probe
  []
  (let [host    (get-hardware-family)
        model   (get-hardware-model)
        arch    (get-arch)
        init    (get-init)
        os-name (get-os-release)
        kernel  (get-kernel)
        uptime  (get-uptime)
        shell   (get-shell)
        cpu     (get-cpu)
        mem     (get-mem)
        disks   (get-disk-usage)
        netinfo (get-netinfo)
        bios    (get-firmware-info)
        battery (get-battery-info)]
    # Even uglier
    (def probes @[@["Host: " host]
                  @["Host Serial #: " model]
                  @["Architecture: " arch]
                  @["OS: " os-name]
                  @["Kernel: " kernel]
                  @["Init: " init]
                  @["Shell: " shell]
                  @["Uptime: " (string (uptime :hours) "h " (uptime :minutes) "m")]
                  @["CPU: " (cpu :cpu-name)]
                  @["Cores: " (string (cpu :cpu-cores-ct) " cores " (cpu :cpu-threads-ct) " threads")]
                  @["Memory: " (string (string/format "%.1f" (mem :mem-used)) " GB / "
                                       (string/format "%.1f" (mem :mem-total)) " GB")]
                  @["Swap: "   (string (string/format "%.1f" (mem :swap-used)) " GB / "
                                       (string/format "%.1f" (mem :swap-total)) " GB")]])
    (loop [[i du] :pairs disks]
      (array/push probes @[(string "Disk " (+ i 1) ": ")
                           (string (du 2) " GB / " (du 1) " GB [" (array/peek du) "]")]))
    
    (array/push probes @["Gateway: " (netinfo :gateway)])
    (loop [[i ip] :pairs (netinfo :ips)]
      (array/push probes @[(string "IP " (+ i 1) ": ")
                           ip]))
    (array/push probes @["DNS: " (netinfo :dns)])

    (array/concat probes @[@["Current Battery: " (string (battery "energy") " Wh")]
                           @["Full Battery: " (string (battery "energy-full") " Wh")]
                           @["Original Capacity: " (string (battery "energy-full-design") " Wh")]
                           @["Energy Rate: " (string battery "energy-rate") " W"]
                           @["Charge Cycles: " (string battery "charge-cycles")]
                           @["BIOS Version: " (bios :bios-version)]
                           @["BIOS Date: " (bios :bios-date)]])
    (process-probes probes)))

(def argparams
  ["Probe your system's hardware and OS details"
   "all" {:kind :flag
          :short "a"
          :help "Show larger probes"
          :required false}])

(defn main
  [& args]
  (def arg (argparse ;argparams))
  (unless arg
    (os/exit 1))
  
  (if (get arg "all")
    (long-probe)
    (probe)))
