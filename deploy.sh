#!/usr/bin/env bash

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
to_deploy=(
  "skel/build/skel"
  "hb/bin/hb"
  "probe/build/probe"
  "e"
  sh/scripts/*
)

for td in "${to_deploy[@]}"; do
  src="$repo_dir/$td"
  name="$(basename "$td")"
  dest=$HOME/.local/bin/$name
  
  ln -sfn "$src" "$dest"
  echo "Linked $td --> $dest"
done
