(defn colorize [to-color]
  (string "\e[94m" to-color "\e[0m"))

(defn get-cpu
  []
  (def [cpui-stdout-r cpui-stdout-w] (os/pipe))
  (os/execute ["cat" "/proc/cpuinfo"] :p {:out cpui-stdout-w})
  (def cpu-filter
    ~{:value (capture (any (if-not "\n" 1)))
      :line  (* "model name" :s+ ":" :s+ :value)
      :main  (* (any (if-not :line 1)) :line)})
  (get (peg/match cpu-filter (:read cpui-stdout-r math/int32-max)) 0))

(defn get-mem
  []
  (def [memi-stdout-r memi-stdout-w] (os/pipe))
  (os/execute ["cat" "/proc/meminfo"] :p {:out memi-stdout-w})
  
  (def mem-info (:read memi-stdout-r math/int32-max))
  
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
  
  {:mem-total           mem-total
   :mem-avail           mem-avail
   :mem-used            mem-used
   :mem-used-percentage (* (/ mem-used mem-total) 100)
   :swap-total          swap-total
   :swap-free           swap-free})

(defn get-disk-usage
  []
  (def [stdout-r stdout-w] (os/pipe))
  (os/execute ["df" "-h"] :p {:out stdout-w})
  
  # Filesystem Size Used Avail Use% Mounted
  (def du
    (->> (:read stdout-r math/int32-max)
         (peg/replace-all ~(some " ") " ")
         (peg/replace-all ~(some "G") "")
         (peg/replace-all ~(some "%") "")
         (string/split "\n")
         (filter (fn [s] (or (string/find "/dev/nvme" s) (string/find "/dev/sda" s))))
         (filter (fn [s] (not (string/find "/boot" s))))
         (map (fn [s] (string/split " " s))))))

(defn hardware-probe
  []
  (get-disk-usage)
  (let [cpu (get-cpu)
        mem (get-mem)
        disks (get-disk-usage)]
    (print (colorize "   CPU: ") cpu)
    (print (colorize "Memory: ")
           (string/format "%.2f" (get mem :mem-used))
           " GB / "
           (string/format "%.2f" (get mem :mem-total))
           " GB ("
           (math/floor (get mem :mem-used-percentage))
           "%)")

    (loop [[i du] :pairs disks]
      (print (colorize (string "Disk " (+ i 1) ": "))
             (get du 2)
             " GB / "
             (get du 1)
             " GB ("
             (get du 4)
             "%) "
             "[" (array/peek du) "]"))))

(defn get-os-release
  []
  (def [osrel-stdout-r osrel-stdout-w] (os/pipe))
  (os/execute ["cat" "/etc/os-release"] :p {:out osrel-stdout-w})
  (def p
    ~{:value (capture (any (if-not "\"" 1)))
      :line  (* "PRETTY_NAME" "=" "\"" :value "\"")
      :main  (* (any (if-not :line 1)) :line)})
  (get (peg/match p (:read osrel-stdout-r math/int32-max)) 0))

(defn get-shell
  []
  (def [shell-stdout-r shell-stdout-w] (os/pipe))
  (def pid (os/getpid))
  (os/execute
    ["sh" "-c" "ps -p $(ps -o ppid= -p $1) -o comm=" "sh" (string pid)]
    :p
    {:out shell-stdout-w})
  (string/replace "\n" "" (:read shell-stdout-r math/int32-max)))

(defn get-uptime
  []
  (def [uptime-stdout-r uptime-stdout-w] (os/pipe))
  (os/execute ["cat" "/proc/uptime"] :p {:out uptime-stdout-w})
  (let [uptime-s              (get (string/split " " (:read uptime-stdout-r math/int32-max)) 0)
        uptime-h              (math/trunc (/ (scan-number uptime-s) 3600))
        uptime-remaining-mins (math/trunc (/ (% (scan-number uptime-s) 3600) 60))]
    {:hours uptime-h :minutes uptime-remaining-mins}))

(defn get-kernel
  []
  (def [uname-stdout-r uname-stdout-w] (os/pipe))
  (os/execute ["uname" "-a"] :p {:out uname-stdout-w})
  (get (string/split " " (:read uname-stdout-r math/int32-max)) 2))

(defn os-probe
  []
  (let [os-name (get-os-release)
        kernel  (get-kernel)
        uptime  (get-uptime)
        shell   (get-shell)]
    (print (colorize "    OS: ") os-name)
    (print (colorize "Kernel: ") kernel)
    (print (colorize "Uptime: ") (get uptime :hours) " hours " (get uptime :minutes) " minutes")
    (print (colorize " Shell: ") shell)))

(defn main
  [& args]
  (print)
  (os-probe)
  (hardware-probe))
