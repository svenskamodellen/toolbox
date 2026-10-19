#!/bin/zsh

cd ../kollektivavtal-autoindex

highest_tag=$(git tag -l | grep -E 'v[0-9]+' | sort -V | tail -n 1)
echo "Highest tag: ${highest_tag}"

cd ..

for dir in ./kollektivavtal-20*/ ./kollektivavtal-year; do
  if [ -d "$dir" ]; then
    echo "$dir"
    find "$dir" -type f -exec sh -c 'LC_CTYPE=C sed -i "" -E "s/kollektivavtal\/autoindex@v[0-9]+/kollektivavtal\/autoindex@${1}/g" "$2"' _ "$highest_tag" {} \;

    cd "$dir"
    if git diff --quiet; then
      echo "No changes in $dir."
    else
      git --no-pager diff
      git commit -am "Bump autoindex to ${highest_tag}"
      git push
    fi
    cd ..
  fi
done
