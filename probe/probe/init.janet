(import spork/argparse :prefix "")
(use spork/sh)
(use spork/sh-dsl)

(defn colorize [to-color]
  (string "\e[94m" to-color "\e[0m"))

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
    (print (colorize "  Host: ") host)
    (print (colorize "    OS: ") os-name)
    (print (colorize "Kernel: ") kernel)
    (print (colorize " Shell: ") shell)
    (print (colorize "Uptime: ") (get uptime :hours) "h " (get uptime :minutes) "m")
    (print (colorize "   CPU: ") (get cpu :cpu-name))
    (print (colorize "Memory: ")
           (string/format "%.2f" (get mem :mem-used))
           " GB / "
           (string/format "%.2f" (get mem :mem-total))
           " GB")
    (print (colorize "  Swap: ")
           (string/format "%.2f" (get mem :swap-used))
           " GB / "
           (string/format "%.2f" (get mem :swap-total))
           " GB")
    (loop [[i du] :pairs disks]
      (print (colorize (string "Disk " (+ i 1) ": "))
             (get du 2)
             " GB / "
             (get du 1)
             " GB "
             "[" (array/peek du) "]"))))

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
    (print (colorize "             Host: ") host)
    (print (colorize "    Host Serial #: ") model)
    (print (colorize "     Architecture: ") arch)
    (print (colorize "               OS: ") os-name)
    (print (colorize "           Kernel: ") kernel)
    (print (colorize "             Init: ") init)
    (print (colorize "            Shell: ") shell)
    (print (colorize "           Uptime: ") (get uptime :hours) "h " (get uptime :minutes) "m")

    (print)
    (print (colorize "              CPU: ") (get cpu :cpu-name))
    (print (colorize "            Cores: ") (get cpu :cpu-cores-ct) " cores " (get cpu :cpu-threads-ct) " threads")
    (print (colorize "           Memory: ")
           (string/format "%.2f" (get mem :mem-used))
           " GB / "
           (string/format "%.2f" (get mem :mem-total))
           " GB")
    (print (colorize "             Swap: ")
           (string/format "%.2f" (get mem :swap-used))
           " GB / "
           (string/format "%.2f" (get mem :swap-total))
           " GB")
    (loop [[i du] :pairs disks]
      (print (colorize (string "           Disk " (+ i 1) ": "))
             (get du 2)
             " GB / "
             (get du 1)
             " GB "
             "[" (array/peek du) "]"))

    (print)
    (print (colorize "          Gateway: ") (get netinfo :gateway))
    (loop [[i ip] :pairs (get netinfo :ips)]
      (print (colorize (string "             IP " (+ i 1) ": "))
             ip))
    (print (colorize "              DNS: ") (get netinfo :dns))

    (print)
    (print (colorize "  Current Battery: ") (get battery "energy") " Wh")
    (print (colorize "     Full Battery: ") (get battery "energy-full") " Wh")
    (print (colorize "Original Capacity: ") (get battery "energy-full-design") " Wh")
    (print (colorize "      Energy Rate: ") (get battery "energy-rate") " W")
    (print (colorize "    Charge Cycles: ") (get battery "charge-cycles"))

    (print)
    (print (colorize "     BIOS Version: " ) (get bios :bios-version))
    (print (colorize "        BIOS Date: " ) (get bios :bios-date))))

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
