(defn colorize [to-color]
  (string "\e[94m" to-color "\e[0m"))

(defn hardware-probe
  [])

(defn os-probe
  []
  (def [osrel-stdout-r osrel-stdout-w] (os/pipe))
  (def [uptime-stdout-r uptime-stdout-w] (os/pipe))
  (def [uname-stdout-r uname-stdout-w] (os/pipe))
  (def [shell-stdout-r shell-stdout-w] (os/pipe))
  
  (def p
    ~{:value (capture (any (if-not "\"" 1)))
      :line  (* "PRETTY_NAME" "=" "\"" :value "\"")
      :main  (* (any (if-not :line 1)) :line)})

  (def pid (os/getpid))

  (os/execute
    ["sh" "-c"
     "ps -p $(ps -o ppid= -p $1) -o comm="
     "sh"
     (string pid)]
    :p
    {:out shell-stdout-w})
  (os/execute ["cat" "/etc/os-release"] :p {:out osrel-stdout-w})
  (os/execute ["uptime"] :p {:out uptime-stdout-w})
  (os/execute ["uname" "-a"] :p {:out uname-stdout-w})
  
  (let [os-name (get (peg/match p (:read osrel-stdout-r math/int32-max)) 0)
        kernel (get (string/split " " (:read uname-stdout-r math/int32-max)) 2)
        uptime (get (string/split " " (:read uptime-stdout-r math/int32-max)) 5)
        uptime-cleaned (string/split ":" (string/replace "," "" uptime))
        shell (string/replace "\n" "" (:read shell-stdout-r math/int32-max))]
    (print)
    (print (colorize "    OS: ") os-name)
    (print (colorize "Kernel: ") kernel)
    (print (colorize "Uptime: ") (get uptime-cleaned 0) " hours, " (get uptime-cleaned 1) " minutes")
    (print (colorize " Shell: ") shell)))

(defn main
  [& args]
  (os-probe))
