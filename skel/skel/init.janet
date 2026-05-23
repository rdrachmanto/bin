(import spork/argparse :prefix "")
(import spork/sh)

(def readme
  ````
## $title
````)

(def license
  ````
MIT License

Copyright (c) $year $author

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
````)

(defn make-meta
  [project-name author]
  (spit (string project-name "/README.md")
        (string/replace "$title" project-name readme))
  (let [license-with-year (string/replace "$year" (get (os/date) :year) license)
        license-completed (string/replace "$author" author license-with-year)]
    (spit (string project-name "/LICENSE") license-completed)))

(def python-main
  ````
def main():
    print("Hello world!")

if __name__ == "__main__":
    main()
````)

(defn make-python
  [project-name author]
  (def project-package-path (string project-name "/src/" project-name))
  (sh/make-new-file (string project-package-path "/__init__.py"))
  (sh/make-new-file (string project-name "/pyproject.toml"))
  (sh/make-new-file (string project-name "/requirements.txt"))

  (spit (string project-package-path "/main.py") python-main)
  
  (make-meta project-name author)

  (sh/create-dirs (string project-name "/notebooks"))
  (sh/create-dirs (string project-name "/results"))
  (sh/create-dirs (string project-name "/scripts")))

(def html
  ````
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8"/>
    <title>$project</title>
    <link href="./static/style.css" rel="stylesheet"/>
  </head>
  <body>
    <h1>$project</h1>
  </body>
  <script src="./static/index.js"></script>
</html>
````)

(defn make-site
  [project-name author]
  (def static (string project-name "/static"))
  (sh/make-new-file (string static "/style.css"))
  (sh/make-new-file (string static "/index.js"))

  (make-meta project-name author)

  (spit (string project-name "/index.html")
        (string/replace-all "$project" project-name html)))

(def project-types ["python" "site" "orgsite"])

(def cliargs
  ["Welcome to skel!"
   "project" {:kind :option
              :short "p"
              :help "Project to bootstrap"
              :required true}])

(defn main
  [& args]
  (def arg (argparse ;cliargs))
  (unless arg
    (os/exit 1))
  
  (def project-type
    (->> (get arg "project")
         (string/trim)
         (string/ascii-lower)))
  
  (unless (index-of project-type project-types)
    (print "\nProject not supported, aborting....")
    (print "\nSee `skel -h` for supported projects")
    (os/exit 1))
  
  (def project-name (string/trim (getline "Project name? ")))
  (def author-name (string/trim (getline "Author? ")))

  (case project-type
    "python" (make-python project-name author-name)
    "site" (make-site project-name author-name))
  
  (print (string "\nFinished bootstrapping " (os/cwd) "/" project-name)))
