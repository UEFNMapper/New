#!/usr/bin/env bash
# Convert every FBX under models_src (that has no glTF twin) to GLB in models_src/_glb/<pack>/<name>.glb
cd /home/user/tools/models_src
mkdir -p _glb
find . -path ./_glb -prune -o -name "*.fbx" -print | while read f; do
  pack=$(echo "$f" | cut -d/ -f2); name=$(basename "$f" .fbx)
  sub=$(dirname "$f" | sed 's#^\./[^/]*/##; s#/FBX##; s#FBX##; s#/#_#g')
  out="_glb/$pack/${sub:+${sub}_}$name.glb"
  [ -s "$out" ] && continue
  mkdir -p "_glb/$pack"
  /home/user/tools/FBX2glTF-linux-x64 -b -i "$f" -o "$out" > "_glb/$pack/${sub:+${sub}_}$name.log" 2>&1 || echo "FAIL $f"
done
echo converted $(find _glb -name "*.glb" | wc -l)
